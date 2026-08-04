import SwiftUI
import SwiftData

private let companionChoices = ["spark", "orbit", "pixel", "comet", "bop"]
private let colorChoices = [
    "#6F2DBD", "#AF52DE", "#007AFF", "#00A6A6", "#34C759",
    "#F4C430", "#FF9500", "#F26B5B", "#FF2D55", "#8E6E53"
]

enum AdaptiveLayout {
    static let readableContentMaximum: CGFloat = 1_100
    static let managementContentMaximum: CGFloat = 900

    static func dashboardColumns(for width: CGFloat) -> Int {
        width >= 760 ? 2 : 1
    }

    static func questColumns(for width: CGFloat) -> Int {
        width >= 700 ? 2 : 1
    }
}

enum ProfilePalette {
    static func name(for hex: String) -> String {
        switch hex.uppercased() {
        case "#6F2DBD": return "Purple"
        case "#AF52DE": return "Violet"
        case "#007AFF": return "Blue"
        case "#00A6A6": return "Teal"
        case "#34C759": return "Green"
        case "#F4C430": return "Gold"
        case "#F26B5B": return "Coral"
        case "#FF9500": return "Orange"
        case "#FF2D55": return "Pink"
        case "#8E6E53": return "Cocoa"
        default: return "Custom"
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var households: [Household]
    @Query(sort: \Person.createdAt) private var people: [Person]
    @Query private var deviceSettings: [LocalDeviceSettings]
    @Query private var pendingInvitations: [PendingShareInvitation]
    @State private var shareInbox = CloudShareInbox.shared

    private var activeAccent: Color {
        guard let selectedID = app.selectedPersonID,
              let selected = people.first(where: {
                  $0.id == selectedID && $0.deletedAt == nil
              }) else {
            return KyndynTheme.brand
        }
        return Color(hex: selected.colorHex)
    }

    var body: some View {
        ZStack {
            KyndynScreenBackground()
            Group {
                if shareInbox.pending != nil ||
                    pendingInvitations.contains(where: { $0.stateRaw == "pending" }) {
                    InvitationLandingView()
                } else if households.isEmpty {
                    OnboardingView()
                } else if app.selectedPersonID == nil &&
                            deviceSettings.first?.showsHouseholdDashboard != true {
                    ProfilePickerView()
                } else {
                    MainView()
                }
            }
            .opacity(app.isPreparing ? 0 : 1)
            if app.isPreparing {
                VStack(spacing: 14) {
                    Image(systemName: "leaf.fill").font(.system(size: 52)).foregroundStyle(.purple)
                    Text("kyndyn").font(.largeTitle.bold())
                    ProgressView().accessibilityLabel("Opening kyndyn")
                }
                .transition(.opacity)
            }
        }
        .tint(activeAccent)
        .task {
            if deviceSettings.isEmpty, !households.isEmpty {
                _ = try? app.ensureLocalDeviceSettings(in: context)
            }
            if let invitation = shareInbox.pending,
               !pendingInvitations.contains(where: {
                   $0.shareIdentifier == invitation.shareIdentifier
               }) {
                context.insert(PendingShareInvitation(
                    shareIdentifier: invitation.shareIdentifier,
                    expectedSchemaVersion: invitation.schemaVersion))
                try? context.save()
            }
            if app.selectedPersonID == nil,
               let stored = deviceSettings.first?.selectedPersonID,
               people.contains(where: { $0.id == stored && $0.deletedAt == nil }) {
                app.selectedPersonID = stored
            }
        }
        .animation(.easeOut(duration: 0.2), value: app.isPreparing)
    }
}

struct InvitationLandingView: View {
    @Environment(InvitationRouter.self) private var router
    @Environment(CloudSyncController.self) private var sync
    @Environment(\.modelContext) private var context
    @Query private var storedInvitations: [PendingShareInvitation]
    @State private var inbox = CloudShareInbox.shared

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Family invitation", systemImage: "person.2.badge.plus")
            } description: {
                Text("Someone invited this device to a kyndyn family. kyndyn will verify it before creating any sample household.")
            } actions: {
                Button("Review invitation") {
                    guard let invitation = inbox.pending else { return }
                    router.receive(invitation)
                    Task {
                        if await sync.acceptInvitation(invitation, context: context) != nil {
                            storedInvitations.first {
                                $0.shareIdentifier == invitation.shareIdentifier
                            }?.stateRaw = "joined"
                            try? context.save()
                            inbox.clear()
                            AutomaticSyncSignalCenter.shared.send(.shareAccepted)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(sync.isWorking)
                .accessibilityHint("Validates the shared kyndyn household")
                Text(sync.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Invitation status, \(sync.statusMessage)")
            }
            .navigationTitle("Join kyndyn family")
        }
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(CloudSyncController.self) private var sync
    @EnvironmentObject private var parentAccess: ParentAccessController
    @Environment(\.modelContext) private var context
    @State private var isWorking = false
    @State private var showSetup = false
    @State private var showImporter = false
    @State private var pendingImportData: Data?
    @State private var pendingImportKind: TransferReport.Source?
    @State private var importReport: TransferReport?
    @State private var showImportConfirmation = false
    @State private var showCloudRecovery = false
    @State private var showRestoreOptions = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "leaf.fill").font(.system(size: 58)).foregroundStyle(.purple)
                Text("Welcome to kyndyn").font(.largeTitle.bold()).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("A calm home base for quests, progress, and family wins.")
                    .font(.title3).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button {
                    showSetup = true
                } label: {
                    Label("Set up my family", systemImage: "house.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                Button {
                    showRestoreOptions = true
                } label: {
                    Label("Restore or import a household", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityHint("Recover from iCloud or restore a backup")

                Button {
                    isWorking = true
                    do { try app.seedSample(into: context) }
                    catch { app.errorMessage = error.localizedDescription }
                    isWorking = false
                } label: {
                    Label("Explore with sample data", systemImage: "sparkles")
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .disabled(isWorking)
            }
            .padding(32).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background(KyndynLaunchBackground())
        .accessibilityIdentifier("onboarding")
        .sheet(isPresented: $showSetup) {
            HouseholdSetupView()
        }
        .sheet(isPresented: $showCloudRecovery) {
            CloudHouseholdRecoveryView()
        }
        .confirmationDialog(
            "Restore or import a household",
            isPresented: $showRestoreOptions,
            titleVisibility: .visible
        ) {
            Button("Restore from iCloud", systemImage: "icloud.and.arrow.down") {
                showCloudRecovery = true
            }
            Button("Import a backup or Rowan export", systemImage: "square.and.arrow.down") {
                Task {
                    await parentAccess.authenticate()
                    if parentAccess.isUnlocked { showImporter = true }
                }
            }
        } message: {
            Text("Choose where your existing family is stored. Nothing will be replaced without your review.")
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                if let converted = try? RowanTransferConverter.dryRun(data) {
                    pendingImportKind = .rowanPWA
                    importReport = converted.report
                } else {
                    pendingImportKind = .kyndynBackup
                    importReport = try HouseholdTransferCodec
                        .validateBackup(data).1
                }
                pendingImportData = data
                showImportConfirmation = true
            } catch {
                app.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showImportConfirmation) {
            ImportReviewView(report: importReport) {
                guard let data = pendingImportData,
                      let kind = pendingImportKind else { return }
                do {
                    let household = kind == .rowanPWA
                        ? try RowanTransferConverter.apply(data, context: context)
                        : try HouseholdRestoreService.restore(data, context: context)
                    _ = try app.ensureLocalDeviceSettings(in: context)
                    app.selectedPersonID = try context.fetch(
                        FetchDescriptor<Person>()).first {
                            $0.householdID == household.id &&
                            $0.deletedAt == nil
                        }?.id
                    showImportConfirmation = false
                } catch {
                    app.errorMessage = error.localizedDescription
                }
            }
        }
        .errorAlert(app: app)
    }
}

struct CloudHouseholdRecoveryView: View {
    @Environment(CloudSyncController.self) private var sync
    @Environment(AppModel.self) private var app
    @Environment(AutomaticSyncCoordinator.self) private var automaticSync
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var candidates = [CloudHouseholdCandidate]()
    @State private var hasChecked = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Kyndyn will look for families already owned by or shared with this iCloud account. It won’t upload, replace, or delete anything.")
                        .foregroundStyle(.secondary)
                }
                if sync.isWorking {
                    Section { ProgressView("Checking iCloud…") }
                } else if candidates.isEmpty, hasChecked {
                    Section {
                        ContentUnavailableView(
                            "No family found",
                            systemImage: "icloud.slash",
                            description: Text(sync.statusMessage))
                    }
                } else {
                    Section("Families found") {
                        ForEach(candidates) { candidate in
                            Button {
                                recover(candidate)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(candidate.householdName).font(.headline)
                                    Text(candidate.scope == .privateDatabase
                                         ? "Hosted by you" : "Shared with you")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section {
                    Button("Check again", systemImage: "arrow.clockwise") {
                        check()
                    }
                    .disabled(sync.isWorking)
                }
            }
            .navigationTitle("Recover from iCloud")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { check() }
        }
    }

    private func check() {
        Task {
            candidates = await sync.discoverRecoverableHouseholds()
            hasChecked = true
        }
    }

    private func recover(_ candidate: CloudHouseholdCandidate) {
        Task {
            guard await sync.recoverHousehold(candidate, context: context) != nil else {
                return
            }
            let recoveredPeople = (try? context.fetch(FetchDescriptor<Person>())) ?? []
            app.selectedPersonID = recoveredPeople.first(where: {
                $0.householdID == candidate.householdID && $0.deletedAt == nil
            })?.id
            automaticSync.request(.accountRecovery)
            dismiss()
        }
    }
}

struct HouseholdSetupView: View {
    @Environment(AppModel.self) private var app
    @EnvironmentObject private var parentAccess: ParentAccessController
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft = HouseholdSetupDraft()
    @State private var pin = ""
    @State private var confirmation = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Your family") {
                    TextField("Household name", text: $draft.householdName)
                    Picker("Time zone", selection: $draft.timeZoneIdentifier) {
                        ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) {
                            Text($0.replacingOccurrences(of: "_", with: " "))
                                .tag($0)
                        }
                    }
                }
                Section("First parent") {
                    TextField("Parent name", text: $draft.parent.name)
                    ProfileColorSelector(selection: $draft.parent.colorHex)
                    Picker("Companion", selection: $draft.parent.companionID) {
                        ForEach(companionChoices, id: \.self) {
                            Text($0.capitalized).tag($0)
                        }
                    }
                }
                Section("Optional kyndyn PIN") {
                    Text("Your device passcode or biometrics protects the Parent area. You may also add a device-only fallback PIN now.")
                        .font(.footnote).foregroundStyle(.secondary)
                    SecureField("6–12 digit PIN", text: $pin)
                        .keyboardType(.numberPad)
                    SecureField("Confirm PIN", text: $confirmation)
                        .keyboardType(.numberPad)
                }
                Section {
                    Text("No sample people or quests will be added. You can add family members and quests from the protected Parent area.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Set up my family")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create family") { create() }
                }
            }
        }
    }

    private func create() {
        do {
            if !pin.isEmpty || !confirmation.isEmpty {
                guard pin == confirmation else {
                    app.errorMessage = "The PIN entries don’t match."
                    return
                }
                if let message = PINValidation.message(for: pin) {
                    app.errorMessage = message
                    return
                }
                try parentAccess.configurePIN(pin)
            }
            _ = try app.createHousehold(draft, context: context)
            dismiss()
        } catch {
            app.errorMessage = error.localizedDescription
        }
    }
}

struct ImportReviewView: View {
    let report: TransferReport?
    let importAction: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if let report {
                    Section("Dry-run report") {
                        LabeledContent("Accepted", value: "\(report.accepted)")
                        LabeledContent("Normalized", value: "\(report.normalized)")
                        LabeledContent("Skipped duplicates", value: "\(report.skipped)")
                        LabeledContent("Unsupported", value: "\(report.unsupported)")
                        LabeledContent("Invalid", value: "\(report.invalid)")
                    }
                    Section("What will happen") {
                        Text("This creates one new household on this empty installation. It does not merge with or replace another household.")
                        ForEach(report.notes, id: \.self) { Text($0) }
                    }
                    Section {
                        Button("Import new household", action: importAction)
                            .buttonStyle(.borderedProminent)
                            .disabled(!report.canImport)
                    }
                }
            }
            .navigationTitle("Review import")
        }
    }
}

struct ProfilePickerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Person.createdAt) private var people: [Person]
    @Query private var settings: [LocalDeviceSettings]
    let columns = [GridItem(.adaptive(minimum: 160, maximum: 260), spacing: 18)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    Text("Who’s using kyndyn?").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text("Choose your profile to see the right quests.").foregroundStyle(.secondary)
                }.padding(.vertical, 28)
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(people.filter { $0.deletedAt == nil }) { person in
                        Button {
                            app.selectedPersonID = person.id
                            app.selectedTab = 0
                            if let setting = settings.first {
                                setting.selectedPersonID = person.id
                                setting.showsHouseholdDashboard = false
                            }
                            try? context.save()
                            dismiss()
                        } label: {
                            VStack(spacing: 12) {
                                CompanionArt(id: person.companionID)
                                    .frame(height: 112)
                                    .padding(8)
                                    .background(.background.opacity(0.78), in: Circle())
                                    .overlay {
                                        Circle().stroke(
                                            Color(hex: person.colorHex),
                                            lineWidth: 5
                                        )
                                    }
                                Text(person.name).font(.title3.bold()).foregroundStyle(.primary)
                                Text(person.role == .parent ? "Parent" : "Family member").font(.caption).foregroundStyle(.secondary)
                                Label(ProfilePalette.name(for: person.colorHex),
                                      systemImage: "paintpalette.fill")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color(hex: person.colorHex))
                            }
                            .frame(maxWidth: .infinity).padding()
                            .background(
                                Color(hex: person.colorHex).opacity(0.18),
                                in: RoundedRectangle(cornerRadius: 24)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(Color(hex: person.colorHex), lineWidth: 2)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(person.name), \(person.role == .parent ? "parent" : "family member")")
                        .accessibilityValue("\(ProfilePalette.name(for: person.colorHex)) profile color")
                        .accessibilityHint("Shows this person’s kyndyn dashboard")
                        .accessibilityIdentifier("profile-\(person.name)")
                    }
                }
                .padding()
                .frame(maxWidth: AdaptiveLayout.readableContentMaximum)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("kyndyn")
        }
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var app
    @EnvironmentObject private var parentAccess: ParentAccessController
    @Query private var people: [Person]
    @Query private var deviceSettings: [LocalDeviceSettings]
    private var selected: Person? { people.first { $0.id == app.selectedPersonID } }
    private var devicePerson: Person? {
        people.first { $0.id == deviceSettings.first?.devicePersonID }
    }

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            DashboardView().tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
            QuestListView().tabItem { Label("Quests", systemImage: "checklist") }.tag(1)
            if selected?.role == .parent ||
                (selected == nil && devicePerson?.role == .parent) {
                Group {
                    if parentAccess.isUnlocked { ParentAreaView() }
                    else { ParentAuthenticationView() }
                }
                .tabItem { Label("Parent", systemImage: "lock.shield.fill") }.tag(2)
            }
            ProfilePickerView().tabItem { Label("Switch", systemImage: "person.2.fill") }.tag(3)
        }
        .onChange(of: app.selectedPersonID) { _, _ in
            app.selectedTab = 0
            if !ProcessInfo.processInfo.arguments.contains("-ui-testing-parent-unlocked") {
                parentAccess.lock()
            }
        }
    }
}

struct ParentAuthenticationView: View {
    @EnvironmentObject private var access: ParentAccessController
    @State private var pin = ""
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 52)).foregroundStyle(.purple)
                    Text("Parent area").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text("Authenticate to manage people, quests, reminders, and device security.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button {
                        isWorking = true
                        Task { await access.authenticate(); isWorking = false }
                    } label: {
                        Label("Use Face ID, Touch ID, or passcode", systemImage: "faceid")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(isWorking)
                    if access.hasPIN {
                        Divider().padding(.vertical, 4)
                        SecureField("kyndyn PIN", text: $pin).keyboardType(.numberPad)
                            .textContentType(.password).padding()
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                            .accessibilityLabel("kyndyn parent PIN")
                        Button("Unlock with kyndyn PIN") {
                            if access.unlock(pin: pin) { pin = "" }
                        }.buttonStyle(.bordered).controlSize(.large).disabled(pin.isEmpty)
                    }
                    if let message = access.message {
                        Text(message).font(.callout).foregroundStyle(.secondary)
                    }
                    Text("Canceling leaves kyndyn unlocked for everyday child use; only parent tools stay locked.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(28).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }.navigationTitle("Protected")
        }
    }
}

struct DashboardView: View {
    @Environment(AppModel.self) private var app
    @Environment(AutomaticSyncCoordinator.self) private var automaticSync
    @Environment(\.modelContext) private var context
    @Query private var households: [Household]
    @Query private var people: [Person]
    @Query private var completions: [QuestCompletion]
    @Query private var goals: [RewardGoal]
    @Query private var deviceSettings: [LocalDeviceSettings]
    @Query private var quests: [Quest]
    @State private var showMyProfile = false
    @State private var showProgress = false
    private var person: Person? { people.first { $0.id == app.selectedPersonID } }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let household = households.first {
                    VStack(spacing: 16) {
                        dashboardModePicker
                            .padding(.horizontal)
                            .padding(.top, 8)
                        if deviceSettings.first?.showsHouseholdDashboard == true {
                            householdDashboard(household)
                        } else if let person {
                            let progress = ProgressionEngine.progress(personID: person.id, completions: completions, now: .now, timeZoneIdentifier: household.timeZoneIdentifier)
                            VStack(spacing: 18) {
                                ViewThatFits(in: .horizontal) {
                            HStack {
                                profileArt(person)
                                greeting(person)
                                Spacer()
                            }
                            VStack(spacing: 10) {
                                profileArt(person)
                                greeting(person)
                                    .multilineTextAlignment(.center)
                                    }
                                }
                                .kyndynCard(
                                    tint: Color(hex: person.colorHex),
                                    raised: true)
                                progressSummary(progress, tint: Color(hex: person.colorHex))
                        VStack(alignment: .leading, spacing: 10) {
                            ViewThatFits(in: .horizontal) {
                                HStack {
                                            Text(rewardTitle(household)).font(.headline)
                                    Spacer()
                                    rewardProgress(household)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                            Text(rewardTitle(household)).font(.headline)
                                    rewardProgress(household)
                                }
                            }
                                    ProgressView(
                                        value: min(Double(rewardXP(household)),
                                                   Double(rewardTarget(household))),
                                        total: Double(rewardTarget(household)))
                                }.kyndynCard(tint: KyndynTheme.purple)
                        QuestListView(compact: true, includeUpcoming: true)
                        recentActivity(household: household, personID: person.id)
                            }
                            .padding()
                            .frame(maxWidth: AdaptiveLayout.readableContentMaximum)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .refreshable {
                automaticSync.request(.manual)
                await automaticSync.waitUntilIdle()
            }
            .background(KyndynScreenBackground())
            .navigationTitle("Today")
            .toolbar {
                if person != nil && deviceSettings.first?.showsHouseholdDashboard != true {
                    ToolbarItem(placement: .primaryAction) {
                        Button("My profile", systemImage: "person.crop.circle") {
                            showMyProfile = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showMyProfile) {
                if let person { MyProfileView(person: person) }
            }
            .sheet(isPresented: $showProgress) {
                if let person, let household = households.first {
                    ProgressDetailView(person: person, household: household)
                }
            }
        }
    }

    private var dashboardModePicker: some View {
        Picker("Dashboard view", selection: Binding(
            get: { deviceSettings.first?.showsHouseholdDashboard == true },
            set: { showsEveryone in
                guard let setting = deviceSettings.first else { return }
                setting.showsHouseholdDashboard = showsEveryone
                if !showsEveryone, app.selectedPersonID == nil {
                    let fallback = people.first {
                        $0.id == setting.selectedPersonID && $0.deletedAt == nil
                    } ?? people.first {
                        $0.id == setting.devicePersonID && $0.deletedAt == nil
                    } ?? people.first { $0.deletedAt == nil }
                    app.selectedPersonID = fallback?.id
                    setting.selectedPersonID = fallback?.id
                }
                try? context.save()
            }
        )) {
            Text("My day").tag(false)
            Text("Everyone").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 420)
        .padding(5)
        .background(.thinMaterial, in: RoundedRectangle(
            cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("dashboard-view-picker")
    }

    private func householdDashboard(_ household: Household) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            householdHeading(household)
            VStack(alignment: .leading, spacing: 10) {
                Text(rewardTitle(household)).font(.headline)
                ProgressView(
                    value: min(Double(rewardXP(household)),
                               Double(rewardTarget(household))),
                    total: Double(rewardTarget(household)))
                rewardProgress(household)
            }.kyndynCard(tint: KyndynTheme.purple)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 280, maximum: 540), spacing: 12)],
                spacing: 12
            ) {
                ForEach(people.filter { $0.deletedAt == nil }) { member in
                    householdMemberSummary(member, household: household)
                }
            }
            recentActivity(household: household, personID: nil)
        }
        .padding()
        .frame(maxWidth: AdaptiveLayout.readableContentMaximum)
        .frame(maxWidth: .infinity)
    }

    private func householdHeading(_ household: Household) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Everyone’s day").font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(household.name).foregroundStyle(.secondary)
        }
    }

    private func householdMemberSummary(
        _ member: Person, household: Household
    ) -> some View {
        let memberQuests = quests.compactMap { quest -> (Quest, QuestTemporalStatus)? in
            let status = ProgressionEngine.temporalStatus(
                for: quest, personID: member.id, completions: completions,
                now: .now, timeZoneIdentifier: household.timeZoneIdentifier)
            return status == .inactive ? nil : (quest, status)
        }
        let waiting = memberQuests.filter { $0.1 == .overdue || $0.1 == .today }
        let completed = memberQuests.filter { $0.1 == .completed }.count
        let progress = ProgressionEngine.progress(
            personID: member.id, completions: completions, now: .now,
            timeZoneIdentifier: household.timeZoneIdentifier)

        return Button {
            app.selectedPersonID = member.id
            app.selectedTab = 0
            if let setting = deviceSettings.first {
                setting.selectedPersonID = member.id
                setting.showsHouseholdDashboard = false
            }
            try? context.save()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Circle().fill(Color(hex: member.colorHex))
                        .frame(width: 14, height: 14)
                    Text(member.name).font(.headline)
                    Spacer()
                    Text("\(progress.xp) XP")
                        .font(.subheadline.bold().monospacedDigit())
                }
                HStack(spacing: 16) {
                    Label("\(waiting.count) waiting", systemImage: "circle.dashed")
                    Label("\(completed) done", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .font(.subheadline)
                if let next = waiting.first {
                    Text(next.0.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("All clear for today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        }
        .buttonStyle(.plain)
        .kyndynCard(tint: Color(hex: member.colorHex))
        .accessibilityLabel("\(member.name), \(waiting.count) waiting, \(completed) completed today, \(progress.xp) XP")
        .accessibilityHint("Shows \(member.name)’s dashboard")
    }

    private func recentActivity(household: Household, personID: UUID?) -> some View {
        let recent = completions.filter {
            $0.reversedAt == nil && (personID == nil || $0.personID == personID)
        }.sorted { $0.completedAt > $1.completedAt }.prefix(5)
        return Group {
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    KyndynSectionHeader(title: "Recent activity")
                        .padding(.bottom, 6)
                ForEach(Array(recent)) { event in
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading) {
                            Text(quests.first { $0.id == event.questID }?.title
                                 ?? "Completed quest")
                            if personID == nil {
                                Text(people.first { $0.id == event.personID }?.name
                                     ?? "Family member")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("+\(event.awardedXP) XP")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 9)
                    if event.id != recent.last?.id {
                        Divider().padding(.leading, 30)
                    }
                }
            }
            .padding(.horizontal, 4)
            }
        }
    }

    private func profileArt(_ person: Person) -> some View {
        CompanionArt(id: person.companionID)
            .frame(width: 100, height: 100)
            .padding(7)
            .background(Color(hex: person.colorHex).opacity(0.18), in: Circle())
            .overlay {
                Circle().stroke(Color(hex: person.colorHex), lineWidth: 5)
            }
            .accessibilityHint("\(ProfilePalette.name(for: person.colorHex)) profile")
    }

    private func greeting(_ person: Person) -> some View {
        VStack(alignment: .leading) {
            Text("Hi, \(person.name)")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Small steps count.").foregroundStyle(.secondary)
        }
    }

    private func rewardProgress(_ household: Household) -> some View {
        Text("\(rewardXP(household)) / \(rewardTarget(household)) XP")
            .font(.subheadline.monospacedDigit())
    }

    private func currentReward(_ household: Household) -> RewardGoal? {
        ProgressionEngine.currentRewardGoal(goals, householdID: household.id)
    }

    private func rewardTitle(_ household: Household) -> String {
        currentReward(household)?.title ?? household.rewardTitle
    }

    private func rewardTarget(_ household: Household) -> Int {
        max(1, currentReward(household)?.targetXP ?? household.rewardGoalXP)
    }

    private func rewardXP(_ household: Household) -> Int {
        ProgressionEngine.rewardXP(completions, goal: currentReward(household))
    }

    private func progressSummary(_ progress: PersonProgress, tint: Color) -> some View {
        Button {
            showProgress = true
        } label: {
            VStack(spacing: 14) {
                HStack {
                    Label("Your progress", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 0) {
                    ProgressStat(value: "\(progress.xp)", label: "XP")
                    Divider().frame(height: 34)
                    ProgressStat(value: "\(progress.level)", label: "Level")
                    Divider().frame(height: 34)
                    ProgressStat(
                        value: "\(progress.currentStreak)", label: "Day streak")
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .kyndynCard(tint: tint)
        .accessibilityIdentifier("home-progress-summary")
        .accessibilityHint("Shows progress details")
    }
}

private enum QuestBrowseFilter: String, CaseIterable, Identifiable {
    case waiting, completed, overdue, upcoming, all
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct ProgressDetailView: View {
    let person: Person
    let household: Household
    @Environment(\.dismiss) private var dismiss
    @Query private var completions: [QuestCompletion]
    @Query private var quests: [Quest]

    private var activeEvents: [QuestCompletion] {
        completions.filter { $0.personID == person.id && $0.reversedAt == nil }
            .sorted { $0.completedAt > $1.completedAt }
    }
    private var progress: PersonProgress {
        ProgressionEngine.progress(
            personID: person.id, completions: completions, now: .now,
            timeZoneIdentifier: household.timeZoneIdentifier)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Progress") {
                    LabeledContent("Total XP", value: "\(progress.xp)")
                    LabeledContent("Level", value: "\(progress.level)")
                    LabeledContent("Current streak", value: "\(progress.currentStreak) days")
                    Text("XP comes from active completion events. Undoing a completion removes that event’s XP from these totals.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Recent XP") {
                    if activeEvents.isEmpty {
                        Text("Complete a quest to begin your history.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(activeEvents.prefix(30)) { event in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(quests.first { $0.id == event.questID }?.title
                                         ?? "Completed quest")
                                    Text(event.completedAt.formatted())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("+\(event.awardedXP) XP")
                                    .font(.subheadline.bold()).monospacedDigit()
                            }
                        }
                    }
                }
            }
            .navigationTitle("\(person.name)’s progress")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct MyProfileView: View {
    let person: Person
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var colorHex: String
    @State private var companionID: String

    init(person: Person) {
        self.person = person
        _colorHex = State(initialValue: person.colorHex)
        _companionID = State(initialValue: person.companionID)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    CompanionArt(id: companionID)
                        .frame(width: 150, height: 150)
                        .padding(14)
                        .background(Color(hex: colorHex).opacity(0.16), in: Circle())
                        .overlay { Circle().stroke(Color(hex: colorHex), lineWidth: 6) }
                        .accessibilityLabel("Preview for \(person.name)")
                    VStack(alignment: .leading, spacing: 10) {
                        Text("App color").font(.headline)
                        ProfileColorSelector(selection: $colorHex)
                    }
                    .kyndynCard(tint: Color(hex: colorHex))
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Companion").font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 105))]) {
                            ForEach(companionChoices, id: \.self) { choice in
                                Button {
                                    companionID = choice
                                } label: {
                                    VStack {
                                        CompanionArt(id: choice).frame(width: 74, height: 74)
                                        Text(choice.capitalized).font(.caption.bold())
                                        if companionID == choice {
                                            Label("Active", systemImage: "checkmark.circle.fill")
                                                .font(.caption2)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 122)
                                }
                                .buttonStyle(.plain)
                                .kyndynCard(tint: companionID == choice
                                            ? Color(hex: colorHex) : .secondary)
                            }
                        }
                    }
                    Text("Parents still manage names, roles, and family permissions.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: AdaptiveLayout.managementContentMaximum)
                .frame(maxWidth: .infinity)
            }
            .background(KyndynScreenBackground())
            .navigationTitle("My profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
        .tint(Color(hex: colorHex))
    }

    private func save() {
        do {
            try app.updatePerson(
                person,
                draft: PersonDraft(name: person.name, role: person.role,
                                   colorHex: colorHex,
                                   companionID: companionID),
                context: context)
            dismiss()
        } catch {
            app.errorMessage = error.localizedDescription
        }
    }
}

struct QuestListView: View {
    @Environment(AppModel.self) private var app
    @Environment(AutomaticSyncCoordinator.self) private var automaticSync
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var households: [Household]
    @Query(sort: \Quest.createdAt) private var quests: [Quest]
    @Query private var completions: [QuestCompletion]
    @Query private var people: [Person]
    var compact = false
    var personID: UUID? = nil
    var includeUpcoming = false
    var showsCompactHeading = true
    @State private var inFlight = Set<String>()
    @State private var earnedFeedback: String?
    @State private var browseFilter: QuestBrowseFilter = .waiting
    @State private var searchText = ""
    @State private var selectedQuest: Quest?
    @State private var browseEveryone = false

    private var selectedPersonID: UUID? { personID ?? app.selectedPersonID }

    private var visible: [(Quest, QuestTemporalStatus)] {
        guard let household = households.first else { return [] }
        return quests.compactMap { quest in
            let status: QuestTemporalStatus
            if browseEveryone {
                let values = quest.participantIDs.map { personID in
                    ProgressionEngine.temporalStatus(
                        for: quest, personID: personID, completions: completions,
                        now: .now,
                        timeZoneIdentifier: household.timeZoneIdentifier)
                }
                status = aggregateStatus(values)
            } else if let personID = selectedPersonID {
                status = ProgressionEngine.temporalStatus(
                    for: quest, personID: personID, completions: completions,
                    now: .now, timeZoneIdentifier: household.timeZoneIdentifier)
            } else {
                status = .inactive
            }
            return status == .inactive ||
                (!includeUpcoming && compact && status == .upcoming)
                ? nil : (quest, status)
        }.sorted { lhs, rhs in
            let order: [QuestTemporalStatus: Int] = [.overdue: 0, .today: 1, .completed: 2]
            return order[lhs.1, default: 9] < order[rhs.1, default: 9]
        }
    }

    private func aggregateStatus(_ values: [QuestTemporalStatus]) -> QuestTemporalStatus {
        for status in [QuestTemporalStatus.overdue, .today, .upcoming, .completed] {
            if values.contains(status) { return status }
        }
        return .inactive
    }

    private var browsed: [(Quest, QuestTemporalStatus)] {
        visible.filter { quest, status in
            let matchesFilter: Bool
            switch browseFilter {
            case .waiting: matchesFilter = status == .today || status == .overdue
            case .completed: matchesFilter = status == .completed
            case .overdue: matchesFilter = status == .overdue
            case .upcoming: matchesFilter = status == .upcoming
            case .all: matchesFilter = true
            }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            return matchesFilter && (query.isEmpty ||
                quest.title.localizedCaseInsensitiveContains(query) ||
                quest.detail.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        Group {
            if compact {
                content
            } else {
                NavigationStack {
                    ScrollView { content.padding() }
                        .refreshable {
                            automaticSync.request(.manual)
                            await automaticSync.waitUntilIdle()
                        }
                        .background(KyndynScreenBackground())
                        .navigationTitle("Today’s quests")
                        .searchable(text: $searchText, prompt: "Search quests")
                }
            }
        }
        .sheet(item: $selectedQuest) { quest in
            QuestDetailView(quest: quest, personID: browseEveryone ? nil : selectedPersonID)
        }
        .errorAlert(app: app)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !compact { browseControls }
            if compact && showsCompactHeading { Text("Quests").font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader) }
            if (compact ? visible : browsed).isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "All clear" : "No matching quests",
                    systemImage: searchText.isEmpty ? "checkmark.circle" : "magnifyingglass",
                    description: Text(searchText.isEmpty
                        ? "No quests match this view."
                        : "Try another search or filter."))
            }
            ForEach([QuestTemporalStatus.overdue, .today, .completed, .upcoming],
                    id: \.rawValue) { status in
                let items = (compact ? visible : browsed).filter { $0.1 == status }
                if !items.isEmpty {
                    KyndynSectionHeader(
                        title: sectionTitle(status), count: items.count,
                        tint: statusTint(status))
                    LazyVGrid(
                        columns: [GridItem(.adaptive(
                            minimum: dynamicTypeSize.isAccessibilitySize ? 540 : 300,
                            maximum: 540
                        ), spacing: 12)],
                        alignment: .leading, spacing: 12
                    ) {
                        ForEach(items, id: \.0.id) { quest, itemStatus in
                            QuestRow(quest: quest, status: itemStatus)
                        }
                    }
                }
            }
            if let earnedFeedback {
                Label(earnedFeedback, systemImage: "sparkles")
                    .font(.headline).foregroundStyle(.purple)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityIdentifier("quest-xp-feedback")
            }
        }
        .frame(maxWidth: AdaptiveLayout.readableContentMaximum)
        .frame(maxWidth: .infinity)
    }

    private var browseControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Whose quests", selection: $browseEveryone) {
                Text("My quests").tag(false)
                Text("Everyone").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                ForEach(QuestBrowseFilter.allCases) { filter in
                        Button {
                            browseFilter = filter
                        } label: {
                            HStack(spacing: 6) {
                                Text(filter.title)
                                Text("\(count(for: filter))")
                                    .font(.caption.bold().monospacedDigit())
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.secondary.opacity(0.13), in: Capsule())
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(browseFilter == filter ? .accentColor : .secondary)
                        .accessibilityValue(browseFilter == filter ? "Selected" : "Not selected")
                    }
                }
            }
            .accessibilityIdentifier("quest-status-filter")
            Text(browseEveryone ? "Showing the whole family" :
                    "Showing quests for \(people.first { $0.id == selectedPersonID }?.name ?? "the selected profile")")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func count(for filter: QuestBrowseFilter) -> Int {
        switch filter {
        case .waiting: return visible.filter { $0.1 == .today || $0.1 == .overdue }.count
        case .completed: return visible.filter { $0.1 == .completed }.count
        case .overdue: return visible.filter { $0.1 == .overdue }.count
        case .upcoming: return visible.filter { $0.1 == .upcoming }.count
        case .all: return visible.count
        }
    }

    @ViewBuilder private func QuestRow(quest: Quest, status: QuestTemporalStatus) -> some View {
        if browseEveryone {
            Button {
                selectedQuest = quest
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: statusIcon(status))
                        .font(.title2).foregroundStyle(statusTint(status))
                        .frame(minWidth: 44, minHeight: 44)
                    questDetails(quest: quest, status: status,
                                 done: status == .completed)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 96,
                       alignment: .leading)
            }
            .buttonStyle(.plain)
            .kyndynCard(tint: statusTint(status), raised: status == .overdue)
            .accessibilityHint("Shows assignments and family completion history")
        } else if let household = households.first, let personID = selectedPersonID {
            let done = status == .completed
            HStack(spacing: 4) {
                Button {
                    toggle(quest: quest, done: done, personID: personID,
                           household: household)
                } label: {
                HStack(spacing: 14) {
                    completionIcon(quest: quest, done: done)
                    questDetails(quest: quest, status: status, done: done)
                    Spacer()
                    xpLabel(quest: quest, done: done, household: household)
                }
                .frame(maxWidth: .infinity, minHeight: 96,
                       alignment: .leading)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .disabled(status == .upcoming ||
                          inFlight.contains(actionKey(quest, personID)))
                .accessibilityLabel(status == .upcoming ? "Upcoming \(quest.title)" :
                    (done ? "Undo \(quest.title)" : "Complete \(quest.title)"))
                .accessibilityHint(done
                    ? "Reverses this occurrence and recalculates progress"
                    : "Records this occurrence as complete")
                .accessibilityValue(quest.completionMode == .sharedAll
                    ? "Shared family check-in" : "Individual check-in")
                .accessibilityIdentifier("quest-toggle-\(quest.title)")
                Button("Details", systemImage: "info.circle") {
                    selectedQuest = quest
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Details for \(quest.title)")
            }
            .kyndynCard(tint: statusTint(status),
                        raised: status == .overdue)
        }
    }

    private func completionIcon(quest: Quest, done: Bool) -> some View {
        Image(systemName: done ? "checkmark.circle.fill" : "circle")
            .font(.title)
            .foregroundStyle(done ? .green : .purple)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityHidden(true)
    }

    private func actionKey(_ quest: Quest, _ personID: UUID) -> String {
        "\(quest.id.uuidString):\(personID.uuidString)"
    }

    private func toggle(quest: Quest, done: Bool, personID: UUID,
                        household: Household) {
        let key = actionKey(quest, personID)
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)
        do {
            if done {
                try app.undo(quest, personID: personID, household: household,
                             completions: completions, context: context)
            } else {
                try app.complete(quest, personID: personID,
                                 household: household,
                                 completions: completions, context: context)
                let earned = ProgressionEngine.effectiveXP(
                    base: quest.xp,
                    overdueDays: ProgressionEngine.overdueDays(
                        for: quest, now: .now,
                        timeZoneIdentifier: household.timeZoneIdentifier))
                withAnimation(.easeOut(duration: 0.2)) {
                    earnedFeedback = "Earned +\(earned) XP"
                }
            }
        } catch { app.errorMessage = error.localizedDescription }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            inFlight.remove(key)
            if !done {
                try? await Task.sleep(for: .milliseconds(900))
                withAnimation { earnedFeedback = nil }
            }
        }
    }

    private func questDetails(
        quest: Quest, status: QuestTemporalStatus, done: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(quest.title).font(.headline).strikethrough(done)
                    .lineLimit(2)
                if quest.completionMode == .sharedAll {
                    Image(systemName: "person.2.fill")
                        .font(.caption.bold())
                        .foregroundStyle(KyndynTheme.purple)
                        .accessibilityHidden(true)
                }
            }
            if !quest.detail.isEmpty {
                Text(quest.detail).font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            KyndynStatusPill(
                text: statusLabel(status, quest: quest),
                systemImage: statusIcon(status), tint: statusTint(status))
                .lineLimit(1)
        }
    }

    private func xpLabel(
        quest: Quest, done: Bool, household: Household
    ) -> some View {
        let occurrence = ProgressionEngine.occurrenceKey(
            for: quest, on: .now,
            timeZoneIdentifier: household.timeZoneIdentifier)
        let awarded = completions.first {
            $0.questID == quest.id && $0.occurrenceDay == occurrence &&
            $0.personID == selectedPersonID && $0.reversedAt == nil
        }?.awardedXP
        let value = done ? (awarded ?? quest.xp) : ProgressionEngine.effectiveXP(
            base: quest.xp,
            overdueDays: ProgressionEngine.overdueDays(
                for: quest, now: .now,
                timeZoneIdentifier: household.timeZoneIdentifier
            )
        )
        return Text("+\(value) XP")
            .font(.subheadline.bold())
            .foregroundStyle(.purple)
            .fixedSize()
    }

    private func statusLabel(_ status: QuestTemporalStatus, quest _: Quest) -> String {
        switch status {
        case .overdue: return "Overdue"
        case .completed: return "Completed · tap to undo"
        case .today: return "Due today"
        case .upcoming: return "Upcoming"
        default: return "Not active"
        }
    }

    private func sectionTitle(_ status: QuestTemporalStatus) -> String {
        switch status {
        case .overdue: return "Overdue"
        case .today: return "Due today"
        case .completed: return "Completed today"
        case .upcoming: return "Upcoming"
        case .inactive: return ""
        }
    }

    private func statusTint(_ status: QuestTemporalStatus) -> Color {
        switch status {
        case .overdue: return KyndynTheme.amber
        case .today: return KyndynTheme.blue
        case .completed: return KyndynTheme.green
        case .upcoming, .inactive: return .secondary
        }
    }

    private func statusIcon(_ status: QuestTemporalStatus) -> String {
        switch status {
        case .overdue: return "exclamationmark.circle.fill"
        case .today: return "sun.max.fill"
        case .completed: return "checkmark.circle.fill"
        case .upcoming: return "calendar"
        case .inactive: return "circle"
        }
    }
}

struct QuestDetailView: View {
    let quest: Quest
    let personID: UUID?
    @Environment(\.dismiss) private var dismiss
    @Query private var people: [Person]
    @Query private var completions: [QuestCompletion]

    private var history: [QuestCompletion] {
        completions.filter {
            $0.questID == quest.id && (personID == nil || $0.personID == personID)
        }.sorted { $0.completedAt > $1.completedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Quest") {
                    LabeledContent("XP", value: "\(quest.xp)")
                    LabeledContent("Schedule", value: scheduleText)
                    LabeledContent("Assigned to", value: assignees)
                    LabeledContent("Check-in", value: quest.completionMode == .sharedAll
                                   ? "Each person" : "Individual")
                    if let due = quest.dueAt {
                        LabeledContent("Deadline", value: due.formatted())
                    }
                    if !quest.detail.isEmpty { Text(quest.detail) }
                }
                Section("Completion history") {
                    if history.isEmpty {
                        Text("No completion events yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(history) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(people.first { $0.id == event.personID }?.name
                                         ?? "Family member")
                                    Spacer()
                                    Text("+\(event.awardedXP) XP")
                                        .font(.subheadline.bold())
                                }
                                Text(event.completedAt.formatted())
                                    .font(.caption).foregroundStyle(.secondary)
                                if let reversed = event.reversedAt {
                                    Label("Undone \(reversed.formatted())",
                                          systemImage: "arrow.uturn.backward.circle")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(quest.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var assignees: String {
        let names = people.filter { quest.participantIDs.contains($0.id) }.map(\.name)
        return names.isEmpty ? "No one" : names.joined(separator: ", ")
    }

    private var scheduleText: String {
        switch quest.scheduleKind {
        case .oneTime: return "One time"
        case .daily: return "Daily"
        case .weekly:
            return quest.repeatIntervalWeeks > 1 ? "Every other week" : "Weekly"
        }
    }
}

// MARK: - Parent area

struct ParentAreaView: View {
    @EnvironmentObject private var access: ParentAccessController
    @Query private var households: [Household]
    @Query private var people: [Person]
    @Query private var quests: [Quest]
    @Query private var completions: [QuestCompletion]
    @Query private var goals: [RewardGoal]
    @Query private var cloudStates: [HouseholdCloudState]
    var body: some View {
        NavigationStack {
            List {
                if households.first?.isSample == true {
                    Section {
                        Label("Sample family", systemImage: "sparkles")
                            .foregroundStyle(.purple)
                        Text("This household contains fictional practice data and is kept separate from personal setup.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let household = households.first {
                    Section("Today at a glance") {
                        HStack(spacing: 10) {
                            ParentSummaryTile(value: waitingCount(household), label: "Waiting", tint: .blue)
                            ParentSummaryTile(value: overdueCount(household), label: "Overdue", tint: .orange)
                            ParentSummaryTile(value: completedCount(household), label: "Done", tint: .green)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(currentReward(household), systemImage: "gift.fill")
                                Spacer()
                                Text("\(rewardXP(household)) / \(rewardTarget(household)) XP")
                                    .font(.subheadline.monospacedDigit())
                            }
                            ProgressView(value: min(Double(rewardXP(household)),
                                                    Double(rewardTarget(household))),
                                         total: Double(rewardTarget(household)))
                        }
                    }
                    Section("Quick actions") {
                        NavigationLink { QuestEditorView(quest: nil) } label: {
                            Label("Create a quest", systemImage: "plus.circle.fill")
                        }
                        NavigationLink { PersonEditorView(person: nil) } label: {
                            Label("Add a person", systemImage: "person.badge.plus")
                        }
                        NavigationLink { FamilyRewardSettingsView() } label: {
                            Label("Update family reward", systemImage: "gift")
                        }
                        NavigationLink { CloudSyncSettingsView() } label: {
                            Label(syncSummary, systemImage: "icloud")
                        }
                    }
                }
                Section {
                    NavigationLink { PeopleManagementView() } label: { Label("People", systemImage: "person.2.fill") }
                    NavigationLink { QuestManagementView() } label: { Label("Quests", systemImage: "checklist") }
                    NavigationLink { FamilyRewardSettingsView() } label: {
                        Label("Family reward", systemImage: "gift.fill")
                    }
                    NavigationLink { CloudSyncSettingsView() } label: {
                        Label("Family sync", systemImage: "icloud")
                    }
                    NavigationLink { NotificationSettingsView() } label: { Label("Reminders", systemImage: "bell.fill") }
                    NavigationLink { HouseholdDataProtectionView() } label: {
                        Label("Backup and migration", systemImage: "externaldrive.fill")
                    }
                    NavigationLink { ParentSecurityView() } label: { Label("Parent security", systemImage: "lock.shield.fill") }
                }
                Section {
                    Button("Lock Parent area", systemImage: "lock.fill") { access.lock() }
                }
                Section("About") {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .frame(maxWidth: AdaptiveLayout.managementContentMaximum)
            .frame(maxWidth: .infinity)
            .navigationTitle("Parent")
        }
    }

    private func statuses(_ household: Household) -> [QuestTemporalStatus] {
        quests.filter { $0.deletedAt == nil }.flatMap { quest in
            quest.participantIDs.compactMap { personID in
                ProgressionEngine.temporalStatus(
                    for: quest, personID: personID, completions: completions,
                    now: .now, timeZoneIdentifier: household.timeZoneIdentifier)
            }
        }
    }

    private func waitingCount(_ household: Household) -> Int {
        statuses(household).filter { $0 == .today || $0 == .overdue }.count
    }
    private func overdueCount(_ household: Household) -> Int {
        statuses(household).filter { $0 == .overdue }.count
    }
    private func completedCount(_ household: Household) -> Int {
        statuses(household).filter { $0 == .completed }.count
    }
    private func currentGoal(_ household: Household) -> RewardGoal? {
        ProgressionEngine.currentRewardGoal(goals, householdID: household.id)
    }
    private func currentReward(_ household: Household) -> String {
        currentGoal(household)?.title ?? household.rewardTitle
    }
    private func rewardTarget(_ household: Household) -> Int {
        max(1, currentGoal(household)?.targetXP ?? household.rewardGoalXP)
    }
    private func rewardXP(_ household: Household) -> Int {
        ProgressionEngine.rewardXP(completions, goal: currentGoal(household))
    }
    private var syncSummary: String {
        guard let state = cloudStates.first else { return "Set up family sync" }
        switch state.mode {
        case .owner, .participant: return "Family sync is up to date"
        case .localOnly: return "Set up family sync"
        default: return "Review family sync"
        }
    }
    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}

private struct ParentSummaryTile: View {
    let value: Int
    let label: String
    let tint: Color
    var body: some View {
        VStack(spacing: 3) {
            Text("\(value)").font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 62)
        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

struct FamilyRewardSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var households: [Household]
    @Query private var completions: [QuestCompletion]
    @Query private var goals: [RewardGoal]
    @State private var rewardTitle = ""
    @State private var targetText = ""
    @State private var confirmNewReward = false
    @State private var statusMessage: String?

    private var household: Household? { households.first }
    private var currentGoal: RewardGoal? {
        guard let household else { return nil }
        return ProgressionEngine.currentRewardGoal(
            goals, householdID: household.id)
    }
    private var currentXP: Int {
        ProgressionEngine.rewardXP(completions, goal: currentGoal)
    }
    private var savedTarget: Int {
        max(1, currentGoal?.targetXP ?? household?.rewardGoalXP ?? 1)
    }

    var body: some View {
        Form {
            Section("Current progress") {
                LabeledContent("Reward",
                    value: currentGoal?.title ?? household?.rewardTitle ?? "Family reward")
                LabeledContent("Family XP", value: "\(currentXP) / \(savedTarget) XP")
                ProgressView(
                    value: min(Double(currentXP), Double(savedTarget)),
                    total: Double(savedTarget))
                if currentXP >= savedTarget {
                    Label("Reward ready!", systemImage: "party.popper.fill")
                        .foregroundStyle(.purple)
                } else {
                    Text("\(savedTarget - currentXP) XP remaining")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("Reward and goal") {
                TextField("Reward name", text: $rewardTitle)
                    .textInputAutocapitalization(.sentences)
                TextField("Goal XP", text: $targetText)
                    .keyboardType(.numberPad)
                Button("Save changes", systemImage: "checkmark.circle") {
                    save(resetProgress: false)
                }
                .disabled(!canSave)
            }

            Section("Next reward") {
                Button("Start as a new reward", systemImage: "arrow.counterclockwise") {
                    confirmNewReward = true
                }
                .disabled(!canSave)
                Text("Starts the reward above at 0 family XP. Everyone keeps their profile XP, levels, streaks, and complete quest history.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            if let statusMessage {
                Section {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("Family reward")
        .task { loadCurrentValues() }
        .alert("Start a new family reward?", isPresented: $confirmNewReward) {
            Button("Start at 0 XP") { save(resetProgress: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This resets only the shared reward counter. Profile XP and quest history stay intact.")
        }
        .errorAlert(app: app)
    }

    private var parsedTarget: Int? { Int(targetText) }
    private var canSave: Bool {
        !rewardTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        rewardTitle.count <= 80 &&
        parsedTarget.map { (1...1_000_000).contains($0) } == true
    }

    private func loadCurrentValues() {
        rewardTitle = currentGoal?.title ?? household?.rewardTitle ?? ""
        targetText = String(currentGoal?.targetXP ?? household?.rewardGoalXP ?? 300)
    }

    private func save(resetProgress: Bool) {
        guard let household, let target = parsedTarget else { return }
        do {
            try app.saveFamilyReward(
                title: rewardTitle, targetXP: target,
                resetProgress: resetProgress, household: household,
                goals: goals, context: context)
            statusMessage = resetProgress
                ? "New reward started at 0 XP."
                : "Family reward updated."
            loadCurrentValues()
        } catch {
            app.errorMessage = error.localizedDescription
        }
    }
}

struct HouseholdDataProtectionView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var households: [Household]
    @Query private var people: [Person]
    @Query private var quests: [Quest]
    @Query private var completions: [QuestCompletion]
    @Query private var goals: [RewardGoal]
    @Query private var settings: [HouseholdSettings]
    @State private var document: TransferDocument?
    @State private var exporting = false
    @State private var confirmSampleRemoval = false

    var body: some View {
        List {
            Section("Household backup") {
                Button("Export household backup",
                       systemImage: "square.and.arrow.up") {
                    prepareExport()
                }
                Text("The JSON backup includes household records and completion history. It excludes PINs, authentication, Apple account details, notification settings, tokens, and device information.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Restore limitation") {
                Text("For safety, 0.7 restores backups and Rowan transfers only into an empty installation. It does not merge with or replace this household. Export a fresh backup before changing devices or CloudKit environments.")
            }
            Section("Development pilot") {
                Label("Apple Development CloudKit", systemImage: "hammer.fill")
                Text("This personal pilot uses Apple’s Development environment. Its cloud data may need to be replaced before public release. Keep a recent exported backup.")
                Text("Use a separate fictional household for destructive sharing, revocation, or Apple-account tests. Production CloudKit has not been deployed.")
                    .foregroundStyle(.secondary)
            }
            if households.first?.isSample == true {
                Section("Leave sample mode") {
                    Button("Remove local sample and start my family",
                           role: .destructive) {
                        confirmSampleRemoval = true
                    }
                    Text("This removes the fictional sample from this device only. kyndyn will refuse if the sample is connected to family sharing.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Backup and migration")
        .fileExporter(
            isPresented: $exporting, document: document,
            contentType: .json,
            defaultFilename: "kyndyn-household-backup.json"
        ) { result in
            if case .failure(let error) = result {
                app.errorMessage = error.localizedDescription
            }
            document = nil
        }
        .confirmationDialog(
            "Remove this sample household?",
            isPresented: $confirmSampleRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove fictional sample", role: .destructive) {
                guard let household = households.first else { return }
                do { try app.deleteLocalSampleHousehold(
                    household, context: context) }
                catch { app.errorMessage = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All fictional people, quests, completion history, and local sync metadata for this sample will be removed from this device. Personal or shared households are not affected.")
        }
        .errorAlert(app: app)
    }

    private func prepareExport() {
        guard let household = households.first else { return }
        do {
            let data = try HouseholdTransferCodec.export(
                household: household,
                people: people.filter { $0.householdID == household.id },
                quests: quests.filter { $0.householdID == household.id },
                completions: completions.filter {
                    $0.householdID == household.id
                },
                goals: goals.filter { $0.householdID == household.id },
                settings: settings.first { $0.householdID == household.id })
            document = TransferDocument(data: data)
            exporting = true
        } catch {
            app.errorMessage = error.localizedDescription
        }
    }
}

struct PeopleManagementView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var households: [Household]
    @Query(sort: \Person.createdAt) private var people: [Person]
    @Query private var quests: [Quest]
    @State private var newPerson = false
    @State private var pendingArchive: Person?

    var body: some View {
        List {
            Section("Active people") {
                ForEach(people.filter { $0.deletedAt == nil }) { person in
                    NavigationLink { PersonEditorView(person: person) } label: { PersonLabel(person: person) }
                        .swipeActions {
                            Button("Archive", role: .destructive) { pendingArchive = person }
                        }
                }
                Button("Add person", systemImage: "person.badge.plus") { newPerson = true }
            }
            if people.contains(where: { $0.deletedAt != nil }) {
                Section("Archived people") {
                    ForEach(people.filter { $0.deletedAt != nil }) { person in
                        HStack {
                            PersonLabel(person: person)
                            Spacer()
                            Button("Restore") {
                                do { try app.restorePerson(person, context: context) }
                                catch { app.errorMessage = error.localizedDescription }
                            }.buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .navigationTitle("People")
        .toolbar { Button("Add", systemImage: "plus") { newPerson = true } }
        .sheet(isPresented: $newPerson) { NavigationStack { PersonEditorView(person: nil) } }
        .confirmationDialog("Archive \(pendingArchive?.name ?? "this person")?", isPresented: Binding(get: { pendingArchive != nil }, set: { if !$0 { pendingArchive = nil } }), titleVisibility: .visible) {
            Button("Archive", role: .destructive) {
                guard let person = pendingArchive else { return }
                do { try app.archivePerson(person, people: people, quests: quests, context: context) }
                catch { app.errorMessage = error.localizedDescription }
                pendingArchive = nil
            }
            Button("Cancel", role: .cancel) { pendingArchive = nil }
        } message: {
            Text("History stays intact. The person will no longer appear for new assignments.")
        }
        .errorAlert(app: app)
    }
}

struct PersonLabel: View {
    let person: Person
    var body: some View {
        HStack {
            CompanionArt(id: person.companionID).frame(width: 48, height: 48)
            VStack(alignment: .leading) {
                Text(person.name)
                Text(person.role.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct PersonEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var households: [Household]
    let person: Person?
    @State private var draft: PersonDraft

    init(person: Person?) {
        self.person = person
        _draft = State(initialValue: person.map {
            PersonDraft(name: $0.name, role: $0.role, colorHex: $0.colorHex, companionID: $0.companionID)
        } ?? PersonDraft())
    }

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: $draft.name).textContentType(.name)
                Picker("Role", selection: $draft.role) {
                    Text("Child").tag(ProfileRole.child)
                    Text("Parent").tag(ProfileRole.parent)
                }
            }
            Section("Color") {
                Text("This accent appears around the person’s companion and profile card. Their name and companion always identify them too.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ProfileColorSelector(selection: $draft.colorHex)
            }
            Section("Companion") {
                Picker("Active companion", selection: $draft.companionID) {
                    ForEach(companionChoices, id: \.self) { id in
                        HStack { CompanionArt(id: id).frame(width: 44, height: 44); Text(id.capitalized) }.tag(id)
                    }
                }
            }
        }
        .navigationTitle(person == nil ? "New person" : "Edit person")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if person == nil { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let household = households.first else { return }
                    do {
                        if let person { try app.updatePerson(person, draft: draft, context: context) }
                        else { try app.createPerson(draft, householdID: household.id, context: context) }
                        dismiss()
                    } catch { app.errorMessage = error.localizedDescription }
                }
            }
        }
        .errorAlert(app: app)
    }
}

struct QuestManagementView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Quest.createdAt) private var quests: [Quest]
    @State private var newQuest = false
    @State private var pendingArchive: Quest?

    var body: some View {
        List {
            Section("Active quests") {
                ForEach(quests.filter { $0.deletedAt == nil }) { quest in
                    NavigationLink { QuestEditorView(quest: quest) } label: { QuestManagementLabel(quest: quest) }
                        .swipeActions { Button("Archive", role: .destructive) { pendingArchive = quest } }
                }
                Button("Add quest", systemImage: "plus.circle") { newQuest = true }
            }
            if quests.contains(where: { $0.deletedAt != nil }) {
                Section("Archived quests") {
                    ForEach(quests.filter { $0.deletedAt != nil }) { quest in
                        HStack {
                            NavigationLink {
                                QuestEditorView(quest: quest)
                            } label: {
                                QuestManagementLabel(quest: quest)
                            }
                            Spacer()
                            Button("Restore") {
                                do { try app.restoreQuest(quest, context: context) }
                                catch { app.errorMessage = error.localizedDescription }
                            }.buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .navigationTitle("Quests")
        .toolbar { Button("Add", systemImage: "plus") { newQuest = true } }
        .sheet(isPresented: $newQuest) { NavigationStack { QuestEditorView(quest: nil) } }
        .confirmationDialog("Archive \(pendingArchive?.title ?? "this quest")?", isPresented: Binding(get: { pendingArchive != nil }, set: { if !$0 { pendingArchive = nil } }), titleVisibility: .visible) {
            Button("Archive", role: .destructive) {
                guard let quest = pendingArchive else { return }
                do { try app.archiveQuest(quest, context: context) }
                catch { app.errorMessage = error.localizedDescription }
                pendingArchive = nil
            }
            Button("Cancel", role: .cancel) { pendingArchive = nil }
        } message: { Text("Completion history and awarded XP stay intact.") }
        .errorAlert(app: app)
    }
}

struct QuestManagementLabel: View {
    let quest: Quest
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(quest.title)
            Text("\(quest.xp) XP · \(scheduleLabel(quest))").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func scheduleLabel(_ quest: Quest) -> String {
        switch quest.scheduleKind {
        case .oneTime: return "One time"
        case .daily: return "Daily"
        case .weekly:
            return quest.repeatIntervalWeeks == 2 ? "Every other week" : "Selected weekdays"
        }
    }
}

struct QuestEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var households: [Household]
    @Query(sort: \Person.createdAt) private var people: [Person]
    @Query private var deviceSettings: [LocalDeviceSettings]
    @Query private var reminderPreferences: [LocalQuestReminder]
    let quest: Quest?
    @State private var draft: QuestDraft
    @State private var loadedReminder = false
    @State private var confirmArchive = false

    init(quest: Quest?) {
        self.quest = quest
        var value = QuestDraft()
        if let quest {
            value.title = quest.title; value.detail = quest.detail; value.xp = quest.xp
            value.participantIDs = Set(quest.participantIDs); value.completionMode = quest.completionMode
            value.scheduleKind = quest.scheduleKind; value.weekdays = Set(quest.weekdays)
            value.repeatIntervalWeeks = quest.repeatIntervalWeeks
            value.startDate = quest.startDate
            if let due = quest.dueAt { value.hasDueDate = true; value.dueDate = due; value.hasDueTime = true; value.dueTime = due }
        }
        _draft = State(initialValue: value)
    }

    private var activePeople: [Person] { people.filter { $0.deletedAt == nil } }

    var body: some View {
        Form {
            Section("Quest") {
                TextField("Title", text: $draft.title)
                TextField("Notes (optional)", text: $draft.detail, axis: .vertical).lineLimit(2...5)
                Stepper("\(draft.xp) XP", value: $draft.xp, in: 1...500)
            }
            Section("Assignees") {
                ForEach(activePeople) { person in
                    Button {
                        if draft.participantIDs.contains(person.id) { draft.participantIDs.remove(person.id) }
                        else { draft.participantIDs.insert(person.id) }
                    } label: {
                        HStack {
                            Text(person.name).foregroundStyle(.primary)
                            Spacer()
                            if draft.participantIDs.contains(person.id) { Image(systemName: "checkmark") }
                        }
                    }
                }
                if draft.participantIDs.count > 1 {
                    Picker("Completion", selection: $draft.completionMode) {
                        Text("Each person completes").tag(QuestCompletionMode.individual)
                        Text("Everyone checks in").tag(QuestCompletionMode.sharedAll)
                    }
                }
            }
            Section("Schedule") {
                Picker("Repeats", selection: $draft.scheduleKind) {
                    Text("One time").tag(ScheduleKind.oneTime)
                    Text("Daily").tag(ScheduleKind.daily)
                    Text("Selected weekdays").tag(ScheduleKind.weekly)
                }
                DatePicker("Starts", selection: $draft.startDate, displayedComponents: .date)
                if draft.scheduleKind == .weekly {
                    Picker("Frequency", selection: $draft.repeatIntervalWeeks) {
                        Text("Every week").tag(1)
                        Text("Every other week").tag(2)
                    }
                    WeekdayPicker(selection: $draft.weekdays)
                    if draft.repeatIntervalWeeks == 2 {
                        Text("The week containing the start date is the first active week.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Deadline") {
                Toggle("Add due date", isOn: $draft.hasDueDate)
                if draft.hasDueDate {
                    DatePicker("Due date", selection: $draft.dueDate, displayedComponents: .date)
                    Toggle("Specific time", isOn: $draft.hasDueTime)
                    if draft.hasDueTime { DatePicker("Due time", selection: $draft.dueTime, displayedComponents: .hourAndMinute) }
                    if let household = households.first { Text("Uses \(household.timeZoneIdentifier).").font(.caption).foregroundStyle(.secondary) }
                }
            }
            Section("Reminder on this device") {
                Toggle("Remind me about this quest",
                       isOn: $draft.reminderEnabled)
                if draft.reminderEnabled {
                    DatePicker("Reminder time", selection: $draft.reminderTime,
                               displayedComponents: .hourAndMinute)
                    if deviceSettings.first?.notificationsEnabled != true {
                        Text("Turn on quest reminders in Parent → Reminders to receive this alert.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("This choice stays on this device and is not included in family sync or backups.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if quest != nil {
                Section {
                    Text("Edits apply to current and future appearances. Existing completion records and previously awarded XP are not changed.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Quest status") {
                    if quest?.deletedAt == nil {
                        Button("Archive quest", role: .destructive) {
                            confirmArchive = true
                        }
                    } else if let quest {
                        Button("Restore quest") {
                            do {
                                try app.restoreQuest(quest, context: context)
                                dismiss()
                            } catch {
                                app.errorMessage = error.localizedDescription
                            }
                        }
                    }
                    Text("Archiving hides future appearances but keeps completion history and XP records.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .task {
            guard !loadedReminder,
                  let household = households.first else { return }
            loadedReminder = true
            let calendar = ProgressionEngine.calendar(
                timeZoneIdentifier: household.timeZoneIdentifier)
            if let quest, let preference = reminderPreferences.first(where: {
                $0.questID == quest.id
            }) {
                draft.reminderEnabled = preference.isEnabled
                draft.reminderTime = calendar.date(
                    from: DateComponents(hour: preference.hour,
                                         minute: preference.minute)) ?? .now
            } else if let setting = deviceSettings.first {
                draft.reminderEnabled = quest != nil &&
                    setting.notificationsEnabled
                draft.reminderTime = calendar.date(from: DateComponents(
                    hour: setting.defaultReminderHour,
                    minute: setting.defaultReminderMinute)) ?? .now
            }
        }
        .confirmationDialog("Archive this quest?",
                            isPresented: $confirmArchive,
                            titleVisibility: .visible) {
            Button("Archive", role: .destructive) {
                guard let quest else { return }
                do {
                    try app.archiveQuest(quest, context: context)
                    dismiss()
                } catch { app.errorMessage = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Completion history and awarded XP stay intact.")
        }
        .navigationTitle(quest == nil ? "New quest" : "Edit quest")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if quest == nil { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let household = households.first else { return }
                    do {
                        if let quest { try app.updateQuest(quest, draft: draft, household: household, people: people, context: context) }
                        else { try app.createQuest(draft, household: household, people: people, context: context) }
                        dismiss()
                    } catch { app.errorMessage = error.localizedDescription }
                }
            }
        }
        .errorAlert(app: app)
    }
}

struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    private let days = [(1, "Sun"), (2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat")]
    var body: some View {
        VStack(alignment: .leading) {
            Text("Weekdays").font(.subheadline)
            ViewThatFits {
                HStack { buttons }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 54))]) { buttons }
            }
        }
    }
    @ViewBuilder private var buttons: some View {
        ForEach(days, id: \.0) { number, label in
            Button(label) {
                if selection.contains(number) { selection.remove(number) } else { selection.insert(number) }
            }
            .buttonStyle(.bordered)
            .tint(selection.contains(number) ? .purple : .secondary)
            .accessibilityValue(selection.contains(number) ? "Selected" : "Not selected")
        }
    }
}

struct CloudSyncSettingsView: View {
    @Environment(CloudSyncController.self) private var sync
    @Environment(AutomaticSyncCoordinator.self) private var automaticSync
    @Environment(\.modelContext) private var context
    @Query private var households: [Household]
    @Query private var people: [Person]
    @Query private var quests: [Quest]
    @Query private var completions: [QuestCompletion]
    @Query private var goals: [RewardGoal]
    @Query private var sharedSettings: [HouseholdSettings]
    @Query private var cloudStates: [HouseholdCloudState]
    @Query private var pending: [PendingSyncMutation]
    @State private var confirmEnable = false
    @StateObject private var sharingSheet = CloudSharingSheetModel()
    private let configuration = KyndynCloudConfiguration()

    private var household: Household? { households.first }
    private var state: HouseholdCloudState? {
        guard let household else { return nil }
        return cloudStates.first { $0.householdID == household.id }
    }

    var body: some View {
        List {
            Section("Status") {
                LabeledContent("This household", value: modeText)
                    .accessibilityIdentifier("cloud-household-mode")
                LabeledContent("Sync", value: automaticStatusText)
                    .accessibilityLabel(
                        "Family sync status, \(automaticStatusText)")
                if !pending.isEmpty {
                    LabeledContent("Waiting to sync", value: "\(pending.count) changes")
                }
                if let date = state?.lastSuccessfulSyncAt {
                    LabeledContent("Last updated", value: date.formatted())
                }
                if case .ready = configuration.readiness {
                    EmptyView()
                } else {
                    Label(configuration.readiness.developmentMessage,
                          systemImage: "wrench.and.screwdriver")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("cloud-configuration-readiness")
                }
            }
            Section("What family sync does") {
                Text("Keeps people, quests, schedules, completions, rewards, and shared household settings consistent across invited devices.")
                Text("Your kyndyn PIN, authentication, notification permission, quiet hours, and device preferences stay only on this device.")
                    .foregroundStyle(.secondary)
            }
            if let household {
                let preview = sync.preview(
                    household: household, people: people, quests: quests,
                    completions: completions, goals: goals)
                Section("Ready to synchronize") {
                    LabeledContent("People", value: "\(preview.people)")
                    LabeledContent("Quests", value: "\(preview.quests)")
                    LabeledContent("Completion events", value: "\(preview.completions)")
                    LabeledContent("Cloud records", value: "\(preview.totalRecords)")
                }
                Section {
                    if state?.mode == .owner || state?.mode == .participant ||
                        (state?.mode == .recoverableError &&
                         state?.provisioningStage == .roundTripVerified) {
                        Button("Refresh now", systemImage: "arrow.clockwise") {
                            automaticSync.request(.manual)
                        }
                        .disabled(sync.isWorking || automaticSync.isRunning)
                        if state?.databaseScope == .privateDatabase,
                           let zoneName = state?.zoneName,
                           let shareRecordName = state?.shareRecordName {
                            Button("Invite or manage family",
                                   systemImage: "person.2.badge.plus") {
                                Task {
                                    await sharingSheet.prepare(
                                        zoneName: zoneName,
                                        shareRecordName: shareRecordName)
                                }
                            }
                            .disabled(sync.isWorking)
                            .accessibilityHint(
                                "Opens Apple’s private family invitation screen")
                        }
                    } else {
                        Button("Enable family sync", systemImage: "icloud.and.arrow.up") {
                            confirmEnable = true
                        }
                        .disabled(sync.isWorking || !configurationIsReady)
                    }
                } footer: {
                    Text("Live family sync requires the authorized Apple Developer team and iCloud container. Until configured, kyndyn stays safely local-only.")
                }
            }
        }
        .accessibilityIdentifier("cloud-sync-settings")
        .navigationTitle("Family sync")
        .confirmationDialog(
            "Enable family sync?",
            isPresented: $confirmEnable,
            titleVisibility: .visible
        ) {
            Button("Enable and upload") { enable() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("kyndyn will prepare this household in the owner’s iCloud and create an Apple sharing invitation. Local data remains available if setup is interrupted.")
        }
        .sheet(isPresented: $sharingSheet.isPresented) {
            SystemCloudSharingSheet(model: sharingSheet)
        }
        .alert(
            "Invitation unavailable",
            isPresented: Binding(
                get: { sharingSheet.errorMessage != nil },
                set: { if !$0 { sharingSheet.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) { sharingSheet.clearError() }
        } message: {
            Text(sharingSheet.errorMessage ?? "")
        }
        .task { ensureState() }
    }

    private var modeText: String {
        switch state?.mode ?? .localOnly {
        case .localOnly: return "Only on this device"
        case .preparing: return "Preparing family sync"
        case .owner: return "Hosted by you"
        case .participant: return "Shared with you"
        case .unavailable: return "iCloud unavailable"
        case .accountChanged: return "iCloud account changed"
        case .paused: return "Paused"
        case .recoverableError: return "Will retry"
        case .needsAttention: return "Needs attention"
        }
    }

    private var automaticStatusText: String {
        switch automaticSync.displayState {
        case .synchronizing: return "Synchronizing"
        case .upToDate: return "Up to date"
        case .offline: return "Offline — changes are safe"
        case .waiting: return "Waiting for Apple or network"
        case .needsAttention: return sync.statusMessage
        case .localOnly: return sync.statusMessage
        }
    }

    private var configurationIsReady: Bool {
        if case .ready = configuration.readiness { return true }
        return false
    }

    private func ensureState() {
        guard let household, state == nil else { return }
        context.insert(HouseholdCloudState(householdID: household.id))
        try? context.save()
    }

    private func enable() {
        guard let household else { return }
        let cloudState = state ?? {
            let value = HouseholdCloudState(householdID: household.id)
            context.insert(value)
            return value
        }()
        var records = [SyncSnapshot.household(household)]
        records += people.map { SyncSnapshot.person($0) }
        records += quests.flatMap { SyncSnapshot.quest($0) }
        records += completions.map { SyncSnapshot.completion($0) }
        records += goals.map { SyncSnapshot.reward($0) }
        records += sharedSettings.map { SyncSnapshot.settings($0) }
        Task {
            await sync.provisionOwner(
                household: household, records: records,
                state: cloudState, context: context)
            if cloudState.mode == .owner {
                automaticSync.request(.accountRecovery)
            }
        }
    }
}

struct ParentSecurityView: View {
    @EnvironmentObject private var access: ParentAccessController
    @State private var pin = ""
    @State private var confirmation = ""
    @State private var message: String?
    @State private var confirmDisable = false

    var body: some View {
        Form {
            Section {
                Text("Face ID, Touch ID, or the device passcode is kyndyn’s primary parent check. A kyndyn PIN is an optional fallback stored only in this device’s Keychain.")
            }
            Section(access.hasPIN ? "Change kyndyn PIN" : "Add kyndyn PIN") {
                SecureField("New 6–12 digit PIN", text: $pin).keyboardType(.numberPad)
                SecureField("Confirm PIN", text: $confirmation).keyboardType(.numberPad)
                Button(access.hasPIN ? "Change PIN" : "Save PIN") {
                    guard pin == confirmation else { message = "The PIN entries don’t match."; return }
                    if let validation = PINValidation.message(for: pin) { message = validation; return }
                    do { try access.configurePIN(pin); pin = ""; confirmation = ""; message = "kyndyn PIN saved securely on this device." }
                    catch { message = error.localizedDescription }
                }.disabled(pin.isEmpty || confirmation.isEmpty)
            }
            if access.hasPIN {
                Section {
                    Button("Disable kyndyn PIN", role: .destructive) { confirmDisable = true }
                }
            }
            if let message { Section { Text(message).foregroundStyle(.secondary) } }
            Section("Recovery limitation") {
                Text("kyndyn has no server account or email recovery. If you forget the kyndyn PIN, use the device owner authentication to enter this screen and replace it. If device authentication is also unavailable, kyndyn cannot safely prove parental identity.")
            }
        }
        .navigationTitle("Parent security")
        .confirmationDialog("Disable the kyndyn PIN?", isPresented: $confirmDisable, titleVisibility: .visible) {
            Button("Disable PIN", role: .destructive) {
                do { try access.disablePIN(); message = "kyndyn PIN disabled." }
                catch { message = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var households: [Household]
    @Query private var people: [Person]
    @Query private var quests: [Quest]
    @Query private var completions: [QuestCompletion]
    @Query private var reminderPreferences: [LocalQuestReminder]
    @Query private var settings: [LocalDeviceSettings]
    @State private var permission: NotificationPermissionState = .notDetermined
    @State private var explanation = false
    private let scheduler: NotificationScheduling = UserNotificationScheduler()

    var body: some View {
        Form {
            if let setting = settings.first {
                Section("Permission") {
                    LabeledContent("Status", value: permission.rawValue.readable)
                    if permission == .notDetermined {
                        Button("Turn on reminders") { explanation = true }
                    } else if permission == .denied {
                        Text("Notifications are off in iOS Settings. kyndyn still works normally.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("This device") {
                    Toggle("Enable quest reminders", isOn: binding(setting, \.notificationsEnabled))
                    Picker("Device profile", selection: optionalBinding(setting, \.devicePersonID)) {
                        Text("Not assigned").tag(UUID?.none)
                        ForEach(people.filter { $0.deletedAt == nil }) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Toggle("Eligible for parent summaries", isOn: binding(setting, \.parentSummaryEligible))
                        .disabled(people.first(where: { $0.id == setting.devicePersonID })?.role != .parent)
                }
                Section("Timing") {
                    DatePicker("Default reminder", selection: timeBinding(setting, hour: \.defaultReminderHour, minute: \.defaultReminderMinute), displayedComponents: .hourAndMinute)
                    DatePicker("Quiet hours start", selection: timeBinding(setting, hour: \.quietStartHour, minute: \.quietStartMinute), displayedComponents: .hourAndMinute)
                    DatePicker("Quiet hours end", selection: timeBinding(setting, hour: \.quietEndHour, minute: \.quietEndMinute), displayedComponents: .hourAndMinute)
                }
                Section("Lock screen privacy") {
                    Toggle("Show quest titles", isOn: binding(setting, \.showQuestDetailsOnLockScreen))
                    Text(setting.showQuestDetailsOnLockScreen ? "Reminder previews may reveal quest names on the lock screen." : "Reminders use general wording until kyndyn is opened.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView("Settings unavailable", systemImage: "gear.badge.questionmark", description: Text("Reopen kyndyn and try again."))
            }
        }
        .navigationTitle("Reminders")
        .task { permission = await scheduler.permissionState(); await reschedule() }
        .onChange(of: settings.first?.notificationsEnabled) { _, _ in Task { await reschedule() } }
        .onChange(of: settings.first?.devicePersonID) { _, _ in Task { await reschedule() } }
        .alert("Useful, private reminders", isPresented: $explanation) {
            Button("Not now", role: .cancel) {}
            Button("Continue") {
                Task { permission = await scheduler.requestPermission(); await reschedule() }
            }
        } message: {
            Text("kyndyn can remind this device about locally stored quests. You choose the profile, timing, and whether quest names appear.")
        }
    }

    private func binding<T>(_ setting: LocalDeviceSettings, _ keyPath: ReferenceWritableKeyPath<LocalDeviceSettings, T>) -> Binding<T> {
        Binding(get: { setting[keyPath: keyPath] }, set: { setting[keyPath: keyPath] = $0; try? context.save(); Task { await reschedule() } })
    }
    private func optionalBinding(_ setting: LocalDeviceSettings, _ keyPath: ReferenceWritableKeyPath<LocalDeviceSettings, UUID?>) -> Binding<UUID?> {
        binding(setting, keyPath)
    }
    private func timeBinding(_ setting: LocalDeviceSettings, hour: ReferenceWritableKeyPath<LocalDeviceSettings, Int>, minute: ReferenceWritableKeyPath<LocalDeviceSettings, Int>) -> Binding<Date> {
        Binding(get: {
            Calendar.current.date(from: DateComponents(hour: setting[keyPath: hour], minute: setting[keyPath: minute])) ?? .now
        }, set: {
            setting[keyPath: hour] = Calendar.current.component(.hour, from: $0)
            setting[keyPath: minute] = Calendar.current.component(.minute, from: $0)
            try? context.save(); Task { await reschedule() }
        })
    }
    private func reschedule() async {
        guard let setting = settings.first, let household = households.first else { return }
        if people.first(where: { $0.id == setting.devicePersonID })?.role != .parent { setting.parentSummaryEligible = false }
        let candidates = ReminderRules.candidates(
            quests: quests, people: people, settings: setting,
            household: household, completions: completions,
            reminderPreferences: reminderPreferences, now: .now)
        do { try await scheduler.replaceKyndynReminders(with: candidates) }
        catch { app.errorMessage = "kyndyn couldn’t update reminders. Your quests are unchanged." }
    }
}

// MARK: - Shared presentation

struct ProfileColorSelector: View {
    @Binding var selection: String

    private var customColor: Binding<Color> {
        Binding(
            get: { Color(hex: selection) },
            set: { selection = $0.hexRGB ?? selection })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: selection))
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 2))
                    .shadow(color: Color(hex: selection).opacity(0.25), radius: 4, y: 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ProfilePalette.name(for: selection)).font(.headline)
                    Text("Profile and app accent")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Selected color, \(ProfilePalette.name(for: selection))")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 8)], spacing: 12) {
                ForEach(colorChoices, id: \.self) { color in
                    Button { selection = color } label: {
                        VStack(spacing: 5) {
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 42, height: 42)
                                .overlay {
                                    Circle().stroke(
                                        selection.uppercased() == color ? Color.primary : .clear,
                                        lineWidth: 3)
                                        .padding(-4)
                                }
                                .overlay {
                                    if selection.uppercased() == color {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold()).foregroundStyle(.white)
                                    }
                                }
                            Text(ProfilePalette.name(for: color))
                                .font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(ProfilePalette.name(for: color)) profile color")
                    .accessibilityValue(selection.uppercased() == color ? "Selected" : "Not selected")
                    .accessibilityIdentifier("profile-color-\(color)")
                }
            }

            ColorPicker("Choose any color", selection: customColor, supportsOpacity: false)
                .accessibilityIdentifier("profile-custom-color")
        }
    }
}

struct CompanionArt: View {
    let id: String
    var body: some View {
        Group {
            if let path = Bundle.main.path(forResource: id, ofType: "png"),
               let image = UIImage(contentsOfFile: path) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "sparkles").resizable().scaledToFit().foregroundStyle(.purple)
            }
        }
            .accessibilityLabel("\(id.capitalized), kyndyn companion")
    }
}

struct ProgressStat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore).accessibilityLabel("\(label), \(value)")
    }
}

extension View {
    func card() -> some View {
        kyndynCard()
    }
    func errorAlert(app: AppModel) -> some View {
        alert("kyndyn couldn’t save that", isPresented: Binding(get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(app.errorMessage ?? "") }
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0x6F2DBD
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }

    var hexRGB: String? {
        let resolved = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: nil) else {
            return nil
        }
        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded()))
    }
}

private extension String {
    var readable: String {
        switch self {
        case "notDetermined": return "Not requested"
        case "denied": return "Denied"
        case "provisional": return "Provisional"
        case "authorized": return "Allowed"
        default: return "Unavailable"
        }
    }
}

#if DEBUG
#Preview("Compact square onboarding") {
    OnboardingView()
        .environment(AppModel())
        .frame(width: 520, height: 520)
}
#endif
