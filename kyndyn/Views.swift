import SwiftUI
import SwiftData
import UIKit

private let companionChoices = CollectionCatalog.companionIDs
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
    @State private var showFamilySetupGuide = false

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
                    OnboardingView {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(350))
                            showFamilySetupGuide = true
                        }
                    }
                } else if app.selectedPersonID == nil &&
                            deviceSettings.first?.showsHouseholdDashboard != true {
                    ProfilePickerView()
                } else {
                    MainView()
                }
            }
            .opacity(app.isPreparing ? 0 : 1)
            if app.isPreparing {
                KyndynStartupView()
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
        .sheet(isPresented: $showFamilySetupGuide) {
            FamilySetupGuideView(isFirstRun: true)
        }
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

private enum OnboardingLesson: Int, CaseIterable {
    case familyLoop, profiles, sync, backup

    var icon: String {
        switch self {
        case .familyLoop: "checkmark.circle"
        case .profiles: "person.3"
        case .sync: "icloud"
        case .backup: "externaldrive"
        }
    }

    var title: String {
        switch self {
        case .familyLoop: "Small quests. Shared progress."
        case .profiles: "Profiles and invitations are different"
        case .sync: "Choose how your family stays connected"
        case .backup: "Keep a private backup too"
        }
    }

    var detail: String {
        switch self {
        case .familyLoop:
            "Parents create quests. Family members complete them, earn XP, and move the family reward forward."
        case .profiles:
            "Add a profile for each person in your household. Invite another device only after family sync is enabled."
        case .sync:
            "Kyndyn works on one device without iCloud. Family sync lets invited Apple devices share changes, but background delivery is not guaranteed."
        case .backup:
            "An exported backup is separate from iCloud sync. Store it privately in Files so you can restore an empty installation later."
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
    @State private var lessonIndex = 0
    @State private var introductionComplete = false
    let onHouseholdCreated: () -> Void

    init(onHouseholdCreated: @escaping () -> Void = {}) {
        self.onHouseholdCreated = onHouseholdCreated
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image("KyndynMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                Text("Welcome to kyndyn").font(.largeTitle.bold()).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if introductionComplete {
                    Text("Choose how you want to begin.")
                        .font(.title3).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    onboardingActions
                        .accessibilityIdentifier("onboarding-actions")
                } else {
                    let lesson = OnboardingLesson.allCases[lessonIndex]
                    Image(systemName: lesson.icon)
                        .font(.system(size: 42))
                        .foregroundStyle(.purple)
                        .accessibilityHidden(true)
                    Text(lesson.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(lesson.detail)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(lessonIndex + 1),
                                 total: Double(OnboardingLesson.allCases.count))
                        .accessibilityLabel("Introduction step \(lessonIndex + 1) of \(OnboardingLesson.allCases.count)")
                    Button(lessonIndex == OnboardingLesson.allCases.count - 1
                           ? "Choose how to begin" : "Continue") {
                        if lessonIndex == OnboardingLesson.allCases.count - 1 {
                            introductionComplete = true
                        } else {
                            lessonIndex += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("onboarding-next")
                    Button("Skip introduction") {
                        introductionComplete = true
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("onboarding-skip")
                }
            }
            .padding(32).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background(KyndynLaunchBackground())
        .accessibilityIdentifier("onboarding")
        .sheet(isPresented: $showSetup) {
            HouseholdSetupView(onCreated: onHouseholdCreated)
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

    @ViewBuilder
    private var onboardingActions: some View {
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
}

struct CloudHouseholdRecoveryView: View {
    @Environment(CloudSyncController.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var candidates = [CloudHouseholdCandidate]()
    @State private var hasChecked = false
    @State private var selectedCandidate: CloudHouseholdCandidate?

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
                                selectedCandidate = candidate
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
            .sheet(item: $selectedCandidate) { candidate in
                CloudRecoveryPreviewView(candidate: candidate) {
                    selectedCandidate = nil
                    dismiss()
                }
            }
        }
    }

    private func check() {
        Task {
            candidates = await sync.discoverRecoverableHouseholds()
            hasChecked = true
        }
    }

}

struct CloudRecoveryPreviewView: View {
    @Environment(CloudSyncController.self) private var sync
    @Environment(AppModel.self) private var app
    @Environment(AutomaticSyncCoordinator.self) private var automaticSync
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let candidate: CloudHouseholdCandidate
    let onFinished: () -> Void
    @State private var isRecovering = false
    @State private var didRecover = false

    private var preview: CloudRecoveryPreview {
        CloudRecoveryAudit.preview(candidate)
    }

    var body: some View {
        NavigationStack {
            Group {
                if didRecover {
                    List {
                        Section {
                            ContentUnavailableView(
                                "Recovery complete",
                                systemImage: "checkmark.icloud.fill",
                                description: Text(
                                    "Kyndyn verified the recovered profiles, quests, and history before saving them."))
                        }
                        recoveryCounts
                        Section {
                            Button("Continue to my family") { onFinished() }
                                .frame(maxWidth: .infinity)
                                .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    List {
                        Section {
                            KyndynCallout(
                                kind: preview.isSafeToRecover ? .information : .caution,
                                message: preview.isSafeToRecover
                                    ? "Review what Kyndyn found before anything is saved on this device."
                                    : "This cloud copy did not pass Kyndyn’s safety checks and will not be restored.")
                        }
                        recoveryCounts
                        if !preview.issues.isEmpty {
                            Section("Needs attention") {
                                ForEach(preview.issues, id: \.self) { issue in
                                    Label(issue, systemImage: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        Section("What happens next") {
                            Text("Recovery creates this household on an empty installation. It does not delete or modify the cloud copy.")
                            Text("Kyndyn verifies the restored record counts before reporting success. Keep a separate private backup after recovery.")
                                .foregroundStyle(.secondary)
                        }
                        if isRecovering {
                            Section { ProgressView("Verifying and recovering…") }
                        } else if sync.lastErrorCategory != nil {
                            Section { KyndynCallout(kind: .caution, message: sync.statusMessage) }
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        Button("Recover this family", systemImage: "icloud.and.arrow.down") {
                            recover()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!preview.isSafeToRecover || isRecovering)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                    }
                }
            }
            .navigationTitle(didRecover ? "Recovered" : "Review recovery")
            .toolbar {
                if !didRecover {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(isRecovering)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isRecovering)
    }

    @ViewBuilder private var recoveryCounts: some View {
        Section(preview.householdName) {
            LabeledContent("Profiles", value: "\(preview.activePeople) active · \(preview.people) total")
            LabeledContent("Quests", value: "\(preview.quests - preview.archivedQuests) active · \(preview.quests) total")
            LabeledContent("Completion history", value: "\(preview.completions)")
            if preview.undoneCompletions > 0 {
                LabeledContent("Undone completions", value: "\(preview.undoneCompletions)")
            }
            LabeledContent("Starting XP adjustments", value: "\(preview.startingXP) XP")
            LabeledContent("Active completion XP", value: "\(preview.awardedXP) XP")
        }
    }

    private func recover() {
        isRecovering = true
        Task {
            defer { isRecovering = false }
            guard await sync.recoverHousehold(candidate, context: context) != nil else {
                return
            }
            let recoveredPeople = (try? context.fetch(FetchDescriptor<Person>())) ?? []
            app.selectedPersonID = recoveredPeople.first(where: {
                $0.householdID == candidate.householdID && $0.deletedAt == nil
            })?.id
            automaticSync.request(.accountRecovery)
            didRecover = true
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
    let onCreated: () -> Void

    init(onCreated: @escaping () -> Void = {}) {
        self.onCreated = onCreated
    }

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
            onCreated()
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
    @Environment(AutomaticSyncCoordinator.self) private var automaticSync
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Person.createdAt) private var people: [Person]
    @Query private var completions: [QuestCompletion]
    @Query private var settings: [LocalDeviceSettings]
    @State private var isPullRefreshing = false

    private var activePeople: [Person] {
        people.filter { $0.deletedAt == nil }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 28) {
                        VStack(spacing: 8) {
                            Text("Who’s using kyndyn?")
                                .font(.largeTitle.bold())
                                .accessibilityAddTraits(.isHeader)
                            Text("Choose a profile to see the right quests.")
                                .foregroundStyle(.secondary)
                        }
                        LazyVGrid(
                            columns: profileColumns(for: proxy.size.width),
                            spacing: 26
                        ) {
                            ForEach(activePeople) { person in
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
                                    VStack(spacing: 10) {
                                        CompanionArt(id: person.companionID)
                                            .frame(width: 94, height: 94)
                                            .padding(10)
                                            .background(
                                                Color(hex: person.colorHex).opacity(0.15),
                                                in: Circle())
                                            .overlay {
                                                Circle().stroke(
                                                    Color(hex: person.colorHex),
                                                    lineWidth: app.selectedPersonID == person.id ? 6 : 3
                                                )
                                            }
                                            .shadow(
                                                color: Color(hex: person.colorHex).opacity(0.22),
                                                radius: 10, y: 5)
                                        Text(person.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(person.role == .parent ? "Parent" : "Family member")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        HStack(spacing: 8) {
                                            Text("Level \(level(for: person))")
                                            if badgeCount(for: person) > 0 {
                                                Label("\(badgeCount(for: person))", systemImage: "medal.fill")
                                            }
                                        }
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color(hex: person.colorHex))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(person.name), \(person.role == .parent ? "parent" : "family member")")
                                .accessibilityValue("Level \(level(for: person)), \(badgeCount(for: person)) badges, \(ProfilePalette.name(for: person.colorHex)) profile color")
                                .accessibilityHint("Opens this person’s home")
                                .accessibilityIdentifier("profile-\(person.name)")
                            }
                        }
                        .frame(width: profileGridWidth(for: proxy.size.width))
                        .frame(maxWidth: AdaptiveLayout.readableContentMaximum)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height, alignment: .center)
                }
                .refreshable {
                    await refreshFamilyData()
                }
                .refreshStatusPill(isRefreshing: isPullRefreshing, topPadding: 58)
            }
            .background(KyndynScreenBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func profileColumns(for width: CGFloat) -> [GridItem] {
        guard width >= 700 else {
            return [GridItem(.adaptive(minimum: 128, maximum: 190), spacing: 24)]
        }
        return Array(
            repeating: GridItem(.fixed(190), spacing: 24, alignment: .top),
            count: max(1, min(activePeople.count, 4)))
    }

    private func profileGridWidth(for width: CGFloat) -> CGFloat? {
        guard width >= 700 else { return nil }
        let count = CGFloat(max(1, min(activePeople.count, 4)))
        return count * 190 + (count - 1) * 24
    }

    private func refreshFamilyData() async {
        isPullRefreshing = true
        defer { isPullRefreshing = false }
        await Task.yield()
        async let minimumVisibleTime: Void = Task.sleep(for: .milliseconds(550))
        automaticSync.request(.manual)
        await automaticSync.waitUntilIdle()
        try? await minimumVisibleTime
    }

    private func level(for person: Person) -> Int {
        let questXP = completions.lazy
            .filter { $0.personID == person.id && $0.reversedAt == nil }
            .reduce(0) { $0 + $1.awardedXP }
        return max(0, questXP + person.startingXPAdjustment) / 100 + 1
    }

    private func badgeCount(for person: Person) -> Int {
        RecognitionEngine.normalizedBadges(person.earnedBadgeIDs).count
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
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(2)
            if selected?.role == .parent ||
                (selected == nil && devicePerson?.role == .parent) {
                Group {
                    if parentAccess.isUnlocked { ParentAreaView() }
                    else { ParentAuthenticationView() }
                }
                .tabItem { Label("Parent", systemImage: "lock.shield.fill") }.tag(3)
            }
            ProfilePickerView().tabItem { Label("Profiles", systemImage: "person.2.fill") }.tag(4)
        }
        .tabViewStyle(.tabBarOnly)
        .background(KyndynScreenBackground())
        .onChange(of: app.selectedPersonID) { _, _ in
            app.selectedTab = 0
            if !ProcessInfo.processInfo.arguments.contains("-ui-testing-parent-unlocked") {
                parentAccess.lock()
            }
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(AutomaticSyncCoordinator.self) private var automaticSync
    @Query private var people: [Person]
    @Query private var deviceSettings: [LocalDeviceSettings]
    @State private var isPullRefreshing = false

    private var activePerson: Person? {
        people.first { $0.id == app.selectedPersonID && $0.deletedAt == nil }
            ?? people.first {
                $0.id == deviceSettings.first?.selectedPersonID && $0.deletedAt == nil
            }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Personalization") {
                    if let activePerson {
                        NavigationLink {
                            ProfileCustomizationView(person: activePerson, section: .color)
                        } label: {
                            settingsRow(
                                title: "App color",
                                subtitle: "Use your profile color throughout kyndyn",
                                systemImage: "paintpalette.fill",
                                tint: Color(hex: activePerson.colorHex))
                        }
                        .accessibilityIdentifier("settings-app-color")
                        NavigationLink {
                            ProfileCustomizationView(person: activePerson, section: .companion)
                        } label: {
                            HStack(spacing: 12) {
                                settingsIconTile(tint: Color(hex: activePerson.colorHex)) {
                                    CompanionArt(id: activePerson.companionID).padding(3)
                                }
                                settingsRowText(
                                    title: "Companion",
                                    subtitle: "Choose who joins you on your day")
                            }
                        }
                        .accessibilityIdentifier("settings-companion")
                        NavigationLink {
                            ProfileCustomizationView(person: activePerson, section: .background)
                        } label: {
                            settingsRow(
                                title: "Background",
                                subtitle: "Choose the scene behind your companion",
                                systemImage: "photo.fill",
                                tint: Color(hex: activePerson.colorHex))
                        }
                        .accessibilityIdentifier("settings-background")
                    } else {
                        Text("Choose a person from Profiles to customize a profile.")
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink {
                        AppIconPickerView()
                    } label: {
                        settingsRow(
                            title: "App icon",
                            subtitle: "Choose how kyndyn looks on this device",
                            systemImage: "app.dashed",
                            tint: KyndynTheme.purple)
                    }
                    .accessibilityIdentifier("settings-app-icon")
                }
                Section("Your day") {
                    NavigationLink {
                        CalendarSettingsView()
                    } label: {
                        settingsRow(
                            title: "Calendar",
                            subtitle: "Show events from calendars you choose",
                            systemImage: "calendar",
                            tint: KyndynTheme.blue)
                    }
                    .accessibilityIdentifier("settings-calendar")
                    NavigationLink {
                        WeatherSettingsView()
                    } label: {
                        settingsRow(
                            title: "Weather",
                            subtitle: "Add local conditions to your day",
                            systemImage: "cloud.sun.fill",
                            tint: KyndynTheme.amber)
                    }
                    .accessibilityIdentifier("settings-weather")
                }
                Section("Help") {
                    NavigationLink {
                        SiriShortcutsHelpView()
                    } label: {
                        settingsRow(
                            title: "Siri & Shortcuts",
                            subtitle: "See available voice and shortcut actions",
                            systemImage: "waveform",
                            tint: KyndynTheme.pink)
                    }
                    .accessibilityIdentifier("settings-siri-shortcuts")
                    NavigationLink {
                        FamilySetupGuideView()
                    } label: {
                        settingsRow(
                            title: "Family setup guide",
                            subtitle: "Profiles, sharing, and private backups",
                            systemImage: "questionmark.circle.fill",
                            tint: KyndynTheme.green)
                    }
                }
                Section {
                    KyndynCallout(
                        kind: .information,
                        message: "Household management, family sync, reminders, backups, and security remain protected in Parent.",
                        title: "Looking for family controls?")
                }
            }
            .refreshable { await refreshFamilyData() }
            .refreshStatusPill(isRefreshing: isPullRefreshing)
            .scrollContentBackground(.hidden)
            .background(KyndynScreenBackground())
            .navigationTitle("Settings")
        }
    }

    private func refreshFamilyData() async {
        isPullRefreshing = true
        defer { isPullRefreshing = false }
        await Task.yield()
        async let minimumVisibleTime: Void = Task.sleep(for: .milliseconds(550))
        automaticSync.request(.manual)
        await automaticSync.waitUntilIdle()
        try? await minimumVisibleTime
    }

    private func settingsRow(
        title: String, subtitle: String, systemImage: String, tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            settingsIconTile(tint: tint) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
            }
            settingsRowText(title: title, subtitle: subtitle)
        }
    }

    private func settingsRowText(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func settingsIconTile<Content: View>(
        tint: Color, @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(width: 38, height: 38)
            .background(tint.opacity(0.11), in: RoundedRectangle(
                cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(tint.opacity(0.20), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

struct SiriShortcutsHelpView: View {
    var body: some View {
        List {
            Section("Try saying") {
                Label("“Show my quests in kyndyn”", systemImage: "checklist")
                Label("“Show family reward progress in kyndyn”",
                      systemImage: "gift.fill")
                Label("“Open a profile in kyndyn”",
                      systemImage: "person.crop.circle")
                Label("“Complete a quest in kyndyn”",
                      systemImage: "checkmark.circle.fill")
                Label("“Undo a quest in kyndyn”",
                      systemImage: "arrow.uturn.backward.circle.fill")
            }
            Section("Privacy") {
                KyndynCallout(kind: .privacy, message: "Device authentication protects profile names, quest details, and reward progress. Shortcut changes use the same offline history and family-sync queue as the app.")
                    .accessibilityIdentifier("siri-shortcuts-privacy")
            }
            Section {
                Text("Apple controls which phrases are recognized and when Siri or Shortcuts can run. Newer Apple Intelligence features vary by device, language, and OS version.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(KyndynScreenBackground())
        .navigationTitle("Siri & Shortcuts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CalendarSettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    @Query private var settings: [LocalDeviceSettings]
    @State private var permission: DevicePermissionState = .notRequested
    @State private var calendars: [DeviceCalendar] = []
    private let provider = EventKitCalendarProvider()

    var body: some View {
        List {
            Section {
                KyndynCallout(kind: .information, message: "Choose calendars to show alongside your day. kyndyn reads upcoming events but never creates or changes them.")
            }
            if permission == .allowed, let setting = settings.first {
                Section("Calendars") {
                    ForEach(calendars) { calendar in
                        Button {
                            if setting.selectedCalendarIdentifiers.contains(calendar.id) {
                                setting.selectedCalendarIdentifiers.removeAll { $0 == calendar.id }
                            } else {
                                setting.selectedCalendarIdentifiers.append(calendar.id)
                            }
                            setting.calendarIntegrationEnabled = !setting.selectedCalendarIdentifiers.isEmpty
                            try? context.save()
                        } label: {
                            HStack {
                                Circle().fill(Color(hex: calendar.colorHex)).frame(width: 12, height: 12)
                                Text(calendar.title).foregroundStyle(.primary)
                                Spacer()
                                if setting.selectedCalendarIdentifiers.contains(calendar.id) {
                                    Image(systemName: "checkmark").fontWeight(.semibold)
                                }
                            }
                        }
                    }
                }
                Section {
                    Button("Stop showing calendars", role: .destructive) {
                        setting.calendarIntegrationEnabled = false
                        setting.selectedCalendarIdentifiers = []
                        try? context.save()
                    }
                }
                if calendars.isEmpty {
                    Section {
                        KyndynCallout(kind: .information, message: "No calendars are available on this device yet. Add one in Calendar, then return here.")
                    }
                }
            } else {
                Section {
                    Button("Allow calendar access") {
                        Task {
                            _ = await provider.requestAccess()
                            reload()
                        }
                    }
                    if permission == .denied || permission == .restricted {
                        Text("Calendar access is off. You can change it in the iPhone or iPad Settings app.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Open device settings") { openAppSettings() }
                    }
                }
            }
            Section("Privacy") {
                KyndynCallout(kind: .privacy, message: "Calendar choices and event details stay on this device. kyndyn does not family-sync them or include them in backups.")
            }
        }
        .scrollContentBackground(.hidden).background(KyndynScreenBackground())
        .navigationTitle("Calendar").navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
    }

    private func reload() {
        permission = provider.permissionState()
        calendars = permission == .allowed ? provider.calendars() : []
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

struct WeatherSettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    @Query private var settings: [LocalDeviceSettings]
    @State private var isLoading = false
    @State private var message: String?

    var body: some View {
        List {
            Section {
                KyndynCallout(kind: .information, message: "Show local conditions alongside your day using Apple Weather. Location is requested only while kyndyn is open.")
            }
            Section {
                if let setting = settings.first {
                    Toggle("Show weather on Home", isOn: Binding(
                        get: { setting.weatherIntegrationEnabled },
                        set: { enabled in
                            setting.weatherIntegrationEnabled = enabled
                            if !enabled { clearCache(setting) }
                            try? context.save()
                            if enabled { Task { await load(setting) } }
                        }))
                    if setting.weatherIntegrationEnabled {
                        Button(isLoading ? "Updating…" : "Update weather now") {
                            Task { await load(setting) }
                        }.disabled(isLoading)
                    }
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                    Button("Open device settings") { openAppSettings() }
                }
            }
            Section("Privacy") {
                KyndynCallout(kind: .privacy, message: "kyndyn never saves precise coordinates. A short-lived weather summary and city or town name stay on this device and are excluded from family sync and backups.")
            }
        }
        .scrollContentBackground(.hidden).background(KyndynScreenBackground())
        .navigationTitle("Weather").navigationBarTitleDisplayMode(.inline)
    }

    @MainActor private func load(_ setting: LocalDeviceSettings) async {
        isLoading = true; message = nil
        defer { isLoading = false }
        do {
            let location = try await OneShotLocationProvider().currentLocation()
            let value = try await AppleWeatherProvider().weather(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude)
            setting.cachedWeatherTemperature = value.temperature
            setting.cachedWeatherHigh = value.high
            setting.cachedWeatherLow = value.low
            setting.cachedWeatherCondition = value.condition
            setting.cachedWeatherSymbolName = value.symbolName
            setting.cachedWeatherLocationName = value.locationName
            setting.cachedWeatherAt = value.fetchedAt
            try context.save()
            message = "Weather is ready on Home."
        } catch {
            message = "Weather isn’t available yet. Check location access and your connection, then try again."
        }
    }

    private func clearCache(_ setting: LocalDeviceSettings) {
        setting.cachedWeatherTemperature = nil; setting.cachedWeatherHigh = nil
        setting.cachedWeatherLow = nil; setting.cachedWeatherCondition = nil
        setting.cachedWeatherSymbolName = nil
        setting.cachedWeatherLocationName = nil; setting.cachedWeatherAt = nil
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
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
            }
            .background(KyndynScreenBackground())
            .navigationTitle("Protected")
        }
    }
}

struct DashboardView: View {
    private enum DayDetail: String, Identifiable {
        case weather, calendar
        var id: String { rawValue }
    }
    @Environment(AppModel.self) private var app
    @Environment(AutomaticSyncCoordinator.self) private var automaticSync
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var households: [Household]
    @Query private var people: [Person]
    @Query private var completions: [QuestCompletion]
    @Query private var goals: [RewardGoal]
    @Query private var deviceSettings: [LocalDeviceSettings]
    @Query private var quests: [Quest]
    @Query private var broadcasts: [FamilyBroadcast]
    @State private var showProgress = false
    @State private var unlockToPresent: String?
    @State private var greetingMessage = "Small steps count."
    @State private var calendarEvents: [DeviceCalendarEvent] = []
    @State private var weatherHourlyForecast: [DeviceWeatherHour] = []
    @State private var weatherForecast: [DeviceWeatherDay] = []
    @State private var presentedDayDetail: DayDetail?
    @State private var isLoadingWeather = false
    @State private var isPullRefreshing = false
    private var person: Person? { people.first { $0.id == app.selectedPersonID } }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let household = households.first {
                    VStack(spacing: 16) {
                        if let person {
                            ImmersiveProfileHeader(
                                personName: person.name,
                                message: greetingMessage,
                                backgroundID: person.backgroundID,
                                companionID: person.companionID,
                                accent: Color(hex: person.colorHex)
                            )
                            .frame(height: dynamicTypeSize.isAccessibilitySize
                                   ? 380
                                   : (horizontalSizeClass == .regular ? 350 : 300))
                            .accessibilityIdentifier("home-profile-scene")
                        }
                        dashboardModePicker
                            .padding(.horizontal)
                        if ProgressionEngine.isSchedulePaused(
                            on: .now, household: household),
                           let end = household.schedulePauseEndsAt {
                            KyndynCallout(
                                kind: .information,
                                message: "Scheduled quests and reminders resume after \(end.formatted(date: .abbreviated, time: .omitted)).",
                                title: "Family schedules are paused")
                            .padding(.horizontal)
                        }
                        dayContext
                            .padding(.horizontal)
                        if deviceSettings.first?.showsHouseholdDashboard == true {
                            broadcastNavigation
                                .padding(.horizontal)
                            householdDashboard(household)
                        } else if let person {
                            let progress = ProgressionEngine.progress(
                                personID: person.id, completions: completions,
                                now: .now,
                                timeZoneIdentifier: household.timeZoneIdentifier,
                                startingXPAdjustment: person.startingXPAdjustment,
                                schedulePauseStartsAt: household.schedulePauseStartsAt,
                                schedulePauseEndsAt: household.schedulePauseEndsAt)
                            VStack(spacing: 16) {
                                broadcastNavigation
                                progressSummary(
                                    progress, person: person, household: household,
                                    tint: Color(hex: person.colorHex))
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
                            .padding(.horizontal)
                            .frame(maxWidth: AdaptiveLayout.readableContentMaximum)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .ignoresSafeArea(edges: .top)
            .refreshable {
                isPullRefreshing = true
                defer { isPullRefreshing = false }
                await Task.yield()
                async let minimumVisibleTime: Void = Task.sleep(
                    for: .milliseconds(550))
                automaticSync.request(.manual)
                await automaticSync.waitUntilIdle()
                try? await minimumVisibleTime
                rotateGreeting()
            }
            .refreshStatusPill(
                isRefreshing: isPullRefreshing,
                topPadding: horizontalSizeClass == .regular ? 20 : 58)
            .background(KyndynScreenBackground())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showProgress) {
                if let person, let household = households.first {
                    ProgressDetailView(person: person, household: household)
                }
            }
            .sheet(item: $presentedDayDetail) { detail in
                switch detail {
                case .weather:
                    WeatherGlanceView(
                        setting: deviceSettings.first,
                        hourlyForecast: weatherHourlyForecast,
                        forecast: weatherForecast,
                        isLoading: isLoadingWeather)
                case .calendar:
                    CalendarGlanceView(events: calendarEvents)
                }
            }
            .alert(unlockTitle(unlockToPresent), isPresented: Binding(
                get: { unlockToPresent != nil },
                set: { if !$0 { acknowledgePresentedUnlock() } }
            )) {
                Button("Nice!") { acknowledgePresentedUnlock() }
            } message: {
                Text(unlockMessage(unlockToPresent))
            }
            .task(id: person?.pendingUnlockIDs.first) {
                unlockToPresent = person?.pendingUnlockIDs.first
            }
            .onAppear { rotateGreeting() }
            .task(id: deviceSettings.first?.calendarIntegrationEnabled) {
                refreshCalendarEvents()
            }
            .task(id: deviceSettings.first?.weatherIntegrationEnabled) {
                await refreshWeatherIfNeeded()
            }
        }
    }

    @ViewBuilder private var dayContext: some View {
        if let setting = deviceSettings.first,
           setting.calendarIntegrationEnabled || setting.weatherIntegrationEnabled {
            Grid(horizontalSpacing: 12) {
                GridRow(alignment: .top) {
                    if setting.weatherIntegrationEnabled {
                        Button {
                            presentedDayDetail = .weather
                            Task { await refreshWeatherDetails() }
                        } label: {
                            weatherSummary(setting)
                        }
                        .buttonStyle(.plain)
                    }
                    if setting.calendarIntegrationEnabled {
                        Button {
                            refreshCalendarEvents()
                            presentedDayDetail = .calendar
                        } label: {
                            calendarSummary
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: AdaptiveLayout.readableContentMaximum)
        }
    }

    private func weatherSummary(_ setting: LocalDeviceSettings) -> some View {
        let tint = weatherTint(for: setting.cachedWeatherSymbolName)
        return VStack(alignment: .leading, spacing: 6) {
            Label(setting.cachedWeatherCondition ?? "Local weather",
                  systemImage: setting.cachedWeatherSymbolName ?? "cloud.sun")
                .font(.headline)
                .foregroundStyle(tint)
            if let locationName = setting.cachedWeatherLocationName {
                Text(locationName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let temperature = setting.cachedWeatherTemperature {
                Text("\(Int(temperature.rounded()))°")
                    .font(.title.bold().monospacedDigit())
                if let high = setting.cachedWeatherHigh, let low = setting.cachedWeatherLow {
                    Text("H \(Int(high.rounded()))°  L \(Int(low.rounded()))°")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let fetchedAt = setting.cachedWeatherAt {
                    Text(WeatherCachePolicy.isFresh(fetchedAt)
                         ? "Updated recently" : "Last updated \(fetchedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            } else {
                Label("Tap to check weather", systemImage: "arrow.clockwise")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 90, maxHeight: .infinity, alignment: .topLeading)
        .kyndynCard(tint: tint)
    }

    private var calendarSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Coming up", systemImage: "calendar")
                .font(.headline)
            if let event = calendarEvents.first {
                Text(event.title).font(.subheadline.bold()).lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(hex: event.calendarColorHex))
                        .frame(width: 7, height: 7)
                    Text(event.calendarTitle).lineLimit(1)
                    Text("•")
                    Text(calendarTime(for: event)).lineLimit(1)
                }
                .font(.caption).foregroundStyle(.secondary)
                if calendarEvents.count > 1 {
                    Text("+\(calendarEvents.count - 1) more in the next 2 weeks")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            } else {
                Text("Nothing scheduled soon")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 90, maxHeight: .infinity, alignment: .topLeading)
        .kyndynCard(tint: calendarEvents.first.map {
            Color(hex: $0.calendarColorHex)
        } ?? .orange)
    }

    private func calendarTime(for event: DeviceCalendarEvent) -> String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(event.startDate) { day = "Today" }
        else if calendar.isDateInTomorrow(event.startDate) { day = "Tomorrow" }
        else { day = event.startDate.formatted(.dateTime.weekday(.abbreviated)) }
        return event.isAllDay
            ? "\(day), all day"
            : "\(day) at \(event.startDate.formatted(date: .omitted, time: .shortened))"
    }

    private func refreshCalendarEvents() {
        guard let setting = deviceSettings.first,
              setting.calendarIntegrationEnabled else {
            calendarEvents = []; return
        }
        let provider = EventKitCalendarProvider()
        guard provider.permissionState() == .allowed else {
            calendarEvents = []; return
        }
        calendarEvents = Array(provider.events(
            from: .now,
            through: Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now,
            calendarIDs: Set(setting.selectedCalendarIdentifiers)).prefix(20))
    }

    @MainActor private func refreshWeatherIfNeeded() async {
        guard let setting = deviceSettings.first,
              setting.weatherIntegrationEnabled, !isLoadingWeather else { return }
        if WeatherCachePolicy.isFresh(setting.cachedWeatherAt) { return }
        isLoadingWeather = true
        defer { isLoadingWeather = false }
        do {
            let location = try await OneShotLocationProvider().currentLocation()
            let snapshot = try await AppleWeatherProvider().weather(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude)
            setting.cachedWeatherTemperature = snapshot.temperature
            setting.cachedWeatherHigh = snapshot.high
            setting.cachedWeatherLow = snapshot.low
            setting.cachedWeatherCondition = snapshot.condition
            setting.cachedWeatherSymbolName = snapshot.symbolName
            setting.cachedWeatherLocationName = snapshot.locationName
            setting.cachedWeatherAt = snapshot.fetchedAt
            weatherHourlyForecast = snapshot.hourlyForecast
            weatherForecast = snapshot.dailyForecast
            try? context.save()
        } catch {
            // Cached weather remains visible. Permission guidance lives in Settings.
        }
    }

    @MainActor private func refreshWeatherDetails() async {
        guard let setting = deviceSettings.first,
              setting.weatherIntegrationEnabled, !isLoadingWeather else { return }
        isLoadingWeather = true
        defer { isLoadingWeather = false }
        do {
            let location = try await OneShotLocationProvider().currentLocation()
            let snapshot = try await AppleWeatherProvider().weather(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude)
            setting.cachedWeatherTemperature = snapshot.temperature
            setting.cachedWeatherHigh = snapshot.high
            setting.cachedWeatherLow = snapshot.low
            setting.cachedWeatherCondition = snapshot.condition
            setting.cachedWeatherSymbolName = snapshot.symbolName
            setting.cachedWeatherLocationName = snapshot.locationName
            setting.cachedWeatherAt = snapshot.fetchedAt
            weatherHourlyForecast = snapshot.hourlyForecast
            weatherForecast = snapshot.dailyForecast
            try? context.save()
        } catch {
            // Keep the cached glance visible when an update is unavailable.
        }
    }

    private var activeBroadcasts: [FamilyBroadcast] {
        broadcasts.filter {
            $0.deletedAt == nil && ($0.expiresAt == nil || $0.expiresAt! > .now)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    @ViewBuilder private var broadcastNavigation: some View {
        if let announcement = activeBroadcasts.first {
            NavigationLink {
                FamilyBroadcastListView()
            } label: {
                BroadcastCard(
                    broadcast: announcement,
                    additionalCount: max(0, activeBroadcasts.count - 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func unlockMessage(_ value: String?) -> String {
        guard let value else { return "A new item is ready in Settings." }
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return "A new item is ready in Settings." }
        if parts[0] == "badge",
           let badge = RecognitionEngine.badgeCatalog.first(where: {
               $0.id == parts[1]
           }) {
            let count = person.map {
                RecognitionEngine.normalizedBadges($0.earnedBadgeIDs).count
            } ?? 0
            if let milestone = RecognitionEngine.collectionMilestone(
                reachedWith: count) {
                return "\(badge.detail). You also unlocked the \(milestone.detail)."
            }
            return badge.detail
        }
        return "\(parts[1].capitalized) is now available as a \(parts[0]). You can choose it in Settings."
    }

    private func unlockTitle(_ value: String?) -> String {
        guard let value else { return "New collection item" }
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2, parts[0] == "badge",
           let badge = RecognitionEngine.badgeCatalog.first(where: {
               $0.id == parts[1]
           }) {
            return "Badge earned: \(badge.title)"
        }
        return "New collection item"
    }

    private func acknowledgePresentedUnlock() {
        guard let value = unlockToPresent, let person else { return }
        unlockToPresent = nil
        do { try app.acknowledgeUnlock(value, for: person, context: context) }
        catch { app.errorMessage = error.localizedDescription }
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
            householdHeading
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
        .padding(.horizontal)
        .frame(maxWidth: AdaptiveLayout.readableContentMaximum)
        .frame(maxWidth: .infinity)
    }

    private var householdHeading: some View {
        Text("Everyone’s day").font(.largeTitle.bold())
            .accessibilityAddTraits(.isHeader)
    }

    private func householdMemberSummary(
        _ member: Person, household: Household
    ) -> some View {
        let memberQuests = quests.compactMap { quest -> (Quest, QuestTemporalStatus)? in
            let status = ProgressionEngine.temporalStatus(
                for: quest, personID: member.id, completions: completions,
                now: .now, timeZoneIdentifier: household.timeZoneIdentifier,
                household: household)
            return status == .inactive ? nil : (quest, status)
        }
        let waiting = memberQuests.filter { $0.1 == .overdue || $0.1 == .today }
        let completed = memberQuests.filter { $0.1 == .completed }.count
        let progress = ProgressionEngine.progress(
            personID: member.id, completions: completions, now: .now,
            timeZoneIdentifier: household.timeZoneIdentifier,
            startingXPAdjustment: member.startingXPAdjustment,
            schedulePauseStartsAt: household.schedulePauseStartsAt,
            schedulePauseEndsAt: household.schedulePauseEndsAt)

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

    private func rotateGreeting() {
        let messages = [
            "Small steps count.",
            "You’ve got this.",
            "A little progress goes a long way.",
            "Ready for today’s adventure?",
            "One quest at a time.",
            "Your effort matters.",
            "Let’s make today count.",
            "Every win starts with one step.",
            "Good things grow from steady effort.",
            "There’s something great ahead."
        ]
        let choices = messages.filter { $0 != greetingMessage }
        greetingMessage = choices.randomElement() ?? messages[0]
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

    private func progressSummary(
        _ progress: PersonProgress, person: Person, household: Household,
        tint: Color
    ) -> some View {
        let badgeCount = RecognitionEngine.badges(
            progress: progress,
            familyRewardReached: rewardXP(household) >= rewardTarget(household),
            earnedBadgeIDs: person.earnedBadgeIDs).count
        return Button {
            showProgress = true
        } label: {
            VStack(spacing: 14) {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your progress")
                                .font(.title3.bold())
                            Text("Level \(progress.level) journey")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.title3.bold())
                            .foregroundStyle(tint)
                            .frame(width: 38, height: 38)
                            .background(tint.opacity(0.14), in: Circle())
                    }
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
                    ProgressStat(value: "\(badgeCount)", label: "Badges")
                }
                VStack(spacing: 6) {
                    ProgressView(
                        value: Double(progress.xp % 100), total: 100)
                        .tint(tint)
                    HStack {
                        Text("Level \(progress.level)")
                        Spacer()
                        Text("\(xpToNextLevel(progress)) XP to Level \(progress.level + 1)")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .kyndynCard(tint: tint, raised: true)
        .accessibilityIdentifier("home-progress-summary")
        .accessibilityHint("Shows progress details")
    }

    private func xpToNextLevel(_ progress: PersonProgress) -> Int {
        100 - (progress.xp % 100)
    }
}

private enum QuestBrowseFilter: String, CaseIterable, Identifiable {
    case waiting, completed, overdue, upcoming, all
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .waiting: "circle.dashed"
        case .completed: "checkmark.circle.fill"
        case .overdue: "exclamationmark.circle.fill"
        case .upcoming: "calendar"
        case .all: "line.3.horizontal.decrease.circle"
        }
    }
}

private struct WeatherGlanceView: View {
    private enum ForecastMode: String, CaseIterable, Identifiable {
        case hourly = "Hourly"
        case daily = "10-day"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    let setting: LocalDeviceSettings?
    let hourlyForecast: [DeviceWeatherHour]
    let forecast: [DeviceWeatherDay]
    let isLoading: Bool
    @State private var mode: ForecastMode = .hourly

    private var tint: Color {
        weatherTint(for: setting?.cachedWeatherSymbolName)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let temperature = setting?.cachedWeatherTemperature {
                        HStack(spacing: 16) {
                            Image(systemName: setting?.cachedWeatherSymbolName ?? "cloud.sun")
                                .font(.system(size: 42)).foregroundStyle(tint)
                            VStack(alignment: .leading, spacing: 3) {
                                if let locationName = setting?.cachedWeatherLocationName {
                                    Text(locationName)
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                }
                                Text("\(Int(temperature.rounded()))°")
                                    .font(.largeTitle.bold().monospacedDigit())
                                Text(setting?.cachedWeatherCondition ?? "Local weather")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .kyndynCard(tint: tint, raised: true)
                    }

                    Picker("Forecast", selection: $mode) {
                        ForEach(ForecastMode.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    if isLoading && hourlyForecast.isEmpty && forecast.isEmpty {
                        HStack { Spacer(); ProgressView("Updating forecast…"); Spacer() }
                            .padding(.vertical, 24)
                    } else if mode == .hourly, !hourlyForecast.isEmpty {
                        hourlyRows
                    } else if mode == .daily, !forecast.isEmpty {
                        dailyRows
                    } else {
                        KyndynCallout(kind: .information,
                                      message: "This forecast isn’t available right now. Your last weather update is still shown above.")
                    }
                }
                .padding()
            }
            .background(KyndynScreenBackground())
            .navigationTitle("Weather")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents(forecast.count > 4 ? [.medium, .large] : [.medium])
    }

    private var hourlyRows: some View {
        VStack(spacing: 0) {
            ForEach(hourlyForecast) { hour in
                HStack(spacing: 12) {
                    Text(hour.date.formatted(.dateTime.hour()))
                        .frame(width: 68, alignment: .leading)
                    Image(systemName: hour.symbolName)
                        .foregroundStyle(weatherTint(for: hour.symbolName))
                        .frame(width: 30)
                    if hour.precipitationChance >= 0.05 {
                        Label("\(Int((hour.precipitationChance * 100).rounded()))%",
                              systemImage: "drop.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    Spacer()
                    Text("\(Int(hour.temperature.rounded()))°")
                        .fontWeight(.semibold).monospacedDigit()
                }
                .padding(.vertical, 12)
                if hour.id != hourlyForecast.last?.id { Divider() }
            }
        }
        .kyndynCard(tint: tint)
    }

    private var dailyRows: some View {
        VStack(spacing: 0) {
            ForEach(forecast) { day in
                HStack(spacing: 12) {
                    Text(day.date.formatted(.dateTime.weekday(.wide)))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: day.symbolName)
                        .foregroundStyle(weatherTint(for: day.symbolName))
                        .frame(width: 28)
                    Text("\(Int(day.high.rounded()))°")
                        .fontWeight(.semibold).monospacedDigit()
                    Text("\(Int(day.low.rounded()))°")
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(.vertical, 12)
                if day.id != forecast.last?.id { Divider() }
            }
        }
        .kyndynCard(tint: tint)
    }
}

private func weatherTint(for symbolName: String?) -> Color {
    let symbol = symbolName?.lowercased() ?? ""
    if symbol.contains("thunder") || symbol.contains("bolt") { return .indigo }
    if symbol.contains("snow") || symbol.contains("sleet") { return .cyan }
    if symbol.contains("rain") || symbol.contains("drizzle") { return .blue }
    if symbol.contains("sun") { return .orange }
    if symbol.contains("moon") { return .indigo }
    if symbol.contains("cloud") || symbol.contains("fog") { return .gray }
    return .blue
}

private struct CalendarGlanceView: View {
    @Environment(\.dismiss) private var dismiss
    let events: [DeviceCalendarEvent]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if events.isEmpty {
                        KyndynCallout(kind: .information,
                                      message: "Nothing is scheduled in your selected calendars over the next two weeks.")
                    } else {
                        ForEach(events) { event in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(event.title).font(.headline)
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(hex: event.calendarColorHex))
                                        .frame(width: 9, height: 9)
                                    Text(event.calendarTitle)
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color(hex: event.calendarColorHex))
                                Label(eventTime(event), systemImage: "clock")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .kyndynCard(tint: Color(hex: event.calendarColorHex))
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(
                                "\(event.title), \(event.calendarTitle), \(eventTime(event))")
                        }
                    }
                }
                .padding()
            }
            .background(KyndynScreenBackground())
            .navigationTitle("Coming up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents(events.count > 3 ? [.medium, .large] : [.medium])
    }

    private func eventTime(_ event: DeviceCalendarEvent) -> String {
        if event.isAllDay {
            return event.startDate.formatted(.dateTime.weekday(.wide).month().day()) + ", all day"
        }
        return event.startDate.formatted(.dateTime.weekday(.wide).month().day().hour().minute())
    }
}

struct ProgressDetailView: View {
    let person: Person
    let household: Household
    @Environment(\.dismiss) private var dismiss
    @Query private var completions: [QuestCompletion]
    @Query private var quests: [Quest]
    @Query private var goals: [RewardGoal]

    private var activeEvents: [QuestCompletion] {
        completions.filter { $0.personID == person.id && $0.reversedAt == nil }
            .sorted { $0.completedAt > $1.completedAt }
    }
    private var progress: PersonProgress {
        ProgressionEngine.progress(
            personID: person.id, completions: completions, now: .now,
            timeZoneIdentifier: household.timeZoneIdentifier,
            startingXPAdjustment: person.startingXPAdjustment,
            schedulePauseStartsAt: household.schedulePauseStartsAt,
            schedulePauseEndsAt: household.schedulePauseEndsAt)
    }
    private var familyRewardReached: Bool {
        let goal = ProgressionEngine.currentRewardGoal(
            goals, householdID: household.id)
        return goal.map {
            ProgressionEngine.rewardXP(completions, goal: $0) >= $0.targetXP
        } ?? false
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
                Section("Badges") {
                    NavigationLink {
                        BadgeGalleryView(
                            person: person, household: household,
                            progress: progress,
                            familyRewardReached: familyRewardReached)
                    } label: {
                        let earned = RecognitionEngine.badges(
                            progress: progress,
                            familyRewardReached: familyRewardReached,
                            earnedBadgeIDs: person.earnedBadgeIDs)
                        Label(
                            "\(earned.count) of \(RecognitionEngine.badgeCatalog.count) earned",
                            systemImage: "medal.fill")
                    }
                    Text("Badges come only from quest activity and family milestones. Starting XP changes levels, not badges.")
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

struct BadgeGalleryView: View {
    let person: Person
    let household: Household
    let progress: PersonProgress
    let familyRewardReached: Bool

    private var badges: [BadgeProgress] {
        RecognitionEngine.badgeProgress(
            progress: progress, familyRewardReached: familyRewardReached,
            earnedBadgeIDs: person.earnedBadgeIDs)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(badges.filter(\.isEarned).count) of \(badges.count) earned")
                        .font(.title2.bold())
                    ProgressView(
                        value: Double(badges.filter(\.isEarned).count),
                        total: Double(badges.count))
                        .tint(Color(hex: person.colorHex))
                    Text("Each badge marks something you did in kyndyn. Keep going at your own pace.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .kyndynCard(tint: Color(hex: person.colorHex), raised: true)

                if !RecognitionEngine.badgeCollectionMilestones.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Badges unlock your collection", systemImage: "sparkles")
                            .font(.headline)
                        ForEach(RecognitionEngine.badgeCollectionMilestones) { milestone in
                            HStack(alignment: .firstTextBaseline) {
                                Image(systemName: badges.filter(\.isEarned).count >= milestone.badgeCount
                                      ? "checkmark.circle.fill" : "lock.circle")
                                    .foregroundStyle(Color(hex: person.colorHex))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(milestone.title).font(.subheadline.bold())
                                    Text(milestone.detail)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .kyndynCard(tint: Color(hex: person.colorHex))
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(badges) { item in
                        BadgeTile(item: item)
                    }
                }
            }
            .padding()
            .frame(maxWidth: AdaptiveLayout.readableContentMaximum)
            .frame(maxWidth: .infinity)
        }
        .background(KyndynScreenBackground())
        .navigationTitle("\(person.name)’s badges")
        .accessibilityIdentifier("badge-gallery")
    }
}

private struct BadgeTile: View {
    let item: BadgeProgress

    var body: some View {
        let tint = Color(hex: item.badge.colorHex)
        VStack(spacing: 10) {
            Image(systemName: item.isEarned ? item.badge.systemImage : "lock.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(item.isEarned ? tint : .secondary)
                .frame(width: 66, height: 66)
                .background(
                    item.isEarned ? tint.opacity(0.16) : Color.secondary.opacity(0.10),
                    in: Circle())
                .overlay(Circle().stroke(
                    item.isEarned ? tint.opacity(0.65) : Color.secondary.opacity(0.25),
                    lineWidth: 2))
            Text(item.badge.title)
                .font(.headline).multilineTextAlignment(.center).lineLimit(2)
            Text(item.badge.detail)
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).lineLimit(2)
            if !item.isEarned {
                ProgressView(value: item.fraction).tint(tint)
                Text(item.progressText)
                    .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            } else {
                Label("Earned", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold()).foregroundStyle(tint)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 245, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(
            cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(tint.opacity(item.isEarned ? 0.55 : 0.20)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(item.badge.title), \(item.isEarned ? "earned" : "locked"), \(item.badge.detail)")
        .accessibilityValue(item.isEarned ? "Earned" : item.progressText)
        .accessibilityIdentifier("badge-\(item.badge.id)")
    }
}

private enum ProfileCustomizationSection {
    case color
    case companion
    case background

    var title: String {
        switch self {
        case .color: "App color"
        case .companion: "Companion"
        case .background: "Background"
        }
    }
}

private struct ProfileCustomizationView: View {
    let person: Person
    let section: ProfileCustomizationSection
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var colorHex: String
    @State private var companionID: String
    @State private var backgroundID: String
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var companionColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12),
              count: horizontalSizeClass == .compact ? 3 : 4)
    }

    private var backgroundColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
    }

    init(person: Person, section: ProfileCustomizationSection) {
        self.person = person
        self.section = section
        _colorHex = State(initialValue: person.colorHex)
        _companionID = State(initialValue: person.companionID)
        _backgroundID = State(initialValue: person.backgroundID)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    ProfileScene(
                        backgroundID: backgroundID, companionID: companionID,
                        accent: Color(hex: colorHex))
                        .frame(height: horizontalSizeClass == .compact ? 150 : 210)
                        .accessibilityLabel("Preview for \(person.name)")
                    switch section {
                    case .color:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("App color").font(.headline)
                            Text("This color personalizes navigation, highlights, and your profile without changing anyone else’s view.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            ProfileColorSelector(selection: $colorHex)
                        }
                        .kyndynCard(tint: Color(hex: colorHex))
                    case .companion:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Companion").font(.headline)
                            LazyVGrid(columns: companionColumns, spacing: 12) {
                                ForEach(CollectionCatalog.companions) { choice in
                                    let earned = person.earnedCompanionIDs.contains(choice.id)
                                    Button {
                                        if earned { companionID = choice.id }
                                    } label: {
                                        VStack {
                                            CompanionArt(id: choice.id)
                                                .frame(width: 62, height: 62)
                                                .saturation(earned ? 1 : 0)
                                                .opacity(earned ? 1 : 0.35)
                                            Text(choice.name).font(.caption.bold())
                                            if companionID == choice.id {
                                                Label("Active", systemImage: "checkmark.circle.fill")
                                                    .font(.caption2)
                                            } else if !earned {
                                                VStack(spacing: 2) {
                                                    Label("Locked", systemImage: "lock.fill")
                                                    Text(choice.unlockHint).lineLimit(2)
                                                }
                                                .font(.caption2)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 116)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!earned)
                                    .accessibilityIdentifier("collection-companion-\(choice.id)")
                                    .kyndynCard(tint: companionID == choice.id
                                                ? Color(hex: colorHex) : .secondary)
                                }
                            }
                        }
                    case .background:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Background").font(.headline)
                            LazyVGrid(columns: backgroundColumns, spacing: 16) {
                                ForEach(CollectionCatalog.backgrounds) { background in
                                    let earned = person.earnedBackgroundIDs.contains(background.id)
                                    Button {
                                        if earned { backgroundID = background.id }
                                    } label: {
                                        VStack(spacing: 6) {
                                            ProfileScene(
                                                backgroundID: background.id,
                                                companionID: companionID,
                                                accent: Color(hex: colorHex))
                                                .frame(height: horizontalSizeClass == .compact ? 82 : 120)
                                                .saturation(earned ? 1 : 0)
                                                .opacity(earned ? 1 : 0.42)
                                            Text(background.name).font(.caption.bold())
                                            Text(earned ? (backgroundID == background.id ? "Active" : "Unlocked") : background.unlockHint)
                                                .font(.caption2).foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    .buttonStyle(.plain).disabled(!earned)
                                    .accessibilityIdentifier("collection-background-\(background.id)")
                                }
                            }
                        }
                        .kyndynCard(tint: Color(hex: colorHex))
                    }
                    Text("Parents still manage names, roles, and family permissions.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: horizontalSizeClass == .compact
                       ? 520 : AdaptiveLayout.readableContentMaximum)
                .frame(maxWidth: .infinity)
            }
            .background(KyndynScreenBackground())
            .navigationTitle(section.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
            person.backgroundID = person.earnedBackgroundIDs.contains(backgroundID)
                ? backgroundID : CollectionCatalog.defaultBackgroundID
            try context.save()
            try SyncQueue.enqueue(SyncSnapshot.person(person),
                                  operation: .createOrUpdate, context: context)
            dismiss()
        } catch {
            app.errorMessage = error.localizedDescription
        }
    }
}

private struct AppIconChoice: Identifiable {
    let id: String
    let title: String
    let alternateName: String?
    let previewAsset: String

    static let choices = [
        AppIconChoice(
            id: "original", title: "Original", alternateName: nil,
            previewAsset: "AppIconDefaultPreview"),
        AppIconChoice(
            id: "pastel", title: "Pastel", alternateName: "AppIconPastel",
            previewAsset: "AppIconPastelPreview"),
        AppIconChoice(
            id: "retro-game", title: "Retro Game", alternateName: "AppIconRetroGame",
            previewAsset: "AppIconRetroGamePreview"),
        AppIconChoice(
            id: "japandi", title: "Japandi", alternateName: "AppIconJapandi",
            previewAsset: "AppIconJapandiPreview"),
        AppIconChoice(
            id: "translucent-foil", title: "Prismatic", alternateName: "AppIconTranslucentFoil",
            previewAsset: "AppIconTranslucentFoilPreview"),
        AppIconChoice(
            id: "atomic-age", title: "Atomic Age", alternateName: "AppIconAtomicAge",
            previewAsset: "AppIconAtomicAgePreview"),
        AppIconChoice(
            id: "lcd", title: "LCD", alternateName: "AppIconLCD",
            previewAsset: "AppIconLCDPreview"),
        AppIconChoice(
            id: "outrun-2", title: "Cosmic Outrun", alternateName: "AppIconOutrun2",
            previewAsset: "AppIconOutrun2Preview"),
        AppIconChoice(
            id: "arcade", title: "Arcade", alternateName: "AppIconArcade",
            previewAsset: "AppIconArcadePreview"),
        AppIconChoice(
            id: "translucent", title: "Translucent", alternateName: "AppIconTranslucent",
            previewAsset: "AppIconTranslucentPreview"),
        AppIconChoice(
            id: "outrun", title: "Outrun", alternateName: "AppIconOutrun",
            previewAsset: "AppIconOutrunPreview"),
        AppIconChoice(
            id: "crt", title: "CRT", alternateName: "AppIconCRT",
            previewAsset: "AppIconCRTPreview")
    ]
}

struct AppIconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedName = UIApplication.shared.alternateIconName
    @State private var isChanging = false
    @State private var errorMessage: String?

    private var supportsIconChanges: Bool {
        UIApplication.shared.supportsAlternateIcons
    }

    private var unavailableMessage: String {
        if ProcessInfo.processInfo.isiOSAppOnMac {
            return "This Mac is running the iPad version of kyndyn, and macOS does not currently allow that app to change its icon. Your icon choices remain available on iPhone and iPad."
        }
        return "This device does not currently allow kyndyn to change its app icon. You can still use every other personalization option."
    }

    private let columns = [
        GridItem(.adaptive(minimum: 96, maximum: 112), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "apps.iphone")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(KyndynTheme.purple)
                            .frame(width: 22)
                        Text("Choose the icon used on this device. Everyone else keeps their own selection.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .kyndynCard(tint: KyndynTheme.purple)

                    if !supportsIconChanges {
                        KyndynCallout(
                            kind: .information,
                            message: unavailableMessage,
                            title: "Icon changes unavailable here")
                            .accessibilityIdentifier("app-icon-unavailable")
                    }

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(AppIconChoice.choices) { choice in
                            AppIconChoiceButton(
                                choice: choice,
                                isSelected: selectedName == choice.alternateName,
                                isDisabled: isChanging || !supportsIconChanges
                            ) {
                                change(to: choice.alternateName)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(KyndynScreenBackground())
            .navigationTitle("App icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Couldn’t change the app icon", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private func change(to alternateName: String?) {
        guard supportsIconChanges else {
            errorMessage = unavailableMessage
            return
        }
        guard selectedName != alternateName else { return }
        isChanging = true
        UIApplication.shared.setAlternateIconName(alternateName) { error in
            Task { @MainActor in
                isChanging = false
                if let error {
                    errorMessage = error.localizedDescription
                } else {
                    selectedName = UIApplication.shared.alternateIconName
                }
            }
        }
    }
}

private struct AppIconChoiceButton: View {
    let choice: AppIconChoice
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(choice.previewAsset)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(
                        cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.body)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(5)
                        }
                    }
                Text(choice.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .padding(.horizontal, 6)
            .background(
                isSelected ? Color.accentColor.opacity(0.11) : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.07),
                        lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityIdentifier("app-icon-\(choice.id)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
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
    @State private var isPullRefreshing = false

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
                        timeZoneIdentifier: household.timeZoneIdentifier,
                        household: household)
                }
                status = aggregateStatus(values)
            } else if let personID = selectedPersonID {
                status = ProgressionEngine.temporalStatus(
                    for: quest, personID: personID, completions: completions,
                    now: .now, timeZoneIdentifier: household.timeZoneIdentifier,
                    household: household)
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
                            isPullRefreshing = true
                            defer { isPullRefreshing = false }
                            await Task.yield()
                            async let minimumVisibleTime: Void = Task.sleep(
                                for: .milliseconds(550))
                            automaticSync.request(.manual)
                            await automaticSync.waitUntilIdle()
                            try? await minimumVisibleTime
                        }
                        .refreshStatusPill(isRefreshing: isPullRefreshing)
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
                            minimum: dynamicTypeSize.isAccessibilitySize ? 540 : 340,
                            maximum: 900
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
        VStack(alignment: .leading, spacing: 12) {
            Picker("Whose quests", selection: $browseEveryone) {
                Text("My quests").tag(false)
                Text("Everyone").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 12) {
                questScopeLabel
                    .frame(maxWidth: .infinity, alignment: .leading)
                statusFilterMenu
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(minHeight: 36)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(
            cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(Color.primary.opacity(0.08)))
    }

    private var questScopeLabel: some View {
        Label(
            browseEveryone
                ? "Everyone"
                : (people.first { $0.id == selectedPersonID }?.name
                   ?? "Selected profile"),
            systemImage: browseEveryone ? "person.2.fill" : "person.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var statusFilterMenu: some View {
        Menu {
            ForEach(QuestBrowseFilter.allCases) { filter in
                Button {
                    browseFilter = filter
                } label: {
                    Label(
                        "\(filter.title) (\(count(for: filter)))",
                        systemImage: browseFilter == filter
                            ? "checkmark" : filter.systemImage)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: browseFilter.systemImage)
                Text(browseFilter.title)
                Text("\(count(for: browseFilter))")
                    .font(.caption.bold().monospacedDigit())
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.secondary.opacity(0.14), in: Capsule())
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 32)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .accessibilityLabel("Quest status filter")
        .accessibilityValue("\(browseFilter.title), \(count(for: browseFilter)) quests")
        .accessibilityIdentifier("quest-status-filter")
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

struct FamilySetupGuideView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query private var households: [Household]
    @Query private var people: [Person]
    @Query private var cloudStates: [HouseholdCloudState]
    let isFirstRun: Bool

    init(isFirstRun: Bool = false) {
        self.isFirstRun = isFirstRun
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Your family is ready", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("Use this checklist now or return to it from the Parent area at any time.")
                        .foregroundStyle(.secondary)
                }
                Section("1. Add family profiles") {
                    guideRow(done: activePeople.count > 1,
                             title: activePeople.count > 1 ? "Family profiles added" : "Add each person",
                             detail: "A profile represents someone inside this household. It does not invite another Apple device.")
                }
                Section("2. Connect other devices") {
                    guideRow(done: hasCloudSync,
                             title: hasCloudSync ? cloudTitle : "Enable family sync",
                             detail: "In Parent › Family sync, enable iCloud sharing, then use Invite or manage family to send the Apple invitation.")
                    KyndynCallout(kind: .information, message: "On the invited device, open the invitation and confirm Family sync says “Shared with you” and “Up to date.” Apple may delay background delivery, so kyndyn also catches up when opened.")
                }
                Section("3. Save a private backup") {
                    guideRow(done: false,
                             title: "Export after setup",
                             detail: "Use Parent › Backup and migration, save the JSON file privately in Files, and export a fresh copy after major changes.")
                    KyndynCallout(kind: .caution, message: "A backup is separate from iCloud recovery. Restore and import require an empty installation so existing family data is never replaced silently.")
                }
                if isFirstRun {
                    Section {
                        Button("Open Parent setup", systemImage: "lock.shield") {
                            app.selectedTab = 2
                            dismiss()
                        }
                        Button("Finish for now") { dismiss() }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KyndynScreenBackground())
            .navigationTitle("Family setup guide")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("family-setup-guide")
            .toolbar {
                if isFirstRun {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    private var activePeople: [Person] {
        guard let householdID = households.first?.id else { return [] }
        return people.filter { $0.householdID == householdID && $0.deletedAt == nil }
    }

    private var cloudState: HouseholdCloudState? {
        guard let householdID = households.first?.id else { return nil }
        return cloudStates.first { $0.householdID == householdID }
    }

    private var hasCloudSync: Bool {
        cloudState?.mode == .owner || cloudState?.mode == .participant
    }

    private var cloudTitle: String {
        cloudState?.mode == .participant ? "Shared with you" : "Hosted by you"
    }

    private func guideRow(done: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct BroadcastCard: View {
    let broadcast: FamilyBroadcast
    let additionalCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("Family announcement", systemImage: "megaphone.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KyndynTheme.purple)
                Spacer()
                if additionalCount > 0 {
                    Text("+\(additionalCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Text(broadcast.title).font(.headline)
            Text(broadcast.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            if let expiresAt = broadcast.expiresAt {
                Text("Available until \(expiresAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .kyndynCard(tint: KyndynTheme.purple)
        .accessibilityIdentifier("home-family-announcement")
    }
}

struct FamilyBroadcastListView: View {
    @Query private var broadcasts: [FamilyBroadcast]
    private var active: [FamilyBroadcast] {
        broadcasts.filter {
            $0.deletedAt == nil && ($0.expiresAt == nil || $0.expiresAt! > .now)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List {
            if active.isEmpty {
                ContentUnavailableView(
                    "No announcements", systemImage: "megaphone",
                    description: Text("Family updates will appear here."))
            } else {
                ForEach(active) { broadcast in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(broadcast.title).font(.headline)
                        Text(broadcast.message)
                        Text(broadcast.createdAt.formatted(
                            date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(KyndynScreenBackground())
        .navigationTitle("Announcements")
    }
}

struct FamilyBroadcastManagementView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var households: [Household]
    @Query private var broadcasts: [FamilyBroadcast]
    @Query private var cloudStates: [HouseholdCloudState]
    @State private var showNew = false

    private var canPublish: Bool {
        cloudStates.first?.mode != .participant
    }
    private var ordered: [FamilyBroadcast] {
        broadcasts.filter { $0.deletedAt == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List {
            if !canPublish {
                Section {
                    Label("Only the household owner can publish announcements in this version.",
                          systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if ordered.isEmpty {
                ContentUnavailableView(
                    "No announcements", systemImage: "megaphone",
                    description: Text("Publish a short update for the family."))
            } else {
                ForEach(ordered) { broadcast in
                    NavigationLink {
                        FamilyBroadcastEditorView(broadcast: broadcast)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(broadcast.title).font(.headline)
                            Text(broadcast.message).lineLimit(2)
                                .foregroundStyle(.secondary)
                            Text(status(broadcast))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!canPublish)
                    .swipeActions {
                        if canPublish {
                            Button("Archive", role: .destructive) {
                                do {
                                    try app.archiveBroadcast(
                                        broadcast, context: context)
                                } catch {
                                    app.errorMessage = error.localizedDescription
                                }
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(KyndynScreenBackground())
        .navigationTitle("Announcements")
        .toolbar {
            if canPublish {
                Button("New announcement", systemImage: "plus") {
                    showNew = true
                }
                .accessibilityIdentifier("new-family-announcement")
            }
        }
        .sheet(isPresented: $showNew) {
            NavigationStack {
                FamilyBroadcastEditorView(broadcast: nil)
            }
        }
    }

    private func status(_ broadcast: FamilyBroadcast) -> String {
        guard let expiresAt = broadcast.expiresAt else { return "No expiration" }
        return expiresAt > .now
            ? "Expires \(expiresAt.formatted(date: .abbreviated, time: .shortened))"
            : "Expired"
    }
}

struct FamilyBroadcastEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var households: [Household]
    let broadcast: FamilyBroadcast?
    @State private var draft: FamilyBroadcastDraft
    @State private var hasExpiration: Bool
    @State private var errorMessage: String?

    init(broadcast: FamilyBroadcast?) {
        self.broadcast = broadcast
        _draft = State(initialValue: FamilyBroadcastDraft(
            title: broadcast?.title ?? "Family update",
            message: broadcast?.message ?? "",
            expiresAt: broadcast?.expiresAt ?? Calendar.current.date(
                byAdding: .day, value: 1, to: .now)))
        _hasExpiration = State(initialValue: broadcast?.expiresAt != nil || broadcast == nil)
    }

    var body: some View {
        Form {
            Section("Announcement") {
                TextField("Title", text: $draft.title)
                    .textInputAutocapitalization(.sentences)
                TextField("Message", text: $draft.message, axis: .vertical)
                    .lineLimit(4...8)
                Text("\(draft.message.count) / 500")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Availability") {
                Toggle("Automatically expire", isOn: $hasExpiration)
                if hasExpiration {
                    DatePicker(
                        "Expires", selection: Binding(
                            get: { draft.expiresAt ?? .now.addingTimeInterval(86_400) },
                            set: { draft.expiresAt = $0 }),
                        in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                }
                Text("Expired announcements leave the family Home screen but remain available to the owner until archived.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(broadcast == nil ? "New announcement" : "Edit announcement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if broadcast == nil { Button("Cancel") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Publish") { save() }
                    .accessibilityIdentifier("publish-family-announcement")
            }
        }
        .alert("Couldn’t publish", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK") {} } message: { Text(errorMessage ?? "Try again.") }
    }

    private func save() {
        guard let household = households.first else { return }
        draft.expiresAt = hasExpiration ? draft.expiresAt : nil
        do {
            try app.saveBroadcast(
                broadcast, draft: draft, household: household,
                context: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ParentAreaView: View {
    @EnvironmentObject private var access: ParentAccessController
    @Environment(AutomaticSyncCoordinator.self) private var automaticSync
    @Query private var households: [Household]
    @Query private var people: [Person]
    @Query private var quests: [Quest]
    @Query private var completions: [QuestCompletion]
    @Query private var goals: [RewardGoal]
    @Query private var cloudStates: [HouseholdCloudState]
    @State private var isPullRefreshing = false
    var body: some View {
        NavigationStack {
            List {
                if households.first?.isSample == true {
                    Section {
                        KyndynCallout(
                            kind: .information,
                            message: "This household contains fictional practice data and stays separate from personal setup.",
                            title: "Sample family")
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
                    Section("This week") {
                        NavigationLink {
                            FamilyInsightsView()
                        } label: {
                            weeklyPreview(household)
                        }
                        .accessibilityIdentifier("parent-weekly-insights")
                    }
                    Section("Quick actions") {
                        NavigationLink { QuestEditorView(quest: nil) } label: {
                            parentRow("Create a quest", "Add a task and choose who it belongs to", "plus.circle.fill", .blue)
                        }
                        NavigationLink { PersonEditorView(person: nil) } label: {
                            parentRow("Add a person", "Create another family profile", "person.badge.plus", .green)
                        }
                        NavigationLink { FamilyRewardSettingsView() } label: {
                            parentRow("Update family reward", "Change the shared goal and XP target", "gift.fill", KyndynTheme.pink)
                        }
                        NavigationLink { FamilyBroadcastManagementView() } label: {
                            parentRow("Share an announcement", "Post an update for everyone", "megaphone.fill", KyndynTheme.amber)
                        }
                        NavigationLink { SchedulePauseView() } label: {
                            parentRow("Pause schedules", "Take a break without missed quests", "pause.circle.fill", KyndynTheme.green)
                        }
                        NavigationLink { CloudSyncSettingsView() } label: {
                            parentRow(syncSummary, "Review sharing and synchronization", "icloud.fill", KyndynTheme.purple)
                        }
                    }
                }
                Section("Manage family") {
                    NavigationLink { FamilySetupGuideView() } label: {
                        parentRow("Family setup guide", "Profiles, sharing, and private backups", "questionmark.circle.fill", KyndynTheme.green)
                    }
                    NavigationLink { PeopleManagementView() } label: {
                        parentRow("People", "Names, roles, colors, and collections", "person.2.fill", .blue)
                    }
                    NavigationLink { QuestManagementView() } label: {
                        parentRow("Quests", "Create, edit, archive, and restore", "checklist", KyndynTheme.purple)
                    }
                    NavigationLink { QuestPlanningView() } label: {
                        parentRow("Quest planning", "Templates and two-week schedule overview", "calendar.badge.clock", KyndynTheme.amber)
                    }
                    NavigationLink { FamilyRewardSettingsView() } label: {
                        parentRow("Family reward", "Shared progress, goals, and resets", "gift.fill", KyndynTheme.pink)
                    }
                    NavigationLink { FamilyBroadcastManagementView() } label: {
                        parentRow("Announcements", "Current and archived family updates", "megaphone.fill", .orange)
                    }
                    NavigationLink { FamilyInsightsView() } label: {
                        parentRow("Insights", "Weekly family and individual progress", "chart.xyaxis.line", KyndynTheme.green)
                    }
                }
                Section("Device and privacy") {
                    NavigationLink { CloudSyncSettingsView() } label: {
                        parentRow("Family sync", "iCloud sharing and sync status", "icloud.fill", KyndynTheme.purple)
                    }
                    NavigationLink { NotificationSettingsView() } label: {
                        parentRow("Reminders", "Timing, quiet hours, and lock-screen privacy", "bell.fill", .blue)
                    }
                    NavigationLink { HouseholdDataProtectionView() } label: {
                        parentRow("Data and privacy", "Backups, recovery, and local data controls", "hand.raised.fill", KyndynTheme.green)
                    }
                    NavigationLink { ParentSecurityView() } label: {
                        parentRow("Parent security", "Face ID, device passcode, and fallback PIN", "lock.shield.fill", KyndynTheme.pink)
                    }
                }
                Section {
                    Button { access.lock() } label: {
                        parentRow("Lock Parent area", "Require authentication for parent tools", "lock.fill", .red)
                    }
                }
                Section("About") {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .refreshable { await refreshFamilyData() }
            .refreshStatusPill(isRefreshing: isPullRefreshing)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: AdaptiveLayout.managementContentMaximum)
            .frame(maxWidth: .infinity)
            .background(KyndynScreenBackground())
            .navigationTitle("Parent")
        }
    }

    private func refreshFamilyData() async {
        isPullRefreshing = true
        defer { isPullRefreshing = false }
        await Task.yield()
        async let minimumVisibleTime: Void = Task.sleep(for: .milliseconds(550))
        automaticSync.request(.manual)
        await automaticSync.waitUntilIdle()
        try? await minimumVisibleTime
    }

    private func parentRow(
        _ title: String, _ subtitle: String, _ systemImage: String, _ tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.11), in: RoundedRectangle(
                    cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(tint.opacity(0.20), lineWidth: 1)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    private func statuses(_ household: Household) -> [QuestTemporalStatus] {
        quests.filter { $0.deletedAt == nil }.flatMap { quest in
            quest.participantIDs.compactMap { personID in
                ProgressionEngine.temporalStatus(
                    for: quest, personID: personID, completions: completions,
                    now: .now, timeZoneIdentifier: household.timeZoneIdentifier,
                    household: household)
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
    private func weeklyPreview(_ household: Household) -> some View {
        let insight = InsightsEngine.week(
            containing: .now, now: .now, household: household,
            people: people, quests: quests, completions: completions)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Weekly insights", systemImage: "chart.bar.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(insight.xp) XP")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(KyndynTheme.green)
            }
            HStack(spacing: 16) {
                Label("\(insight.completed) done", systemImage: "checkmark.circle.fill")
                Label("\(insight.notCompleted) not completed", systemImage: "minus.circle.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("See daily activity and individual trends")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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

struct FamilyInsightsView: View {
    @Query private var households: [Household]
    @Query private var people: [Person]
    @Query private var quests: [Quest]
    @Query private var completions: [QuestCompletion]
    @State private var weekOffset = 0

    private var household: Household? { households.first }
    private var selectedDate: Date {
        let zone = household?.timeZoneIdentifier ?? TimeZone.current.identifier
        return ProgressionEngine.calendar(timeZoneIdentifier: zone)
            .date(byAdding: .weekOfYear, value: weekOffset, to: .now) ?? .now
    }
    private var insight: WeeklyInsight? {
        household.map {
            InsightsEngine.week(
                containing: selectedDate, now: .now, household: $0,
                people: people, quests: quests, completions: completions)
        }
    }

    var body: some View {
        ScrollView {
            if let household, let insight {
                VStack(alignment: .leading, spacing: 20) {
                    weekPicker(insight)
                    familyTotals(insight)
                    dailyActivity(insight)
                    peopleSection(insight, household: household)
                    observations(insight)
                }
                .padding()
                .frame(maxWidth: AdaptiveLayout.managementContentMaximum)
                .frame(maxWidth: .infinity)
            } else {
                ContentUnavailableView("Insights unavailable", systemImage: "chart.bar")
            }
        }
        .background(KyndynScreenBackground())
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func weekPicker(_ insight: WeeklyInsight) -> some View {
        HStack {
            Button("Previous week", systemImage: "chevron.left") {
                weekOffset -= 1
            }.labelStyle(.iconOnly)
            Spacer()
            VStack(spacing: 2) {
                Text(weekOffset == 0 ? "This week" : weekOffset == -1 ? "Last week" : "Weekly summary")
                    .font(.headline)
                Text("\(insight.start.formatted(date: .abbreviated, time: .omitted)) – \(insight.end.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Next week", systemImage: "chevron.right") {
                weekOffset += 1
            }.labelStyle(.iconOnly).disabled(weekOffset >= 0)
        }
        .kyndynCard(tint: KyndynTheme.green)
    }

    private func familyTotals(_ insight: WeeklyInsight) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Family overview", systemImage: "person.3.fill").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 10) {
                InsightMetric(value: insight.completed, label: "Completed", tint: .green)
                InsightMetric(value: insight.notCompleted, label: "Not completed", tint: .orange)
                InsightMetric(value: insight.waiting, label: "Waiting", tint: .blue)
                InsightMetric(value: insight.xp, label: "XP earned", tint: KyndynTheme.purple)
            }
            if insight.concluded > 0 {
                Text("\(insight.completionRate)% of concluded scheduled quests were completed.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.kyndynCard(tint: KyndynTheme.green)
    }

    private func dailyActivity(_ insight: WeeklyInsight) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Daily activity", systemImage: "chart.bar.xaxis").font(.headline)
            let peak = max(1, insight.days.map(\.completed).max() ?? 1)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(insight.days) { day in
                    VStack(spacing: 6) {
                        Text("\(day.completed)").font(.caption2.monospacedDigit())
                        RoundedRectangle(cornerRadius: 5)
                            .fill(KyndynTheme.green.gradient)
                            .frame(height: max(5, CGFloat(day.completed) / CGFloat(peak) * 78))
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity)
                }
            }.frame(height: 118, alignment: .bottom)
            Text("Bars show completed quest occurrences. Today’s unfinished quests remain waiting until the day ends.")
                .font(.footnote).foregroundStyle(.secondary)
        }.kyndynCard(tint: KyndynTheme.green)
    }

    private func peopleSection(_ insight: WeeklyInsight, household: Household) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Individual progress").font(.title3.bold())
            ForEach(insight.people) { personInsight in
                if let person = people.first(where: { $0.id == personInsight.personID }) {
                    NavigationLink {
                        PersonInsightsView(person: person, household: household)
                    } label: {
                        HStack(spacing: 12) {
                            CompanionArt(id: person.companionID).frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(person.name).font(.headline).foregroundStyle(.primary)
                                Text("\(personInsight.completed) completed · \(personInsight.xp) XP · Level \(personInsight.level)")
                                    .font(.caption).foregroundStyle(.secondary)
                                if personInsight.concluded > 0 {
                                    Text("\(personInsight.completionRate)% of concluded quests")
                                        .font(.caption2).foregroundStyle(Color(hex: person.colorHex))
                                }
                            }
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }.kyndynCard(tint: Color(hex: person.colorHex))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func observations(_ insight: WeeklyInsight) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Worth a look", systemImage: "eye.fill").font(.headline)
            ForEach(insight.observations, id: \.self) { value in
                Label(value, systemImage: "sparkle").font(.subheadline)
            }
            Text("These are factual summaries of family activity—not ratings or comparisons between people.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kyndynCard(tint: KyndynTheme.amber)
    }
}

struct PersonInsightsView: View {
    let person: Person
    let household: Household
    @Query private var people: [Person]
    @Query private var quests: [Quest]
    @Query private var completions: [QuestCompletion]

    private var weeks: [WeeklyInsight] {
        InsightsEngine.recentWeeks(
            count: 4, now: .now, household: household, people: people,
            quests: quests, completions: completions)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    CompanionArt(id: person.companionID).frame(width: 64, height: 64)
                    VStack(alignment: .leading) {
                        Text(person.name).font(.title2.bold())
                        Text("Four-week progress").foregroundStyle(.secondary)
                    }
                }.kyndynCard(tint: Color(hex: person.colorHex), raised: true)
                VStack(alignment: .leading, spacing: 14) {
                    Label("Weekly trend", systemImage: "chart.line.uptrend.xyaxis").font(.headline)
                    ForEach(weeks) { week in
                        if let value = week.people.first(where: { $0.personID == person.id }) {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(week.start.formatted(.dateTime.month(.abbreviated).day()))
                                    Spacer()
                                    Text("\(value.completed) completed · \(value.xp) XP")
                                        .monospacedDigit()
                                }.font(.subheadline)
                                ProgressView(value: Double(value.completionRate), total: 100)
                                    .tint(Color(hex: person.colorHex))
                                Text(value.concluded == 0 ? "No concluded scheduled quests" : "\(value.completionRate)% of concluded quests")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.kyndynCard(tint: Color(hex: person.colorHex))
                if let latest = weeks.last?.people.first(where: { $0.personID == person.id }) {
                    HStack(spacing: 10) {
                        InsightMetric(value: latest.currentStreak, label: "Day streak", tint: .orange)
                        InsightMetric(value: latest.level, label: "Current level", tint: Color(hex: person.colorHex))
                    }
                }
                KyndynCallout(kind: .information, message: "Progress compares this person only with their own activity. Starting XP affects total level but is never reported as XP earned during a week.")
            }.padding().frame(maxWidth: AdaptiveLayout.managementContentMaximum).frame(maxWidth: .infinity)
        }.background(KyndynScreenBackground()).navigationTitle(person.name)
    }
}

private struct InsightMetric: View {
    let value: Int
    let label: String
    let tint: Color
    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, minHeight: 68)
            .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
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

struct SchedulePauseView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var households: [Household]
    @State private var isEnabled = false
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var statusMessage: String?

    private var household: Household? { households.first }

    var body: some View {
        Form {
            Section {
                KyndynCallout(
                    kind: .information,
                    message: "Scheduled quests won’t become waiting or overdue, reminders stop, and paused days won’t count as missed. Existing XP and history stay exactly as they are.",
                    title: "Take a break without losing progress")
            }
            Section("Schedule") {
                Toggle("Pause family schedules", isOn: $isEnabled)
                if isEnabled {
                    DatePicker("Starts", selection: $startDate,
                               displayedComponents: .date)
                    DatePicker("Ends", selection: $endDate, in: startDate...,
                               displayedComponents: .date)
                }
            }
            .onChange(of: startDate) { _, value in
                if endDate < value { endDate = value }
            }
            Section {
                Button("Save schedule pause", systemImage: "pause.circle.fill") {
                    save()
                }
                if household?.schedulePauseStartsAt != nil {
                    Button("Resume schedules now", systemImage: "play.circle.fill",
                           role: .destructive) { clear() }
                }
            }
            if let statusMessage {
                Section {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("Schedule pause")
        .task { load() }
        .errorAlert(app: app)
    }

    private func load() {
        guard let household else { return }
        isEnabled = household.schedulePauseStartsAt != nil
        startDate = household.schedulePauseStartsAt ?? .now
        endDate = household.schedulePauseEndsAt
            ?? Calendar.current.date(byAdding: .day, value: 6, to: .now) ?? .now
    }

    private func save() {
        guard let household else { return }
        do {
            try app.updateSchedulePause(
                household: household, start: isEnabled ? startDate : nil,
                end: isEnabled ? endDate : nil, context: context)
            statusMessage = isEnabled
                ? "Schedules resume automatically after the selected end date."
                : "Family schedules are active."
            load()
        } catch { app.errorMessage = error.localizedDescription }
    }

    private func clear() {
        guard let household else { return }
        do {
            try app.updateSchedulePause(
                household: household, start: nil, end: nil, context: context)
            statusMessage = "Family schedules resumed."
            load()
        } catch { app.errorMessage = error.localizedDescription }
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
    @Query private var broadcasts: [FamilyBroadcast]
    @Query private var settings: [HouseholdSettings]
    @Query private var cloudStates: [HouseholdCloudState]
    @State private var document: TransferDocument?
    @State private var exporting = false
    @State private var confirmSampleRemoval = false
    @State private var showingRemoval = false
    @State private var removalConfirmation = ""
    @State private var verification: HouseholdBackupVerification?
    @State private var safetyReport: HouseholdSafetyReport?
    @AppStorage("kyndyn.lastSuccessfulBackupExport")
    private var lastBackupExportTimestamp = 0.0
    @State private var recoveryReceipt: CloudRecoveryReceipt?

    var body: some View {
        List {
            Section("Release safety check") {
                if let safetyReport {
                    LabeledContent("Household", value: safetyReport.summary)
                    LabeledContent("Active profiles",
                                   value: "\(safetyReport.activeProfiles)")
                    LabeledContent("Active quests",
                                   value: "\(safetyReport.activeQuests)")
                    LabeledContent("Waiting to sync",
                                   value: "\(safetyReport.pendingChanges)")
                    LabeledContent("Conflicts needing review",
                                   value: "\(safetyReport.unresolvedConflicts)")
                    ForEach(safetyReport.notes, id: \.self) { note in
                        Label(note, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                    Text("Checked \(safetyReport.checkedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Check local relationships, backup freshness, and family-sync recovery signals without showing names, quest text, or record identifiers.")
                        .foregroundStyle(.secondary)
                }
                Button("Run safety check", systemImage: "checkmark.shield") {
                    runSafetyCheck()
                }
                .accessibilityIdentifier("run-household-safety-check")
            }
            Section("Protection status") {
                if lastBackupExportTimestamp > 0 {
                    LabeledContent("Last private backup") {
                        Text(Date(timeIntervalSince1970: lastBackupExportTimestamp),
                             format: .dateTime.month().day().year().hour().minute())
                    }
                } else {
                    LabeledContent("Last private backup", value: "Not exported on this device")
                }
                if let receipt = recoveryReceipt {
                    LabeledContent("Last iCloud recovery") {
                        Text(receipt.recoveredAt,
                             format: .dateTime.month().day().year().hour().minute())
                    }
                    Text("Verified \(receipt.people) profiles, \(receipt.quests) quests, and \(receipt.completions) completion records.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let verification {
                    LabeledContent("Prepared backup", value: "Verified")
                    Text("Includes \(verification.people) profiles, \(verification.quests) quests, \(verification.completions) completion records, and \(verification.broadcasts) announcements.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("backup-verification-summary")
                }
            }
            Section("Household backup") {
                Button("Export household backup",
                       systemImage: "square.and.arrow.up") {
                    prepareExport()
                }
                .accessibilityIdentifier("export-household-backup")
                KyndynCallout(kind: .privacy, message: "The backup includes household records and completion history. It excludes PINs, authentication, Apple account details, notification settings, tokens, and device information.")
            }
            Section("What stays private") {
                Label("Device-only protection", systemImage: "iphone.gen3.lock")
                Text("Your kyndyn PIN, Face ID state, notification choices, calendar selection, weather cache, and device profile stay on this device and are not included in household sync or backups.")
                Label("Privacy-safe diagnostics", systemImage: "waveform.path.ecg")
                Text("Diagnostics may record an operation type and broad error category. They do not include names, quest titles, announcement text, invitation links, PINs, tokens, or household record contents.")
                    .foregroundStyle(.secondary)
            }
            Section("Restore limitation") {
                KyndynCallout(kind: .caution, message: "Restores and Rowan transfers require an empty installation. They do not merge with or replace this household. Export a fresh backup before changing devices or sync environments.")
            }
            Section("Backup and family sync") {
                Label("Two separate protections", systemImage: "lock.icloud.fill")
                Text("Family sync keeps supported household changes aligned across invited Apple devices. An exported backup is a separate file you control and can keep in a private location in Files.")
                Text("Keep a recent backup even when family sync is up to date. Never share a backup publicly because it contains household names, quests, and completion history.")
                    .foregroundStyle(.secondary)
            }
            if let household = households.first, !household.isSample {
                Section("Remove from this device") {
                    Button("Remove household from this device",
                           systemImage: "trash", role: .destructive) {
                        removalConfirmation = ""
                        showingRemoval = true
                    }
                    .disabled(!hasFreshBackup)
                    .accessibilityIdentifier("remove-household-from-device")
                    KyndynCallout(
                        kind: hasFreshBackup ? .caution : .privacy,
                        message: removalMessage(for: household))
                }
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
        .navigationTitle("Data and privacy")
        .onAppear { recoveryReceipt = CloudRecoveryAudit.latestReceipt() }
        .fileExporter(
            isPresented: $exporting, document: document,
            contentType: .json,
            defaultFilename: "kyndyn-household-backup.json"
        ) { result in
            if case .success = result {
                lastBackupExportTimestamp = Date().timeIntervalSince1970
            } else if case .failure(let error) = result {
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
        .sheet(isPresented: $showingRemoval) {
            NavigationStack {
                Form {
                    Section("Before you continue") {
                        KyndynCallout(kind: .caution, message: "This permanently removes this household’s local profiles, quests, history, announcements, and sync metadata from this device. It does not delete the iCloud household or stop sharing.")
                        Text("A private backup was exported on this device within the last 24 hours.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Confirm household name") {
                        TextField(households.first?.name ?? "Household name",
                                  text: $removalConfirmation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("household-removal-confirmation")
                    }
                }
                .navigationTitle("Remove local data")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingRemoval = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Remove", role: .destructive) {
                            guard let household = households.first else { return }
                            do {
                                try app.removeHouseholdFromDevice(
                                    household,
                                    confirmation: removalConfirmation,
                                    context: context)
                                showingRemoval = false
                            } catch {
                                app.errorMessage = error.localizedDescription
                            }
                        }
                        .disabled(removalConfirmation != households.first?.name)
                        .accessibilityIdentifier("confirm-household-removal")
                    }
                }
            }
            .presentationDetents([.medium, .large])
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
                settings: settings.first { $0.householdID == household.id },
                broadcasts: broadcasts.filter {
                    $0.householdID == household.id
                })
            verification = try HouseholdTransferCodec.verifyExport(data)
            document = TransferDocument(data: data)
            exporting = true
        } catch {
            app.errorMessage = error.localizedDescription
        }
    }

    private func runSafetyCheck() {
        guard let household = households.first else { return }
        do {
            safetyReport = try HouseholdSafetyAudit.inspect(
                household: household, context: context,
                lastBackupExportTimestamp: lastBackupExportTimestamp)
        } catch {
            app.errorMessage = "The safety check couldn’t finish. Nothing was changed."
        }
    }

    private var hasFreshBackup: Bool {
        lastBackupExportTimestamp > 0 &&
            Date().timeIntervalSince1970 - lastBackupExportTimestamp < 86_400
    }

    private func removalMessage(for household: Household) -> String {
        if !hasFreshBackup {
            return "Export a fresh private backup first. Removal stays unavailable until this device confirms a successful export within the last 24 hours."
        }
        let mode = cloudStates.first { $0.householdID == household.id }?.mode
        if mode == .owner || mode == .participant {
            return "The iCloud household and its share remain intact. You can recover it later, but removing it here does not remove participants or stop sharing."
        }
        return "This household appears to be local-only. Keep the exported file safe because iCloud recovery may not be available."
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
    @Query private var completions: [QuestCompletion]
    let person: Person?
    @State private var draft: PersonDraft
    @State private var targetXP = 0
    @State private var loadedTargetXP = false

    init(person: Person?) {
        self.person = person
        _draft = State(initialValue: person.map {
            PersonDraft(name: $0.name, role: $0.role, colorHex: $0.colorHex,
                        companionID: $0.companionID,
                        startingXPAdjustment: $0.startingXPAdjustment)
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
                HStack(spacing: 12) {
                    Text("Active companion")
                    Spacer()
                    CompanionArt(id: draft.companionID)
                        .frame(width: 38, height: 38)
                    Picker("Active companion", selection: $draft.companionID) {
                        ForEach(availableCompanions, id: \.self) { id in
                            Text(id.capitalized).tag(id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
            if let person {
                Section("Progress") {
                    LabeledContent("Current level", value: "\(targetXP / 100 + 1)")
                    TextField("Total XP", value: $targetXP,
                              format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                    Text("Set the XP they should begin with in kyndyn. Quest history, streaks, badges, and family reward progress are not created or changed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Collection access") {
                    Text("Parents can make collection items available without changing earned progress.")
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach(CollectionCatalog.companionIDs.filter {
                        !person.earnedCompanionIDs.contains($0)
                    }, id: \.self) { id in
                        Button("Unlock \(id.capitalized) companion") {
                            grantCompanion(id, to: person)
                        }
                    }
                    ForEach(CollectionCatalog.backgrounds.filter {
                        !person.earnedBackgroundIDs.contains($0.id)
                    }) { background in
                        Button("Unlock \(background.name) background") {
                            grantBackground(background.id, to: person)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(KyndynScreenBackground())
        .navigationTitle(person == nil ? "New person" : "Edit person")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !loadedTargetXP, let person else { return }
            targetXP = max(0, questXP(for: person) + person.startingXPAdjustment)
            loadedTargetXP = true
        }
        .toolbar {
            if person == nil { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let household = households.first else { return }
                    do {
                        if let person {
                            guard (0...1_000_000).contains(targetXP) else {
                                app.errorMessage = "Total XP must be between 0 and 1,000,000."
                                return
                            }
                            draft.startingXPAdjustment = targetXP - questXP(for: person)
                            try app.updatePerson(person, draft: draft, context: context)
                        }
                        else { try app.createPerson(draft, householdID: household.id, context: context) }
                        dismiss()
                    } catch { app.errorMessage = error.localizedDescription }
                }
            }
        }
        .errorAlert(app: app)
    }

    private var availableCompanions: [String] {
        person.map { CollectionCatalog.normalizedCompanions($0.earnedCompanionIDs) }
            ?? CollectionCatalog.starterCompanionIDs
    }

    private func questXP(for person: Person) -> Int {
        completions.filter { $0.personID == person.id && $0.reversedAt == nil }
            .reduce(0) { $0 + $1.awardedXP }
    }

    private func grantCompanion(_ id: String, to person: Person) {
        do { try app.grantCompanion(id, to: person, context: context) }
        catch { app.errorMessage = error.localizedDescription }
    }

    private func grantBackground(_ id: String, to person: Person) {
        do { try app.grantBackground(id, to: person, context: context) }
        catch { app.errorMessage = error.localizedDescription }
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
            Section("Plan") {
                NavigationLink {
                    QuestTemplateLibraryView()
                } label: {
                    Label("Quest templates", systemImage: "square.grid.2x2.fill")
                }
                NavigationLink {
                    QuestScheduleOverviewView()
                } label: {
                    Label("Schedule overview", systemImage: "calendar")
                }
            }
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

struct QuestPlanningView: View {
    @Query private var households: [Household]
    @Query private var quests: [Quest]

    private var issues: [QuestScheduleIssue] {
        quests.flatMap(QuestScheduleDiagnostics.issues(for:))
    }

    var body: some View {
        List {
            Section("Start faster") {
                NavigationLink { QuestTemplateLibraryView() } label: {
                    Label("Quest templates", systemImage: "square.grid.2x2.fill")
                }
                Text("Start with a common routine, then choose the people, timing, and reminders that fit your family.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("See what is coming") {
                NavigationLink { QuestScheduleOverviewView() } label: {
                    Label("Two-week schedule", systemImage: "calendar")
                }
                LabeledContent("Active quests",
                    value: "\(quests.filter { $0.deletedAt == nil }.count)")
            }
            Section("Schedule health") {
                if issues.isEmpty {
                    LabeledContent("Legacy schedule check", value: "No issues")
                        .foregroundStyle(.secondary)
                } else {
                    NavigationLink { QuestScheduleHealthView() } label: {
                        Label("\(issues.count) item\(issues.count == 1 ? "" : "s") to review",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                Text(issues.isEmpty
                     ? "New quests are checked before saving. This fallback watches for older, restored, imported, or synchronized schedules."
                     : "Safe repairs never remove completion history or recalculate previously awarded XP.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Quest planning")
        .accessibilityIdentifier("quest-planning")
    }
}

struct QuestTemplateLibraryView: View {
    @State private var selectedTemplate: QuestTemplate?
    private let columns = [GridItem(.adaptive(minimum: 250), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(QuestTemplateCatalog.templates) { template in
                    Button {
                        selectedTemplate = template
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(template.title, systemImage: template.symbol)
                                .font(.headline)
                            Text(template.detail)
                                .font(.subheadline).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack {
                                KyndynStatusPill(text: "\(template.xp) XP",
                                                 systemImage: "bolt.fill",
                                                 tint: .purple)
                                KyndynStatusPill(text: template.scheduleLabel,
                                                 systemImage: "repeat",
                                                 tint: .blue)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 132,
                               alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .kyndynCard(tint: .purple)
                    .accessibilityIdentifier("quest-template-\(template.id)")
                    .accessibilityHint("Opens an editable new quest")
                }
            }
            .padding()
            .frame(maxWidth: AdaptiveLayout.managementContentMaximum)
        }
        .frame(maxWidth: .infinity)
        .background(KyndynScreenBackground())
        .navigationTitle("Quest templates")
        .sheet(item: $selectedTemplate) { template in
            NavigationStack {
                QuestEditorView(quest: nil, template: template)
            }
        }
    }
}

struct QuestScheduleOverviewView: View {
    @Query private var households: [Household]
    @Query(sort: \Quest.createdAt) private var quests: [Quest]

    private var household: Household? { households.first }
    private var days: [QuestScheduleDay] {
        guard let household else { return [] }
        return QuestScheduleProjection.days(
            quests: quests, starting: .now, count: 14,
            timeZoneIdentifier: household.timeZoneIdentifier)
    }

    var body: some View {
        List(days) { day in
            Section {
                if scheduledQuests(day).isEmpty {
                    Text("No quests scheduled")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(scheduledQuests(day)) { quest in
                        NavigationLink { QuestEditorView(quest: quest) } label: {
                            QuestManagementLabel(quest: quest)
                        }
                    }
                }
            } header: {
                Text(day.date.formatted(.dateTime.weekday(.wide).month().day()))
            }
        }
        .navigationTitle("Two-week schedule")
        .accessibilityIdentifier("quest-schedule-overview")
    }

    private func scheduledQuests(_ day: QuestScheduleDay) -> [Quest] {
        let ids = Set(day.questIDs)
        return quests.filter { ids.contains($0.id) }
    }
}

struct QuestScheduleHealthView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var households: [Household]
    @Query(sort: \Quest.createdAt) private var quests: [Quest]
    @State private var confirmRepair = false
    @State private var repairedMessage: String?

    private var issues: [QuestScheduleIssue] {
        quests.flatMap(QuestScheduleDiagnostics.issues(for:))
    }
    private var repairableCount: Int {
        Set(issues.filter { $0.safelyRepairable }.map(\.questID)).count
    }

    var body: some View {
        List {
            if issues.isEmpty {
                ContentUnavailableView("Schedules look good",
                    systemImage: "checkmark.circle.fill",
                    description: Text("No recurrence problems need attention."))
            } else {
                Section("Review") {
                    ForEach(issues) { issue in
                        NavigationLink {
                            if let quest = quests.first(where: { $0.id == issue.questID }) {
                                QuestEditorView(quest: quest)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(issue.questTitle).font(.headline)
                                Text(issue.message).font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(issue.safelyRepairable ? "Safe repair available" :
                                        "Choose the intended dates manually")
                                    .font(.caption)
                                    .foregroundStyle(issue.safelyRepairable ? .green : .orange)
                            }
                        }
                    }
                }
                if repairableCount > 0 {
                    Section("Safe repair") {
                        Button("Repair \(repairableCount) quest\(repairableCount == 1 ? "" : "s")",
                               systemImage: "wrench.and.screwdriver") {
                            confirmRepair = true
                        }
                        Text("Missing weekdays use the quest’s start day. Unsupported intervals return to weekly. Deadlines are never changed automatically.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            if let repairedMessage {
                Section { Label(repairedMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green) }
            }
        }
        .navigationTitle("Schedule health")
        .confirmationDialog("Repair safe schedule issues?",
                            isPresented: $confirmRepair,
                            titleVisibility: .visible) {
            Button("Repair schedules") { repair() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Completion history and previously awarded XP stay unchanged. Repairs will sync to shared family devices.")
        }
        .errorAlert(app: app)
    }

    private func repair() {
        guard let household = households.first else { return }
        do {
            let count = try app.repairQuestSchedules(
                quests, household: household, context: context)
            repairedMessage = count == 0 ? "No safe repairs were needed." :
                "Repaired \(count) quest schedule\(count == 1 ? "" : "s")."
        } catch {
            app.errorMessage = error.localizedDescription
        }
    }
}

private extension QuestTemplate {
    var scheduleLabel: String {
        switch scheduleKind {
        case .oneTime: return "One time"
        case .daily: return "Daily"
        case .weekly:
            return weekdays == Set(2...6) ? "Weekdays" : "Weekly"
        }
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

    init(quest: Quest?, template: QuestTemplate? = nil) {
        self.quest = quest
        var value = template?.draft() ?? QuestDraft()
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
            .onChange(of: draft.scheduleKind) { _, newValue in
                if newValue != .weekly {
                    draft.repeatIntervalWeeks = 1
                }
            }
            Section("Deadline") {
                Toggle("Add due date", isOn: $draft.hasDueDate)
                if draft.hasDueDate {
                    DatePicker("Due date", selection: $draft.dueDate, displayedComponents: .date)
                    Toggle("Specific time", isOn: $draft.hasDueTime)
                    if draft.hasDueTime { DatePicker("Due time", selection: $draft.dueTime, displayedComponents: .hourAndMinute) }
                    if deadlinePrecedesStart {
                        Label("Due date must be on or after the start date.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
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
                .disabled(deadlinePrecedesStart)
            }
        }
        .errorAlert(app: app)
    }

    private var deadlinePrecedesStart: Bool {
        guard draft.hasDueDate else { return false }
        let calendar = ProgressionEngine.calendar(
            timeZoneIdentifier: households.first?.timeZoneIdentifier ??
                TimeZone.current.identifier)
        return calendar.startOfDay(for: draft.dueDate) <
            calendar.startOfDay(for: draft.startDate)
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
    @Query private var broadcasts: [FamilyBroadcast]
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
            Section("Recent sync health") {
                let health = SyncHealthSummary.make(
                    state: state, pendingCount: pending.count)
                Label(health.title, systemImage: healthIcon(health.tone))
                    .foregroundStyle(healthColor(health.tone))
                Text(health.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("This summary never includes names, quest titles, cloud record IDs, or Apple’s raw error text.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Section("What family sync does") {
                Text("Keeps people, quests, schedules, completions, rewards, and shared household settings consistent across invited devices.")
                KyndynCallout(kind: .localOnly, message: "Your kyndyn PIN, authentication, notification permission, quiet hours, and device preferences never leave this device.")
            }
            if let household {
                let preview = sync.preview(
                    household: household, people: people, quests: quests,
                    completions: completions, goals: goals,
                    broadcasts: broadcasts)
                Section("Ready to synchronize") {
                    LabeledContent("People", value: "\(preview.people)")
                    LabeledContent("Quests", value: "\(preview.quests)")
                    LabeledContent("Completion events", value: "\(preview.completions)")
                    LabeledContent("Announcements", value: "\(preview.broadcasts)")
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

    private func healthIcon(_ tone: SyncHealthSummary.Tone) -> String {
        switch tone {
        case .healthy: "checkmark.circle.fill"
        case .waiting: "clock.arrow.circlepath"
        case .attention: "exclamationmark.triangle.fill"
        case .localOnly: "iphone"
        }
    }

    private func healthColor(_ tone: SyncHealthSummary.Tone) -> Color {
        switch tone {
        case .healthy: .green
        case .waiting: .orange
        case .attention: .red
        case .localOnly: .secondary
        }
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
        records += broadcasts.map { SyncSnapshot.broadcast($0) }
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
                KyndynCallout(kind: .localOnly, message: "Face ID, Touch ID, or the device passcode is the primary parent check. An optional kyndyn PIN is stored only in this device’s Keychain.")
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
                KyndynCallout(kind: .caution, message: "kyndyn has no server account or email recovery. Use device-owner authentication to replace a forgotten PIN. Without either method, kyndyn cannot safely prove parental identity.")
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
                    Toggle("Enable notifications", isOn: binding(setting, \.notificationsEnabled))
                    Toggle("Family announcements", isOn: binding(
                        setting, \.broadcastNotificationsEnabled))
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
                    Toggle("Show announcement details", isOn: binding(
                        setting, \.showBroadcastDetailsOnLockScreen))
                    KyndynCallout(kind: .privacy, message: setting.showQuestDetailsOnLockScreen ? "Reminder previews may reveal quest names on the lock screen." : "Reminders use general wording until kyndyn is opened.")
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
            if let image = UIImage(named: id) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "sparkles").resizable().scaledToFit().foregroundStyle(.purple)
            }
        }
            .accessibilityLabel("\(CollectionCatalog.companion(named: id).name), kyndyn companion")
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
    func refreshStatusPill(
        isRefreshing: Bool, topPadding: CGFloat = 8
    ) -> some View {
        overlay(alignment: .top) {
            if isRefreshing {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text("Refreshing…").font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThickMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.22)))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                .padding(.top, topPadding)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Refreshing family updates")
                .accessibilityIdentifier("refresh-status-indicator")
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isRefreshing)
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
