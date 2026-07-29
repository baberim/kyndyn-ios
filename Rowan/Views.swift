import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var households: [Household]
    @Query(sort: \Person.createdAt) private var people: [Person]

    var body: some View {
        Group {
            if households.isEmpty {
                OnboardingView()
            } else if app.selectedPersonID == nil {
                ProfilePickerView()
            } else {
                MainView()
            }
        }
        .tint(.purple)
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @State private var isWorking = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [.purple.opacity(0.22), .cyan.opacity(0.12), Color(.systemBackground)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "leaf.fill").font(.system(size: 58)).foregroundStyle(.purple)
                Text("Welcome to Rowan").font(.largeTitle.bold()).multilineTextAlignment(.center)
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
                Text("Uses fictional people only. You can edit them in the Parent area.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(32).frame(maxWidth: 560)
        }
        .accessibilityIdentifier("onboarding")
        .alert("Rowan couldn’t get started", isPresented: Binding(get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(app.errorMessage ?? "") }
    }
}

struct ProfilePickerView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \Person.createdAt) private var people: [Person]
    let columns = [GridItem(.adaptive(minimum: 145), spacing: 18)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    Text("Who’s using Rowan?").font(.largeTitle.bold())
                    Text("Choose your profile to see the right quests.").foregroundStyle(.secondary)
                }.padding(.vertical, 28)
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(people.filter { $0.deletedAt == nil }) { person in
                        Button { app.selectedPersonID = person.id } label: {
                            VStack(spacing: 12) {
                                CompanionArt(id: person.companionID).frame(height: 112)
                                Text(person.name).font(.title3.bold()).foregroundStyle(.primary)
                                Text(person.role == .parent ? "Parent" : "Family member").font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity).padding()
                            .background(Color(hex: person.colorHex).opacity(0.16), in: RoundedRectangle(cornerRadius: 24))
                        }
                        .buttonStyle(.plain)
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
    @Query private var people: [Person]
    private var selected: Person? { people.first { $0.id == app.selectedPersonID } }

    var body: some View {
        TabView {
            DashboardView().tabItem { Label("Home", systemImage: "house.fill") }
            QuestListView().tabItem { Label("Quests", systemImage: "checklist") }
            if selected?.role == .parent {
                ParentAreaView().tabItem { Label("Parent", systemImage: "lock.shield.fill") }
            }
            ProfilePickerView().tabItem { Label("Switch", systemImage: "person.2.fill") }
        }
    }
}

struct DashboardView: View {
    @Environment(AppModel.self) private var app
    @Query private var households: [Household]
    @Query private var people: [Person]
    @Query private var completions: [QuestCompletion]
    private var person: Person? { people.first { $0.id == app.selectedPersonID } }
    private var household: Household? { households.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let person, let household {
                    let progress = ProgressionEngine.progress(personID: person.id, completions: completions, now: .now, timeZoneIdentifier: household.timeZoneIdentifier)
                    VStack(spacing: 18) {
                        HStack {
                            CompanionArt(id: person.companionID).frame(width: 100, height: 100)
                            VStack(alignment: .leading) {
                                Text("Hi, \(person.name)").font(.largeTitle.bold())
                                Text("Small steps count.").foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        HStack(spacing: 12) {
                            StatCard(value: "\(progress.xp)", label: "XP")
                            StatCard(value: "\(progress.level)", label: "Level")
                            StatCard(value: "\(progress.currentStreak)", label: "Day streak")
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text(household.rewardTitle).font(.headline); Spacer(); Text("\(ProgressionEngine.familyXP(completions)) / \(household.rewardGoalXP) XP").font(.subheadline.monospacedDigit()) }
                            ProgressView(value: min(Double(ProgressionEngine.familyXP(completions)), Double(household.rewardGoalXP)), total: Double(household.rewardGoalXP))
                        }.card()
                        QuestListView(compact: true)
                    }.padding()
                }
            }.navigationTitle("Today")
        }
    }
}

struct QuestListView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var households: [Household]
    @Query(sort: \Quest.createdAt) private var quests: [Quest]
    @Query private var completions: [QuestCompletion]
    var compact = false

    private var visible: [Quest] {
        guard let household = households.first, let personID = app.selectedPersonID else { return [] }
        return quests.filter { $0.deletedAt == nil && $0.participantIDs.contains(personID) && ProgressionEngine.isScheduled($0, on: .now, timeZoneIdentifier: household.timeZoneIdentifier) }
    }

    var body: some View {
        Group {
            if compact { content } else { NavigationStack { ScrollView { content.padding() }.navigationTitle("Today’s quests") } }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if compact { Text("Your quests").font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading) }
            if visible.isEmpty {
                ContentUnavailableView("All clear", systemImage: "checkmark.circle", description: Text("No quests are scheduled for you today."))
            }
            ForEach(visible) { quest in QuestRow(quest: quest) }
        }
    }

    @ViewBuilder private func QuestRow(quest: Quest) -> some View {
        if let household = households.first, let personID = app.selectedPersonID {
            let day = ProgressionEngine.dayKey(.now, timeZoneIdentifier: household.timeZoneIdentifier)
            let done = completions.contains { $0.questID == quest.id && $0.personID == personID && $0.occurrenceDay == day && $0.reversedAt == nil }
            HStack(spacing: 14) {
                Button {
                    do {
                        if done { try app.undo(quest, personID: personID, household: household, completions: completions, context: context) }
                        else { try app.complete(quest, personID: personID, household: household, completions: completions, context: context) }
                    } catch { app.errorMessage = error.localizedDescription }
                } label: {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.title).foregroundStyle(done ? .green : .purple)
                }.accessibilityLabel(done ? "Undo \(quest.title)" : "Complete \(quest.title)").accessibilityIdentifier("quest-toggle-\(quest.title)")
                VStack(alignment: .leading, spacing: 3) {
                    Text(quest.title).font(.headline).strikethrough(done)
                    if !quest.detail.isEmpty { Text(quest.detail).font(.subheadline).foregroundStyle(.secondary) }
                    Text(quest.completionMode == .sharedAll ? "Shared check-in" : "Individual").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("+\(ProgressionEngine.effectiveXP(base: quest.xp, overdueDays: ProgressionEngine.overdueDays(for: quest, now: .now, timeZoneIdentifier: household.timeZoneIdentifier))) XP").font(.subheadline.bold()).foregroundStyle(.purple)
            }.card()
        }
    }
}

struct ParentAreaView: View {
    @Environment(\.modelContext) private var context
    @Query private var households: [Household]
    @Query(sort: \Person.createdAt) private var people: [Person]
    @Query(sort: \Quest.createdAt) private var quests: [Quest]
    @State private var showingPerson = false
    @State private var showingQuest = false

    var body: some View {
        NavigationStack {
            List {
                Section("People") {
                    ForEach(people.filter { $0.deletedAt == nil }) { person in
                        HStack { CompanionArt(id: person.companionID).frame(width: 44, height: 44); Text(person.name); Spacer(); Text(person.role.rawValue.capitalized).foregroundStyle(.secondary) }
                    }
                    Button("Add person", systemImage: "person.badge.plus") { showingPerson = true }
                }
                Section("Quests") {
                    ForEach(quests.filter { $0.deletedAt == nil }) { quest in
                        VStack(alignment: .leading) { Text(quest.title); Text("\(quest.xp) XP · \(quest.scheduleKind.rawValue)").font(.caption).foregroundStyle(.secondary) }
                    }
                    Button("Add quest", systemImage: "plus.circle") { showingQuest = true }
                }
            }.navigationTitle("Parent")
            .sheet(isPresented: $showingPerson) { AddPersonView() }
            .sheet(isPresented: $showingQuest) { AddQuestView() }
        }
    }
}

struct AddPersonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var households: [Household]
    @State private var name = ""
    @State private var role: ProfileRole = .child
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Role", selection: $role) { ForEach(ProfileRole.allCases, id: \.self) { Text($0.rawValue.capitalized) } }
            }.navigationTitle("New person").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    if let household = households.first {
                        context.insert(Person(householdID: household.id, name: name.trimmingCharacters(in: .whitespaces), role: role, colorHex: "#6F2DBD", companionID: "bop"))
                        try? context.save(); dismiss()
                    }
                }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
        }
    }
}

struct AddQuestView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var households: [Household]
    @Query private var people: [Person]
    @State private var title = ""
    @State private var xp = 10
    @State private var selected = Set<UUID>()
    @State private var daily = true
    var body: some View {
        NavigationStack {
            Form {
                TextField("Quest title", text: $title)
                Stepper("\(xp) XP", value: $xp, in: 1...500)
                Toggle("Repeat daily", isOn: $daily)
                Section("Participants") {
                    ForEach(people.filter { $0.deletedAt == nil }) { person in
                        Button { if selected.contains(person.id) { selected.remove(person.id) } else { selected.insert(person.id) } } label: {
                            HStack { Text(person.name).foregroundStyle(.primary); Spacer(); if selected.contains(person.id) { Image(systemName: "checkmark") } }
                        }
                    }
                }
            }.navigationTitle("New quest").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    if let household = households.first {
                        context.insert(Quest(householdID: household.id, title: title.trimmingCharacters(in: .whitespaces), xp: xp, participantIDs: Array(selected), completionMode: selected.count > 1 ? .sharedAll : .individual, scheduleKind: daily ? .daily : .oneTime))
                        try? context.save(); dismiss()
                    }
                }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || selected.isEmpty) }
            }
        }
    }
}

struct CompanionArt: View {
    let id: String
    var body: some View {
        Image(id).resizable().scaledToFit()
            .accessibilityLabel("\(id.capitalized), Rowan companion")
    }
}

struct StatCard: View {
    let value: String
    let label: String
    var body: some View { VStack(spacing: 3) { Text(value).font(.title2.bold()).monospacedDigit(); Text(label).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).card() }
}

extension View {
    func card() -> some View { padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)).overlay { RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.08)) } }
}
extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0x6F2DBD
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

