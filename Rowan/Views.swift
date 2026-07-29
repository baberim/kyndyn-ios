import SwiftUI
import SwiftData

private let companionChoices = ["spark", "orbit", "pixel", "comet", "bop"]
private let colorChoices = ["#6F2DBD", "#007AFF", "#00A6A6", "#34C759", "#F26B5B", "#FF9500"]

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
                    Text("Rowan").font(.largeTitle.bold())
                    ProgressView().accessibilityLabel("Opening Rowan")
                }
                .transition(.opacity)
            }
        }
        .tint(.purple)
        .task {
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
                Text("Someone invited this device to a Rowan family. Rowan will verify it before creating any sample household.")
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
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(sync.isWorking)
                .accessibilityHint("Validates the shared Rowan household")
                Text(sync.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Invitation status, \(sync.statusMessage)")
            }
            .navigationTitle("Join Rowan family")
        }
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @State private var isWorking = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "leaf.fill").font(.system(size: 58)).foregroundStyle(.purple)
                Text("Welcome to Rowan").font(.largeTitle.bold()).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("A calm home base for quests, progress, and family wins. Rowan works offline and keeps this starter household on this device.")
                    .font(.title3).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button {
                    isWorking = true
                    do { try app.seedSample(into: context) } catch { app.errorMessage = error.localizedDescription }
                    isWorking = false
                } label: {
                    Label("Create a sample household", systemImage: "sparkles").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(isWorking)
                Text("Uses fictional people only. You can edit them in the protected Parent area.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(32).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background(RowanLaunchBackground())
        .accessibilityIdentifier("onboarding")
        .errorAlert(app: app)
    }
}

struct ProfilePickerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Person.createdAt) private var people: [Person]
    @Query private var settings: [LocalDeviceSettings]
    let columns = [GridItem(.adaptive(minimum: 145), spacing: 18)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    Text("Who’s using Rowan?").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
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
                                CompanionArt(id: person.companionID).frame(height: 112)
                                Text(person.name).font(.title3.bold()).foregroundStyle(.primary)
                                Text(person.role == .parent ? "Parent" : "Family member").font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity).padding()
                            .background(Color(hex: person.colorHex).opacity(0.16), in: RoundedRectangle(cornerRadius: 24))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(person.name), \(person.role == .parent ? "parent" : "family member")")
                        .accessibilityHint("Shows this person’s Rowan dashboard")
                        .accessibilityIdentifier("profile-\(person.name)")
                    }
                }.padding()
            }
            .navigationTitle("Rowan")
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
                        SecureField("Rowan PIN", text: $pin).keyboardType(.numberPad)
                            .textContentType(.password).padding()
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                            .accessibilityLabel("Rowan parent PIN")
                        Button("Unlock with Rowan PIN") {
                            if access.unlock(pin: pin) { pin = "" }
                        }.buttonStyle(.bordered).controlSize(.large).disabled(pin.isEmpty)
                    }
                    if let message = access.message {
                        Text(message).font(.callout).foregroundStyle(.secondary)
                    }
                    Text("Canceling leaves Rowan unlocked for everyday child use; only parent tools stay locked.")
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
                        HStack {
                            CompanionArt(id: person.companionID).frame(width: 100, height: 100)
                            VStack(alignment: .leading) {
                                Text("Hi, \(person.name)").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                                Text("Small steps count.").foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        ViewThatFits {
                            HStack(spacing: 12) { stats(progress) }
                            VStack(spacing: 12) { stats(progress) }
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(household.rewardTitle).font(.headline)
                                Spacer()
                                Text("\(ProgressionEngine.familyXP(completions)) / \(household.rewardGoalXP) XP").font(.subheadline.monospacedDigit())
                            }
                            ProgressView(value: min(Double(ProgressionEngine.familyXP(completions)), Double(household.rewardGoalXP)), total: Double(household.rewardGoalXP))
                        }.card()
                        QuestListView(compact: true)
                    }.padding()
                }
            }.navigationTitle("Today")
        }
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
            ForEach(visible, id: \.0.id) { quest, status in QuestRow(quest: quest, status: status) }
        }
    }

    @ViewBuilder private func QuestRow(quest: Quest, status: QuestTemporalStatus) -> some View {
        if let household = households.first, let personID = app.selectedPersonID {
            let done = status == .completed
            HStack(spacing: 14) {
                Button {
                    do {
                        if done { try app.undo(quest, personID: personID, household: household, completions: completions, context: context) }
                        else { try app.complete(quest, personID: personID, household: household, completions: completions, context: context) }
                    } catch { app.errorMessage = error.localizedDescription }
                } label: {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.title).foregroundStyle(done ? .green : .purple)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(done ? "Undo \(quest.title)" : "Complete \(quest.title)")
                .accessibilityHint(done ? "Reverses this occurrence and recalculates progress" : "Records this occurrence as complete")
                .accessibilityIdentifier("quest-toggle-\(quest.title)")
                VStack(alignment: .leading, spacing: 3) {
                    Text(quest.title).font(.headline).strikethrough(done)
                    if !quest.detail.isEmpty { Text(quest.detail).font(.subheadline).foregroundStyle(.secondary) }
                    Text(statusLabel(status, quest: quest)).font(.caption).foregroundStyle(status == .overdue ? .orange : .secondary)
                }
                Spacer()
                Text("+\(done ? quest.xp : ProgressionEngine.effectiveXP(base: quest.xp, overdueDays: ProgressionEngine.overdueDays(for: quest, now: .now, timeZoneIdentifier: household.timeZoneIdentifier))) XP")
                    .font(.subheadline.bold()).foregroundStyle(.purple)
            }.card()
        }
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
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { PeopleManagementView() } label: { Label("People", systemImage: "person.2.fill") }
                    NavigationLink { QuestManagementView() } label: { Label("Quests", systemImage: "checklist") }
                    NavigationLink { CloudSyncSettingsView() } label: {
                        Label("Family sync", systemImage: "icloud")
                    }
                    NavigationLink { NotificationSettingsView() } label: { Label("Reminders", systemImage: "bell.fill") }
                    NavigationLink { ParentSecurityView() } label: { Label("Parent security", systemImage: "lock.shield.fill") }
                }
                Section {
                    Button("Lock Parent area", systemImage: "lock.fill") { access.lock() }
                }
            }.navigationTitle("Parent")
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 54))]) {
                    ForEach(colorChoices, id: \.self) { color in
                        Button { draft.colorHex = color } label: {
                            Circle().fill(Color(hex: color)).frame(width: 42, height: 42)
                                .overlay { if draft.colorHex == color { Image(systemName: "checkmark").foregroundStyle(.white).bold() } }
                        }.accessibilityLabel("Profile color \(color)").accessibilityValue(draft.colorHex == color ? "Selected" : "")
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
        case .weekly: return "Selected weekdays"
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
                if draft.scheduleKind == .weekly { WeekdayPicker(selection: $draft.weekdays) }
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
                LabeledContent("Sync", value: sync.statusMessage)
                    .accessibilityLabel("Family sync status, \(sync.statusMessage)")
                if !pending.isEmpty {
                    LabeledContent("Waiting to sync", value: "\(pending.count) changes")
                }
                if let date = state?.lastSuccessfulSyncAt {
                    LabeledContent("Last updated", value: date.formatted())
                }
            }
            Section("What family sync does") {
                Text("Keeps people, quests, schedules, completions, rewards, and shared household settings consistent across invited devices.")
                Text("Your Rowan PIN, authentication, notification permission, quiet hours, and device preferences stay only on this device.")
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
                    if state?.mode == .owner || state?.mode == .participant {
                        Button("Refresh now", systemImage: "arrow.clockwise") {
                            guard let state else { return }
                            Task { await sync.synchronize(state: state, context: context) }
                        }
                        .disabled(sync.isWorking)
                    } else {
                        Button("Enable family sync", systemImage: "icloud.and.arrow.up") {
                            confirmEnable = true
                        }
                        .disabled(sync.isWorking)
                    }
                } footer: {
                    Text("Live family sync requires the authorized Apple Developer team and iCloud container. Until configured, Rowan stays safely local-only.")
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
            Text("Rowan will prepare this household in the owner’s iCloud and create an Apple sharing invitation. Local data remains available if setup is interrupted.")
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
                Text("Face ID, Touch ID, or the device passcode is Rowan’s primary parent check. A Rowan PIN is an optional fallback stored only in this device’s Keychain.")
            }
            Section(access.hasPIN ? "Change Rowan PIN" : "Add Rowan PIN") {
                SecureField("New 6–12 digit PIN", text: $pin).keyboardType(.numberPad)
                SecureField("Confirm PIN", text: $confirmation).keyboardType(.numberPad)
                Button(access.hasPIN ? "Change PIN" : "Save PIN") {
                    guard pin == confirmation else { message = "The PIN entries don’t match."; return }
                    if let validation = PINValidation.message(for: pin) { message = validation; return }
                    do { try access.configurePIN(pin); pin = ""; confirmation = ""; message = "Rowan PIN saved securely on this device." }
                    catch { message = error.localizedDescription }
                }.disabled(pin.isEmpty || confirmation.isEmpty)
            }
            if access.hasPIN {
                Section {
                    Button("Disable Rowan PIN", role: .destructive) { confirmDisable = true }
                }
            }
            if let message { Section { Text(message).foregroundStyle(.secondary) } }
            Section("Recovery limitation") {
                Text("Rowan has no server account or email recovery. If you forget the Rowan PIN, use the device owner authentication to enter this screen and replace it. If device authentication is also unavailable, Rowan cannot safely prove parental identity.")
            }
        }
        .navigationTitle("Parent security")
        .confirmationDialog("Disable the Rowan PIN?", isPresented: $confirmDisable, titleVisibility: .visible) {
            Button("Disable PIN", role: .destructive) {
                do { try access.disablePIN(); message = "Rowan PIN disabled." }
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
                        Text("Notifications are off in iOS Settings. Rowan still works normally.")
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
                    Text(setting.showQuestDetailsOnLockScreen ? "Reminder previews may reveal quest names on the lock screen." : "Reminders use general wording until Rowan is opened.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView("Settings unavailable", systemImage: "gear.badge.questionmark", description: Text("Reopen Rowan and try again."))
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
            Text("Rowan can remind this device about locally stored quests. You choose the profile, timing, and whether quest names appear.")
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
        do { try await scheduler.replaceRowanReminders(with: candidates) }
        catch { app.errorMessage = "Rowan couldn’t update reminders. Your quests are unchanged." }
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
            .accessibilityLabel("\(id.capitalized), Rowan companion")
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
        alert("Rowan couldn’t save that", isPresented: Binding(get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })) {
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
