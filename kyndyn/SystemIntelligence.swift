import AppIntents
import Foundation
import SwiftData

enum KyndynIntentError: LocalizedError, Equatable {
    case storeUnavailable
    case householdUnavailable
    case personUnavailable
    case occurrenceUnavailable
    case alreadyComplete
    case notComplete
    case invalidQuestDraft

    var errorDescription: String? {
        switch self {
        case .storeUnavailable:
            return "Open kyndyn once, then try again."
        case .householdUnavailable:
            return "Set up or join a family in kyndyn first."
        case .personUnavailable:
            return "That profile is no longer available."
        case .occurrenceUnavailable:
            return "That quest occurrence is no longer available."
        case .alreadyComplete:
            return "That quest is already complete."
        case .notComplete:
            return "That quest has not been completed."
        case .invalidQuestDraft:
            return "Check the quest name and XP, then try again."
        }
    }
}

struct KyndynPersonEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Kyndyn Profile")
    static let defaultQuery = KyndynPersonQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "Kyndyn profile")
    }
}

struct KyndynPersonQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [KyndynPersonEntity] {
        try await KyndynIntentStore.shared.waitUntilReady()
        return try await KyndynIntentStore.shared.people(ids: Set(identifiers))
    }

    func suggestedEntities() async throws -> [KyndynPersonEntity] {
        try await KyndynIntentStore.shared.waitUntilReady()
        return try await KyndynIntentStore.shared.people()
    }

    func entities(matching string: String) async throws -> [KyndynPersonEntity] {
        try await KyndynIntentStore.shared.waitUntilReady()
        return try await KyndynIntentStore.shared.people(matching: string)
    }
}

struct KyndynQuestOccurrenceEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Kyndyn Quest")
    static let defaultQuery = KyndynQuestOccurrenceQuery()

    let id: String
    let title: String
    let personName: String
    let xp: Int
    let isComplete: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(personName) · \(xp) XP")
    }
}

struct KyndynQuestOccurrenceQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws
        -> [KyndynQuestOccurrenceEntity] {
        try await KyndynIntentStore.shared.waitUntilReady()
        return try await KyndynIntentStore.shared.occurrences(
            ids: Set(identifiers), includeCompleted: true)
    }

    func suggestedEntities() async throws -> [KyndynQuestOccurrenceEntity] {
        try await KyndynIntentStore.shared.waitUntilReady()
        return try await KyndynIntentStore.shared.occurrences(
            includeCompleted: true)
    }

    func entities(matching string: String) async throws
        -> [KyndynQuestOccurrenceEntity] {
        try await KyndynIntentStore.shared.waitUntilReady()
        return try await KyndynIntentStore.shared.occurrences(
            matching: string, includeCompleted: true)
    }
}

struct ListTodayQuestsIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Today’s Kyndyn Quests"
    static let description = IntentDescription(
        "Shows today’s remaining quests for a Kyndyn profile.")
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication

    @Parameter(title: "Profile") var person: KyndynPersonEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Show today’s quests for \(\.$person)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String>
        & ProvidesDialog {
        try await KyndynIntentStore.shared.waitUntilReady()
        let result = try await KyndynIntentStore.shared.todaySummary(
            personID: person?.id)
        return .result(value: result, dialog: IntentDialog(stringLiteral: result))
    }
}

struct ShowFamilyRewardIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Family Reward Progress"
    static let description = IntentDescription(
        "Shows the current Kyndyn family reward and progress.")
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication

    func perform() async throws -> some IntentResult & ReturnsValue<String>
        & ProvidesDialog {
        try await KyndynIntentStore.shared.waitUntilReady()
        let result = try await KyndynIntentStore.shared.rewardSummary()
        return .result(value: result, dialog: IntentDialog(stringLiteral: result))
    }
}

struct OpenPersonDashboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Open a Kyndyn Profile"
    static let description = IntentDescription(
        "Opens Kyndyn on the selected person’s dashboard.")
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication

    @Parameter(title: "Profile") var person: KyndynPersonEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$person) in Kyndyn")
    }

    func perform() async throws -> some IntentResult {
        try await KyndynIntentStore.shared.waitUntilReady()
        try await KyndynIntentStore.shared.select(personID: person.id)
        return .result()
    }
}

struct CompleteQuestOccurrenceIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete a Kyndyn Quest"
    static let description = IntentDescription(
        "Completes one exact quest occurrence and queues family sync.")
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication

    @Parameter(title: "Quest") var occurrence: KyndynQuestOccurrenceEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Complete \(\.$occurrence)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await KyndynIntentStore.shared.waitUntilReady()
        let result = try await KyndynIntentStore.shared.complete(
            occurrenceID: occurrence.id)
        return .result(dialog: IntentDialog(stringLiteral: result))
    }
}

struct UndoQuestOccurrenceIntent: AppIntent {
    static let title: LocalizedStringResource = "Undo a Kyndyn Quest"
    static let description = IntentDescription(
        "Undoes one exact quest occurrence and queues family sync.")
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication

    @Parameter(title: "Quest") var occurrence: KyndynQuestOccurrenceEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Undo \(\.$occurrence)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await KyndynIntentStore.shared.waitUntilReady()
        let result = try await KyndynIntentStore.shared.undo(
            occurrenceID: occurrence.id)
        return .result(dialog: IntentDialog(stringLiteral: result))
    }
}

struct PrepareQuestIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a Kyndyn Quest"
    static let description = IntentDescription(
        "Prepares a quest for a parent to review and create in Kyndyn.")
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy =
        .requiresLocalDeviceAuthentication

    @Parameter(title: "Quest name") var questName: String
    @Parameter(title: "Profile") var person: KyndynPersonEntity
    @Parameter(title: "XP", default: 10) var xp: Int
    @Parameter(title: "Due date") var dueDate: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$questName) for \(\.$person), worth \(\.$xp) XP, due \(\.$dueDate)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await KyndynIntentStore.shared.waitUntilReady()
        try await KyndynIntentStore.shared.prepareQuest(
            title: questName, personID: person.id, xp: xp,
            dueDate: dueDate)
        return .result(dialog: "Review this quest in Kyndyn to create it.")
    }
}

struct KyndynAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ListTodayQuestsIntent(),
            phrases: [
                "Show my quests in \(.applicationName)",
                "Show my \(.applicationName) quests",
                "Show today’s quests in \(.applicationName)",
                "Show today’s \(.applicationName) quests",
                "What are today’s \(.applicationName) quests",
                "Show \(\.$person)’s quests in \(.applicationName)",
                "Show \(\.$person)’s \(.applicationName) quests"
            ],
            shortTitle: "Today’s quests",
            systemImageName: "checklist")
        AppShortcut(
            intent: ShowFamilyRewardIntent(),
            phrases: ["Show family reward progress in \(.applicationName)"],
            shortTitle: "Family reward",
            systemImageName: "gift.fill")
        AppShortcut(
            intent: OpenPersonDashboardIntent(),
            phrases: ["Open a profile in \(.applicationName)"],
            shortTitle: "Open profile",
            systemImageName: "person.crop.circle")
        AppShortcut(
            intent: CompleteQuestOccurrenceIntent(),
            phrases: ["Complete a quest in \(.applicationName)"],
            shortTitle: "Complete quest",
            systemImageName: "checkmark.circle.fill")
        AppShortcut(
            intent: UndoQuestOccurrenceIntent(),
            phrases: ["Undo a quest in \(.applicationName)"],
            shortTitle: "Undo quest",
            systemImageName: "arrow.uturn.backward.circle.fill")
        AppShortcut(
            intent: PrepareQuestIntent(),
            phrases: [
                "Add a quest in \(.applicationName)",
                "Create a quest in \(.applicationName)"
            ],
            shortTitle: "Add quest",
            systemImageName: "plus.circle.fill")
    }
}

@MainActor
final class KyndynIntentStore {
    static let shared = KyndynIntentStore()
    private var context: ModelContext?
    private var appModel: AppModel?

    func configure(container: ModelContainer, appModel: AppModel) {
        context = container.mainContext
        self.appModel = appModel
    }

    func resetForTesting() {
        context = nil
        appModel = nil
    }

    func waitUntilReady() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while context == nil && ContinuousClock.now < deadline {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(100))
        }
        guard context != nil else { throw KyndynIntentError.storeUnavailable }
    }

    func people(ids: Set<UUID>? = nil) throws -> [KyndynPersonEntity] {
        let people = try requiredContext().fetch(FetchDescriptor<Person>())
        return people.filter {
            $0.deletedAt == nil && (ids == nil || ids!.contains($0.id))
        }
        .sorted { $0.createdAt < $1.createdAt }
        .map { KyndynPersonEntity(id: $0.id, name: $0.name) }
    }

    func people(matching string: String) throws -> [KyndynPersonEntity] {
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return try people() }
        return try people().filter {
            $0.name.localizedCaseInsensitiveContains(normalized)
        }
    }

    func occurrences(ids: Set<String>? = nil, includeCompleted: Bool) throws
        -> [KyndynQuestOccurrenceEntity] {
        let context = try requiredContext()
        guard let household = try context.fetch(
            FetchDescriptor<Household>()).first else {
            throw KyndynIntentError.householdUnavailable
        }
        let people = try context.fetch(FetchDescriptor<Person>())
        let quests = try context.fetch(FetchDescriptor<Quest>())
        let completions = try context.fetch(FetchDescriptor<QuestCompletion>())
        let activePeople = Dictionary(uniqueKeysWithValues: people.filter {
            $0.deletedAt == nil
        }.map { ($0.id, $0) })
        let selectedPersonID = try context.fetch(
            FetchDescriptor<LocalDeviceSettings>()).first?.selectedPersonID
        let orderedPeople = activePeople.values.sorted { left, right in
            if left.id == selectedPersonID { return true }
            if right.id == selectedPersonID { return false }
            return left.createdAt < right.createdAt
        }

        var result = [KyndynQuestOccurrenceEntity]()
        for person in orderedPeople {
            for quest in quests where quest.deletedAt == nil &&
                quest.participantIDs.contains(person.id) {
                guard let day = ProgressionEngine.occurrenceKey(
                    for: quest, on: .now,
                    timeZoneIdentifier: household.timeZoneIdentifier) else {
                    continue
                }
                let id = Self.occurrenceID(
                    questID: quest.id, personID: person.id, day: day)
                guard ids == nil || ids!.contains(id) else { continue }
                let complete = completions.contains {
                    $0.questID == quest.id && $0.personID == person.id &&
                    $0.occurrenceDay == day && $0.reversedAt == nil
                }
                guard includeCompleted || !complete else { continue }
                result.append(KyndynQuestOccurrenceEntity(
                    id: id, title: quest.title, personName: person.name,
                    xp: quest.xp, isComplete: complete))
            }
        }
        return result.sorted {
            if $0.personName != $1.personName {
                return $0.personName.localizedCaseInsensitiveCompare(
                    $1.personName) == .orderedAscending
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) ==
                .orderedAscending
        }
    }

    func occurrences(matching string: String, includeCompleted: Bool) throws
        -> [KyndynQuestOccurrenceEntity] {
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return try occurrences(includeCompleted: includeCompleted)
        }
        return try occurrences(includeCompleted: includeCompleted).filter {
            $0.title.localizedCaseInsensitiveContains(normalized) ||
                $0.personName.localizedCaseInsensitiveContains(normalized)
        }
    }

    func todaySummary(personID: UUID?) throws -> String {
        let selected = try personID ?? selectedPersonID()
        let person = try people(ids: [selected]).first
        guard let person else { throw KyndynIntentError.personUnavailable }
        let remaining = try occurrences(includeCompleted: false).filter {
            Self.components(from: $0.id)?.personID == selected
        }
        if remaining.isEmpty { return "\(person.name) is all clear for today." }
        let titles = remaining.prefix(3).map(\.title).joined(separator: ", ")
        let extra = remaining.count > 3 ? ", and \(remaining.count - 3) more" : ""
        return "\(person.name) has \(remaining.count) quest\(remaining.count == 1 ? "" : "s") left: \(titles)\(extra)."
    }

    func rewardSummary() throws -> String {
        let context = try requiredContext()
        guard let household = try context.fetch(
            FetchDescriptor<Household>()).first else {
            throw KyndynIntentError.householdUnavailable
        }
        let goals = try context.fetch(FetchDescriptor<RewardGoal>())
        let completions = try context.fetch(FetchDescriptor<QuestCompletion>())
        let goal = ProgressionEngine.currentRewardGoal(
            goals, householdID: household.id)
        let title = goal?.title ?? household.rewardTitle
        let target = goal?.targetXP ?? household.rewardGoalXP
        let progress = goal.map {
            ProgressionEngine.rewardXP(completions, goal: $0)
        } ?? ProgressionEngine.familyXP(completions)
        return "\(title): \(min(progress, target)) of \(target) XP."
    }

    func select(personID: UUID) throws {
        let context = try requiredContext()
        guard try people(ids: [personID]).first != nil else {
            throw KyndynIntentError.personUnavailable
        }
        let setting = try context.fetch(
            FetchDescriptor<LocalDeviceSettings>()).first ?? LocalDeviceSettings()
        if setting.modelContext == nil { context.insert(setting) }
        setting.selectedPersonID = personID
        try context.save()
        appModel?.selectedPersonID = personID
        appModel?.selectedTab = 0
    }

    func prepareQuest(title: String, personID: UUID, xp: Int,
                      dueDate: Date?) throws {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 120,
              (1...500).contains(xp) else {
            throw KyndynIntentError.invalidQuestDraft
        }
        guard try people(ids: [personID]).first != nil else {
            throw KyndynIntentError.personUnavailable
        }
        guard let appModel else { throw KyndynIntentError.storeUnavailable }
        appModel.pendingSiriQuestDraft = SiriQuestDraft(
            title: normalized, personID: personID, xp: xp,
            dueDate: dueDate)
    }

    func complete(occurrenceID: String) throws -> String {
        let values = try resolve(occurrenceID)
        guard !values.entity.isComplete else {
            throw KyndynIntentError.alreadyComplete
        }
        let completions = try values.context.fetch(
            FetchDescriptor<QuestCompletion>())
        try (appModel ?? AppModel()).complete(
            values.quest, personID: values.person.id,
            household: values.household, completions: completions,
            context: values.context)
        NotificationCenter.default.post(
            name: .kyndynAutomaticSyncRequested,
            object: nil,
            userInfo: ["trigger": AutomaticSyncTrigger.localMutation.rawValue])
        return "Completed \(values.quest.title) for \(values.person.name)."
    }

    func undo(occurrenceID: String) throws -> String {
        let values = try resolve(occurrenceID)
        guard values.entity.isComplete else {
            throw KyndynIntentError.notComplete
        }
        let completions = try values.context.fetch(
            FetchDescriptor<QuestCompletion>())
        try (appModel ?? AppModel()).undo(
            values.quest, personID: values.person.id,
            household: values.household, completions: completions,
            context: values.context)
        NotificationCenter.default.post(
            name: .kyndynAutomaticSyncRequested,
            object: nil,
            userInfo: ["trigger": AutomaticSyncTrigger.localMutation.rawValue])
        return "Undid \(values.quest.title) for \(values.person.name)."
    }

    private func selectedPersonID() throws -> UUID {
        let context = try requiredContext()
        if let selected = try context.fetch(
            FetchDescriptor<LocalDeviceSettings>()).first?.selectedPersonID {
            return selected
        }
        guard let first = try context.fetch(FetchDescriptor<Person>()).first(
            where: { $0.deletedAt == nil })?.id else {
            throw KyndynIntentError.personUnavailable
        }
        return first
    }

    private func requiredContext() throws -> ModelContext {
        guard let context else { throw KyndynIntentError.storeUnavailable }
        return context
    }

    private func resolve(_ occurrenceID: String) throws -> (
        context: ModelContext, household: Household, person: Person,
        quest: Quest, entity: KyndynQuestOccurrenceEntity
    ) {
        guard let components = Self.components(from: occurrenceID) else {
            throw KyndynIntentError.occurrenceUnavailable
        }
        let context = try requiredContext()
        guard let household = try context.fetch(
            FetchDescriptor<Household>()).first,
              let person = try context.fetch(FetchDescriptor<Person>()).first(
                where: { $0.id == components.personID && $0.deletedAt == nil }),
              let quest = try context.fetch(FetchDescriptor<Quest>()).first(
                where: { $0.id == components.questID && $0.deletedAt == nil }),
              let entity = try occurrences(
                ids: [occurrenceID], includeCompleted: true).first else {
            throw KyndynIntentError.occurrenceUnavailable
        }
        guard ProgressionEngine.occurrenceKey(
            for: quest, on: .now,
            timeZoneIdentifier: household.timeZoneIdentifier) == components.day
        else { throw KyndynIntentError.occurrenceUnavailable }
        return (context, household, person, quest, entity)
    }

    private static func occurrenceID(
        questID: UUID, personID: UUID, day: String
    ) -> String {
        "\(questID.uuidString.lowercased())|\(personID.uuidString.lowercased())|\(day)"
    }

    private static func components(from value: String)
        -> (questID: UUID, personID: UUID, day: String)? {
        let values = value.split(separator: "|", omittingEmptySubsequences: false)
        guard values.count == 3,
              let questID = UUID(uuidString: String(values[0])),
              let personID = UUID(uuidString: String(values[1])),
              !values[2].isEmpty else { return nil }
        return (questID, personID, String(values[2]))
    }
}
