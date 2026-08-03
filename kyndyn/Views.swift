import SwiftUI
import SwiftData

private let companionChoices = ["spark", "orbit", "pixel", "comet", "bop"]
private let colorChoices = ["#6F2DBD", "#007AFF", "#00A6A6", "#34C759", "#F26B5B", "#FF9500"]

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
        case "#007AFF": return "Blue"
        case "#00A6A6": return "Teal"
        case "#34C759": return "Green"
        case "#F26B5B": return "Coral"
        case "#FF9500": return "Orange"
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

    var body: some View {
        ZStack {
            Group {
                if shareInbox.pending != nil ||
                    pendingInvitations.contains(where: { $0.stateRaw == "pending" }) {
                    InvitationLandingView()
                } else if households.isEmpty {
                    OnboardingView()
                } else if app.selectedPersonID == nil {
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
        .tint(.purple)
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
    @EnvironmentObject private var parentAccess: ParentAccessController
    @Environment(\.modelContext) private var context
    @State private var isWorking = false
    @State private var showSetup = false
    @State private var showImporter = false
    @State private var pendingImportData: Data?
    @State private var pendingImportKind: TransferReport.Source?
    @State private var importReport: TransferReport?
    @State private var showImportConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "leaf.fill").font(.system(size: 58)).foregroundStyle(.purple)
                Text("Welcome to kyndyn").font(.largeTitle.bold()).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("A calm home base for quests, progress, and family wins. Start your own family or explore safely with fictional sample data.")
                    .font(.title3).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button {
                    showSetup = true
                } label: {
                    Label("Set up my family", systemImage: "house.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                Button {
                    isWorking = true
                    do { try app.seedSample(into: context) } catch { app.errorMessage = error.localizedDescription }
                    isWorking = false
                } label: {
                    Label("Create a sample household", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large).disabled(isWorking)
                Button("Restore or migrate a household", systemImage: "square.and.arrow.down") {
                    Task {
                        await parentAccess.authenticate()
                        if parentAccess.isUnlocked { showImporter = true }
                    }
                }
                .buttonStyle(.borderless)
                Text("Sample mode uses fictional people and stays separate from your family. Restores and Rowan migrations require an empty installation.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(32).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background(KyndynLaunchBackground())
        .accessibilityIdentifier("onboarding")
        .sheet(isPresented: $showSetup) {
            HouseholdSetupView()
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
                    Picker("Profile color", selection: $draft.parent.colorHex) {
                        ForEach(colorChoices, id: \.self) {
                            Text(ProfilePalette.name(for: $0)).tag($0)
                        }
                    }
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
                            if let setting = settings.first { setting.selectedPersonID = person.id }
                            try? context.save()
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
    private var selected: Person? { people.first { $0.id == app.selectedPersonID } }

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            DashboardView().tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
            QuestListView().tabItem { Label("Quests", systemImage: "checklist") }.tag(1)
            if selected?.role == .parent {
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
    @Query private var households: [Household]
    @Query private var people: [Person]
    @Query private var completions: [QuestCompletion]
    private var person: Person? { people.first { $0.id == app.selectedPersonID } }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let person, let household = households.first {
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
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 145), spacing: 12)],
                            spacing: 12
                        ) {
                            stats(progress)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            ViewThatFits(in: .horizontal) {
                                HStack {
                                    Text(household.rewardTitle).font(.headline)
                                    Spacer()
                                    rewardProgress(household)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(household.rewardTitle).font(.headline)
                                    rewardProgress(household)
                                }
                            }
                            ProgressView(value: min(Double(ProgressionEngine.familyXP(completions)), Double(household.rewardGoalXP)), total: Double(household.rewardGoalXP))
                        }.card()
                        QuestListView(compact: true)
                    }
                    .padding()
                    .frame(maxWidth: AdaptiveLayout.readableContentMaximum)
                    .frame(maxWidth: .infinity)
                }
            }.navigationTitle("Today")
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
        Text("\(ProgressionEngine.familyXP(completions)) / \(household.rewardGoalXP) XP")
            .font(.subheadline.monospacedDigit())
    }

    @ViewBuilder private func stats(_ progress: PersonProgress) -> some View {
        StatCard(value: "\(progress.xp)", label: "XP")
        StatCard(value: "\(progress.level)", label: "Level")
        StatCard(value: "\(progress.currentStreak)", label: "Day streak")
    }
}

struct QuestListView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var households: [Household]
    @Query(sort: \Quest.createdAt) private var quests: [Quest]
    @Query private var completions: [QuestCompletion]
    var compact = false

    private var visible: [(Quest, QuestTemporalStatus)] {
        guard let household = households.first, let personID = app.selectedPersonID else { return [] }
        return quests.compactMap {
            let status = ProgressionEngine.temporalStatus(for: $0, personID: personID, completions: completions, now: .now, timeZoneIdentifier: household.timeZoneIdentifier)
            return status == .inactive || status == .upcoming ? nil : ($0, status)
        }.sorted { lhs, rhs in
            let order: [QuestTemporalStatus: Int] = [.overdue: 0, .today: 1, .completed: 2]
            return order[lhs.1, default: 9] < order[rhs.1, default: 9]
        }
    }

    var body: some View {
        Group {
            if compact { content } else { NavigationStack { ScrollView { content.padding() }.navigationTitle("Today’s quests") } }
        }.errorAlert(app: app)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if compact { Text("Your quests").font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader) }
            if visible.isEmpty {
                ContentUnavailableView("All clear", systemImage: "checkmark.circle", description: Text("No quests are waiting for you today."))
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 300, maximum: 540), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(visible, id: \.0.id) { quest, status in
                    QuestRow(quest: quest, status: status)
                }
            }
        }
        .frame(maxWidth: AdaptiveLayout.readableContentMaximum)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func QuestRow(quest: Quest, status: QuestTemporalStatus) -> some View {
        if let household = households.first, let personID = app.selectedPersonID {
            let done = status == .completed
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    completionButton(
                        quest: quest, done: done, personID: personID,
                        household: household
                    )
                    questDetails(quest: quest, status: status, done: done)
                    Spacer()
                    xpLabel(quest: quest, done: done, household: household)
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        completionButton(
                            quest: quest, done: done, personID: personID,
                            household: household
                        )
                        questDetails(quest: quest, status: status, done: done)
                    }
                    xpLabel(quest: quest, done: done, household: household)
                }
            }.card()
        }
    }

    private func completionButton(
        quest: Quest, done: Bool, personID: UUID, household: Household
    ) -> some View {
        Button {
            do {
                if done {
                    try app.undo(
                        quest, personID: personID, household: household,
                        completions: completions, context: context
                    )
                } else {
                    try app.complete(
                        quest, personID: personID, household: household,
                        completions: completions, context: context
                    )
                }
            } catch {
                app.errorMessage = error.localizedDescription
            }
        } label: {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title)
                .foregroundStyle(done ? .green : .purple)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(done ? "Undo \(quest.title)" : "Complete \(quest.title)")
        .accessibilityHint(done
            ? "Reverses this occurrence and recalculates progress"
            : "Records this occurrence as complete")
        .accessibilityIdentifier("quest-toggle-\(quest.title)")
    }

    private func questDetails(
        quest: Quest, status: QuestTemporalStatus, done: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(quest.title).font(.headline).strikethrough(done)
            if !quest.detail.isEmpty {
                Text(quest.detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(statusLabel(status, quest: quest))
                .font(.caption)
                .foregroundStyle(status == .overdue ? .orange : .secondary)
        }
    }

    private func xpLabel(
        quest: Quest, done: Bool, household: Household
    ) -> some View {
        let value = done ? quest.xp : ProgressionEngine.effectiveXP(
            base: quest.xp,
            overdueDays: ProgressionEngine.overdueDays(
                for: quest, now: .now,
                timeZoneIdentifier: household.timeZoneIdentifier
            )
        )
        return Text("+\(value) XP")
            .font(.subheadline.bold())
            .foregroundStyle(.purple)
    }

    private func statusLabel(_ status: QuestTemporalStatus, quest: Quest) -> String {
        let mode = quest.completionMode == .sharedAll ? "Shared check-in" : "Individual"
        switch status {
        case .overdue: return "Overdue · \(mode)"
        case .completed: return "Completed · tap to undo"
        default: return mode
        }
    }
}

// MARK: - Parent area

struct ParentAreaView: View {
    @EnvironmentObject private var access: ParentAccessController
    @Query private var households: [Household]
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
                Section {
                    NavigationLink { PeopleManagementView() } label: { Label("People", systemImage: "person.2.fill") }
                    NavigationLink { QuestManagementView() } label: { Label("Quests", systemImage: "checklist") }
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
            }
            .frame(maxWidth: AdaptiveLayout.managementContentMaximum)
            .frame(maxWidth: .infinity)
            .navigationTitle("Parent")
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 54))]) {
                    ForEach(colorChoices, id: \.self) { color in
                        Button { draft.colorHex = color } label: {
                            Circle().fill(Color(hex: color)).frame(width: 42, height: 42)
                                .overlay { if draft.colorHex == color { Image(systemName: "checkmark").foregroundStyle(.white).bold() } }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(ProfilePalette.name(for: color)) profile color")
                        .accessibilityValue(draft.colorHex == color ? "Selected" : "Not selected")
                        .accessibilityIdentifier("profile-color-\(color)")
                    }
                }
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
                            QuestManagementLabel(quest: quest)
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
    let quest: Quest?
    @State private var draft: QuestDraft

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
            if quest != nil {
                Section {
                    Text("Edits apply to current and future appearances. Existing completion records and previously awarded XP are not changed.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
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
        let candidates = ReminderRules.candidates(quests: quests, people: people, settings: setting, household: household, now: .now)
        do { try await scheduler.replaceKyndynReminders(with: candidates) }
        catch { app.errorMessage = "kyndyn couldn’t update reminders. Your quests are unchanged." }
    }
}

// MARK: - Shared presentation

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

struct StatCard: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).card()
        .accessibilityElement(children: .ignore).accessibilityLabel("\(label), \(value)")
    }
}

extension View {
    func card() -> some View {
        padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.08)) }
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
