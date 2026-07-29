import Foundation
import SwiftData
import SwiftUI

enum KyndynValidationError: LocalizedError, Equatable {
    case emptyName, nameTooLong, emptyTitle, titleTooLong, detailTooLong
    case invalidXP, noParticipants, noWeekdays, lastParent, archivedParticipant

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Enter a name."
        case .nameTooLong: return "Keep names to 40 characters or fewer."
        case .emptyTitle: return "Give the quest a title."
        case .titleTooLong: return "Keep quest titles to 80 characters or fewer."
        case .detailTooLong: return "Keep quest notes to 300 characters or fewer."
        case .invalidXP: return "XP must be between 1 and 500."
        case .noParticipants: return "Choose at least one active person."
        case .noWeekdays: return "Choose at least one weekday."
        case .lastParent: return "Add or promote another active parent before archiving the last parent."
        case .archivedParticipant: return "Archived people can’t receive new quest assignments."
        }
    }
}

struct PersonDraft {
    var name = ""
    var role: ProfileRole = .child
    var colorHex = "#6F2DBD"
    var companionID = "spark"
}

struct QuestDraft {
    var title = ""
    var detail = ""
    var xp = 10
    var participantIDs = Set<UUID>()
    var completionMode: QuestCompletionMode = .individual
    var scheduleKind: ScheduleKind = .oneTime
    var weekdays = Set<Int>()
    var startDate = Date()
    var hasDueDate = false
    var dueDate = Date()
    var hasDueTime = false
    var dueTime = Date()
}

enum LifecycleRules {
    static func validate(person draft: PersonDraft) throws -> String {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw KyndynValidationError.emptyName }
        guard name.count <= 40 else { throw KyndynValidationError.nameTooLong }
        return name
    }

    static func canArchive(person: Person, people: [Person]) -> Bool {
        guard person.role == .parent else { return true }
        return people.filter { $0.deletedAt == nil && $0.role == .parent && $0.id != person.id }.isEmpty == false
    }

    static func validate(quest draft: QuestDraft, people: [Person]) throws -> (String, String) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = draft.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw KyndynValidationError.emptyTitle }
        guard title.count <= 80 else { throw KyndynValidationError.titleTooLong }
        guard detail.count <= 300 else { throw KyndynValidationError.detailTooLong }
        guard (1...500).contains(draft.xp) else { throw KyndynValidationError.invalidXP }
        guard !draft.participantIDs.isEmpty else { throw KyndynValidationError.noParticipants }
        let active = Set(people.filter { $0.deletedAt == nil }.map(\.id))
        guard draft.participantIDs.isSubset(of: active) else { throw KyndynValidationError.archivedParticipant }
        if draft.scheduleKind == .weekly && draft.weekdays.isEmpty { throw KyndynValidationError.noWeekdays }
        return (title, detail)
    }
}

@MainActor
@Observable final class AppModel {
    var selectedPersonID: UUID?
    var selectedTab = 0
    var errorMessage: String?
    var isPreparing = true
    @ObservationIgnored private let notificationScheduler: NotificationScheduling

    init(notificationScheduler: NotificationScheduling = UserNotificationScheduler()) {
        self.notificationScheduler = notificationScheduler
    }

    func finishedPreparing() { isPreparing = false }

    @discardableResult
    func ensureLocalDeviceSettings(in context: ModelContext) throws
        -> LocalDeviceSettings {
        if let existing = try context.fetch(
            FetchDescriptor<LocalDeviceSettings>()).first {
            return existing
        }
        let settings = LocalDeviceSettings()
        context.insert(settings)
        try context.save()
        return settings
    }

    func seedSample(into context: ModelContext) throws {
        let household = Household(name: "kyndyn Family", timeZoneIdentifier: TimeZone.current.identifier, rewardTitle: "Family Movie Night", rewardGoalXP: 300)
        context.insert(household)
        context.insert(HouseholdSettings(householdID: household.id))
        let device = LocalDeviceSettings()
        context.insert(device)
        let maya = Person(householdID: household.id, name: "Maya", role: .parent, colorHex: "#6F2DBD", companionID: "spark")
        let leo = Person(householdID: household.id, name: "Leo", role: .child, colorHex: "#00A6A6", companionID: "orbit")
        let zoe = Person(householdID: household.id, name: "Zoe", role: .child, colorHex: "#F26B5B", companionID: "pixel")
        [maya, leo, zoe].forEach(context.insert)
        context.insert(Quest(householdID: household.id, title: "Make your bed", detail: "Start the day with a fresh space.", xp: 10, participantIDs: [leo.id], scheduleKind: .daily))
        context.insert(Quest(householdID: household.id, title: "Clear the dinner table", detail: "Everyone checks in when their part is done.", xp: 15, participantIDs: [maya.id, leo.id, zoe.id], completionMode: .sharedAll, scheduleKind: .daily))
        context.insert(Quest(householdID: household.id, title: "Water the plants", xp: 20, participantIDs: [zoe.id], scheduleKind: .weekly, weekdays: [3, 6]))
        device.selectedPersonID = leo.id
        device.devicePersonID = leo.id
        try context.save()
        selectedPersonID = leo.id
    }

    func createPerson(_ draft: PersonDraft, householdID: UUID, context: ModelContext) throws {
        let name = try LifecycleRules.validate(person: draft)
        let person = Person(householdID: householdID, name: name, role: draft.role,
                            colorHex: draft.colorHex, companionID: draft.companionID)
        context.insert(person)
        try context.save()
        try SyncQueue.enqueue(SyncSnapshot.person(person), operation: .createOrUpdate,
                              context: context)
        refreshReminders(context: context)
    }

    func updatePerson(_ person: Person, draft: PersonDraft, context: ModelContext) throws {
        person.name = try LifecycleRules.validate(person: draft)
        person.role = draft.role
        person.colorHex = draft.colorHex
        person.companionID = draft.companionID
        try context.save()
        try SyncQueue.enqueue(SyncSnapshot.person(person), operation: .createOrUpdate,
                              context: context)
        refreshReminders(context: context)
    }

    func archivePerson(_ person: Person, people: [Person], quests: [Quest], context: ModelContext) throws {
        guard LifecycleRules.canArchive(person: person, people: people) else { throw KyndynValidationError.lastParent }
        let affectedQuestIDs = Set(quests.filter {
            $0.deletedAt == nil && $0.participantIDs.contains(person.id)
        }.map(\.id))
        person.deletedAt = .now
        for quest in quests where quest.deletedAt == nil {
            quest.participantIDs.removeAll { $0 == person.id }
            if quest.participantIDs.isEmpty { quest.deletedAt = .now }
            if quest.participantIDs.count == 1 { quest.completionMode = .individual }
        }
        if selectedPersonID == person.id { selectedPersonID = nil }
        try context.save()
        try SyncQueue.enqueue(SyncSnapshot.person(person), operation: .archive,
                              context: context)
        for quest in quests where affectedQuestIDs.contains(quest.id) {
            for envelope in SyncSnapshot.quest(quest) {
                try SyncQueue.enqueue(envelope,
                    operation: quest.deletedAt == nil ? .createOrUpdate : .archive,
                    context: context)
            }
        }
        refreshReminders(context: context)
    }

    func restorePerson(_ person: Person, context: ModelContext) throws {
        person.deletedAt = nil
        try context.save()
        try SyncQueue.enqueue(SyncSnapshot.person(person), operation: .createOrUpdate,
                              context: context)
        refreshReminders(context: context)
    }

    func createQuest(_ draft: QuestDraft, household: Household, people: [Person], context: ModelContext) throws {
        let (title, detail) = try LifecycleRules.validate(quest: draft, people: people)
        let quest = Quest(householdID: household.id, title: title, detail: detail, xp: draft.xp,
                          participantIDs: Array(draft.participantIDs),
                          completionMode: draft.participantIDs.count == 1 ? .individual : draft.completionMode,
                          scheduleKind: draft.scheduleKind, weekdays: Array(draft.weekdays).sorted(),
                          startDate: draft.startDate, dueAt: dueAt(draft, household: household))
        context.insert(quest)
        try context.save()
        for envelope in SyncSnapshot.quest(quest) {
            try SyncQueue.enqueue(envelope, operation: .createOrUpdate, context: context)
        }
        refreshReminders(context: context)
    }

    func updateQuest(_ quest: Quest, draft: QuestDraft, household: Household, people: [Person], context: ModelContext) throws {
        let (title, detail) = try LifecycleRules.validate(quest: draft, people: people)
        quest.title = title
        quest.detail = detail
        quest.xp = draft.xp
        quest.participantIDs = Array(draft.participantIDs)
        quest.completionMode = draft.participantIDs.count == 1 ? .individual : draft.completionMode
        quest.scheduleKind = draft.scheduleKind
        quest.weekdays = Array(draft.weekdays).sorted()
        quest.startDate = draft.startDate
        quest.dueAt = dueAt(draft, household: household)
        try context.save()
        for envelope in SyncSnapshot.quest(quest) {
            try SyncQueue.enqueue(envelope, operation: .createOrUpdate, context: context)
        }
        refreshReminders(context: context)
    }

    func archiveQuest(_ quest: Quest, context: ModelContext) throws {
        quest.deletedAt = .now
        try context.save()
        for envelope in SyncSnapshot.quest(quest) {
            try SyncQueue.enqueue(envelope, operation: .archive, context: context)
        }
        refreshReminders(context: context)
    }

    func restoreQuest(_ quest: Quest, context: ModelContext) throws {
        quest.deletedAt = nil
        try context.save()
        for envelope in SyncSnapshot.quest(quest) {
            try SyncQueue.enqueue(envelope, operation: .createOrUpdate, context: context)
        }
        refreshReminders(context: context)
    }

    private func dueAt(_ draft: QuestDraft, household: Household) -> Date? {
        guard draft.hasDueDate else { return nil }
        let calendar = ProgressionEngine.calendar(timeZoneIdentifier: household.timeZoneIdentifier)
        let time = draft.hasDueTime ? calendar.dateComponents([.hour, .minute], from: draft.dueTime) : DateComponents(hour: 23, minute: 59)
        var date = calendar.dateComponents([.year, .month, .day], from: draft.dueDate)
        date.hour = time.hour; date.minute = time.minute
        return calendar.date(from: date)
    }

    func complete(_ quest: Quest, personID: UUID, household: Household, completions: [QuestCompletion], context: ModelContext, now: Date = .now) throws {
        guard quest.deletedAt == nil, quest.participantIDs.contains(personID) else { return }
        guard let occurrence = ProgressionEngine.occurrenceKey(for: quest, on: now, timeZoneIdentifier: household.timeZoneIdentifier) else { return }
        guard !completions.contains(where: { $0.questID == quest.id && $0.personID == personID && $0.occurrenceDay == occurrence && $0.reversedAt == nil }) else { return }
        let overdue = ProgressionEngine.overdueDays(for: quest, now: now, timeZoneIdentifier: household.timeZoneIdentifier)
        let completion = QuestCompletion(householdID: household.id, questID: quest.id,
                                         personID: personID, occurrenceDay: occurrence,
                                         completedAt: now,
                                         awardedXP: ProgressionEngine.effectiveXP(
                                            base: quest.xp, overdueDays: overdue))
        context.insert(completion)
        try context.save()
        try SyncQueue.enqueue(SyncSnapshot.completion(completion),
                              operation: .createOrUpdate, context: context)
    }

    func undo(_ quest: Quest, personID: UUID, household: Household, completions: [QuestCompletion], context: ModelContext, now: Date = .now) throws {
        guard let occurrence = ProgressionEngine.occurrenceKey(for: quest, on: now, timeZoneIdentifier: household.timeZoneIdentifier) else { return }
        let completion = completions.filter {
            $0.questID == quest.id && $0.personID == personID &&
            $0.occurrenceDay == occurrence && $0.reversedAt == nil
        }.max { $0.completedAt < $1.completedAt }
        completion?.reversedAt = now
        try context.save()
        if let completion {
            try SyncQueue.enqueue(SyncSnapshot.completion(completion),
                                  operation: .createOrUpdate, context: context)
        }
    }

    func refreshReminders(context: ModelContext) {
        Task { @MainActor in
            guard let household = try? context.fetch(FetchDescriptor<Household>()).first,
                  let setting = try? context.fetch(FetchDescriptor<LocalDeviceSettings>()).first else { return }
            let quests = (try? context.fetch(FetchDescriptor<Quest>())) ?? []
            let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
            let candidates = ReminderRules.candidates(quests: quests, people: people, settings: setting,
                                                       household: household, now: .now)
            try? await notificationScheduler.replaceKyndynReminders(with: candidates)
        }
    }
}
