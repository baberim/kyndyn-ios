import Foundation
import CryptoKit
import SwiftData
import SwiftUI

enum KyndynValidationError: LocalizedError, Equatable {
    case emptyName, nameTooLong, emptyTitle, titleTooLong, detailTooLong
    case invalidXP, noParticipants, noWeekdays, invalidWeekdays
    case invalidRepeatInterval, deadlineBeforeStart, lastParent, archivedParticipant
    case emptyRewardTitle, rewardTitleTooLong, invalidRewardTarget
    case emptyBroadcastMessage, broadcastMessageTooLong, broadcastExpired

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
        case .invalidWeekdays: return "Choose valid weekdays for this quest."
        case .invalidRepeatInterval: return "Choose every week or every other week."
        case .deadlineBeforeStart: return "The due date must be on or after the start date."
        case .lastParent: return "Add or promote another active parent before archiving the last parent."
        case .archivedParticipant: return "Archived people can’t receive new quest assignments."
        case .emptyRewardTitle: return "Enter a family reward."
        case .rewardTitleTooLong: return "Keep family rewards to 80 characters or fewer."
        case .invalidRewardTarget: return "The family XP goal must be between 1 and 1,000,000."
        case .emptyBroadcastMessage: return "Enter an announcement message."
        case .broadcastMessageTooLong:
            return "Keep announcement messages to 500 characters or fewer."
        case .broadcastExpired:
            return "Choose an expiration time in the future."
        }
    }
}

struct PersonDraft {
    var name = ""
    var role: ProfileRole = .child
    var colorHex = "#6F2DBD"
    var companionID = "spark"
    var startingXPAdjustment = 0
}

struct QuestDraft {
    var title = ""
    var detail = ""
    var xp = 10
    var participantIDs = Set<UUID>()
    var completionMode: QuestCompletionMode = .individual
    var scheduleKind: ScheduleKind = .oneTime
    var weekdays = Set<Int>()
    var repeatIntervalWeeks = 1
    var startDate = Date()
    var hasDueDate = false
    var dueDate = Date()
    var hasDueTime = false
    var dueTime = Date()
    var reminderEnabled = false
    var reminderTime = Date()
}

struct FamilyBroadcastDraft {
    var title = "Family update"
    var message = ""
    var expiresAt: Date? = Calendar.current.date(
        byAdding: .day, value: 1, to: .now)
}

enum CompletionIdentity {
    static func id(questID: UUID, personID: UUID, occurrenceDay: String) -> UUID {
        let value = "com.kyndynfamily.completion.v1:\(questID.uuidString.lowercased()):\(personID.uuidString.lowercased()):\(occurrenceDay)"
        var bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

struct HouseholdSetupDraft {
    var householdName = ""
    var timeZoneIdentifier = TimeZone.current.identifier
    var parent = PersonDraft(name: "", role: .parent)
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

    static func validateSchedule(_ draft: QuestDraft,
                                 timeZoneIdentifier: String) throws {
        if draft.scheduleKind == .weekly {
            guard !draft.weekdays.isEmpty else {
                throw KyndynValidationError.noWeekdays
            }
            guard draft.weekdays.allSatisfy((1...7).contains) else {
                throw KyndynValidationError.invalidWeekdays
            }
            guard [1, 2].contains(draft.repeatIntervalWeeks) else {
                throw KyndynValidationError.invalidRepeatInterval
            }
        } else if draft.repeatIntervalWeeks != 1 {
            throw KyndynValidationError.invalidRepeatInterval
        }

        guard draft.hasDueDate else { return }
        let calendar = ProgressionEngine.calendar(
            timeZoneIdentifier: timeZoneIdentifier)
        guard calendar.startOfDay(for: draft.dueDate) >=
                calendar.startOfDay(for: draft.startDate) else {
            throw KyndynValidationError.deadlineBeforeStart
        }
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
        household.isSample = true
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

    @discardableResult
    func createHousehold(_ draft: HouseholdSetupDraft,
                         context: ModelContext) throws -> Household {
        let name = draft.householdName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw KyndynValidationError.emptyName }
        guard name.count <= 80 else { throw KyndynValidationError.nameTooLong }
        guard TimeZone(identifier: draft.timeZoneIdentifier) != nil else {
            throw HouseholdTransferError.malformed(
                "Choose a recognized household time zone.")
        }
        var parentDraft = draft.parent
        parentDraft.role = .parent
        let parentName = try LifecycleRules.validate(person: parentDraft)
        let household = Household(
            name: name, timeZoneIdentifier: draft.timeZoneIdentifier)
        household.isSample = false
        let parent = Person(
            householdID: household.id, name: parentName, role: .parent,
            colorHex: parentDraft.colorHex,
            companionID: parentDraft.companionID)
        let shared = HouseholdSettings(householdID: household.id)
        let device = LocalDeviceSettings()
        device.selectedPersonID = parent.id
        device.devicePersonID = parent.id
        context.insert(household)
        context.insert(parent)
        context.insert(shared)
        context.insert(device)
        try context.save()
        selectedPersonID = parent.id
        return household
    }

    func deleteLocalSampleHousehold(_ household: Household,
                                    context: ModelContext) throws {
        guard household.isSample else {
            throw HouseholdTransferError.malformed(
                "Only a sample household can be removed here.")
        }
        let states = try context.fetch(FetchDescriptor<HouseholdCloudState>())
            .filter { $0.householdID == household.id }
        guard states.allSatisfy({ $0.mode == .localOnly }) else {
            throw HouseholdTransferError.malformed(
                "Turn off or resolve family sharing before removing this sample. Cloud data is never silently deleted.")
        }
        let questIDs = Set(try context.fetch(FetchDescriptor<Quest>())
            .filter { $0.householdID == household.id }.map(\.id))
        try context.fetch(FetchDescriptor<Person>())
            .filter { $0.householdID == household.id }.forEach(context.delete)
        try context.fetch(FetchDescriptor<Quest>())
            .filter { $0.householdID == household.id }.forEach(context.delete)
        try context.fetch(FetchDescriptor<QuestCompletion>())
            .filter { $0.householdID == household.id }.forEach(context.delete)
        try context.fetch(FetchDescriptor<RewardGoal>())
            .filter { $0.householdID == household.id }.forEach(context.delete)
        try context.fetch(FetchDescriptor<HouseholdSettings>())
            .filter { $0.householdID == household.id }.forEach(context.delete)
        try context.fetch(FetchDescriptor<LocalQuestReminder>())
            .filter { questIDs.contains($0.questID) }.forEach(context.delete)
        try context.fetch(FetchDescriptor<HouseholdCloudState>())
            .filter { $0.householdID == household.id }.forEach(context.delete)
        try context.fetch(FetchDescriptor<SyncRecordMetadata>())
            .filter { $0.householdID == household.id }.forEach(context.delete)
        try context.fetch(FetchDescriptor<PendingSyncMutation>())
            .filter { $0.householdID == household.id }.forEach(context.delete)
        try context.fetch(FetchDescriptor<SyncConflict>())
            .filter { $0.householdID == household.id }.forEach(context.delete)
        context.delete(household)
        try context.fetch(FetchDescriptor<LocalDeviceSettings>())
            .forEach(context.delete)
        try context.save()
        selectedPersonID = nil
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
        person.startingXPAdjustment = draft.startingXPAdjustment
        try context.save()
        try SyncQueue.enqueue(SyncSnapshot.person(person), operation: .createOrUpdate,
                              context: context)
        if let household = try context.fetch(FetchDescriptor<Household>())
            .first(where: { $0.id == person.householdID }) {
            try evaluateCollections(for: person.id, household: household,
                                    context: context)
        }
        refreshReminders(context: context)
    }

    func grantCompanion(_ id: String, to person: Person, context: ModelContext) throws {
        guard CollectionCatalog.companionIDs.contains(id) else { return }
        person.earnedCompanionIDs = CollectionCatalog.normalizedCompanions(
            person.earnedCompanionIDs + [id])
        try context.save()
        try SyncQueue.enqueue(SyncSnapshot.person(person), operation: .createOrUpdate,
                              context: context)
    }

    func grantBackground(_ id: String, to person: Person, context: ModelContext) throws {
        guard CollectionCatalog.backgrounds.contains(where: { $0.id == id }) else { return }
        person.earnedBackgroundIDs = CollectionCatalog.normalizedBackgrounds(
            person.earnedBackgroundIDs + [id])
        try context.save()
        try SyncQueue.enqueue(SyncSnapshot.person(person), operation: .createOrUpdate,
                              context: context)
    }

    func acknowledgeUnlock(_ id: String, for person: Person, context: ModelContext) throws {
        person.pendingUnlockIDs.removeAll { $0 == id }
        try context.save()
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

    @discardableResult
    func createQuest(_ draft: QuestDraft, household: Household, people: [Person], context: ModelContext) throws -> Quest {
        let (title, detail) = try LifecycleRules.validate(quest: draft, people: people)
        try LifecycleRules.validateSchedule(
            draft, timeZoneIdentifier: household.timeZoneIdentifier)
        let quest = Quest(householdID: household.id, title: title, detail: detail, xp: draft.xp,
                          participantIDs: Array(draft.participantIDs),
                          completionMode: draft.participantIDs.count == 1 ? .individual : draft.completionMode,
                          scheduleKind: draft.scheduleKind, weekdays: Array(draft.weekdays).sorted(),
                          repeatIntervalWeeks: draft.repeatIntervalWeeks,
                          startDate: draft.startDate, dueAt: dueAt(draft, household: household))
        context.insert(quest)
        try context.save()
        for envelope in SyncSnapshot.quest(quest) {
            try SyncQueue.enqueue(envelope, operation: .createOrUpdate, context: context)
        }
        try updateReminder(for: quest, draft: draft, household: household,
                           context: context)
        refreshReminders(context: context)
        return quest
    }

    func updateQuest(_ quest: Quest, draft: QuestDraft, household: Household, people: [Person], context: ModelContext) throws {
        let (title, detail) = try LifecycleRules.validate(quest: draft, people: people)
        try LifecycleRules.validateSchedule(
            draft, timeZoneIdentifier: household.timeZoneIdentifier)
        quest.title = title
        quest.detail = detail
        quest.xp = draft.xp
        quest.participantIDs = Array(draft.participantIDs)
        quest.completionMode = draft.participantIDs.count == 1 ? .individual : draft.completionMode
        quest.scheduleKind = draft.scheduleKind
        quest.weekdays = Array(draft.weekdays).sorted()
        quest.repeatIntervalWeeks = draft.repeatIntervalWeeks
        quest.startDate = draft.startDate
        quest.dueAt = dueAt(draft, household: household)
        try context.save()
        for envelope in SyncSnapshot.quest(quest) {
            try SyncQueue.enqueue(envelope, operation: .createOrUpdate, context: context)
        }
        try updateReminder(for: quest, draft: draft, household: household,
                           context: context)
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

    @discardableResult
    func repairQuestSchedules(
        _ quests: [Quest], household: Household, context: ModelContext
    ) throws -> Int {
        var repaired = [Quest]()
        for quest in quests where QuestScheduleDiagnostics.applySafeRepairs(
            to: quest, timeZoneIdentifier: household.timeZoneIdentifier
        ) {
            repaired.append(quest)
        }
        guard !repaired.isEmpty else { return 0 }
        try context.save()
        for quest in repaired {
            for envelope in SyncSnapshot.quest(quest) {
                try SyncQueue.enqueue(envelope, operation: .createOrUpdate,
                                      context: context)
            }
        }
        refreshReminders(context: context)
        return repaired.count
    }

    func saveFamilyReward(
        title rawTitle: String, targetXP: Int, resetProgress: Bool,
        household: Household, goals: [RewardGoal], context: ModelContext,
        now: Date = .now
    ) throws {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw KyndynValidationError.emptyRewardTitle }
        guard title.count <= 80 else {
            throw KyndynValidationError.rewardTitleTooLong
        }
        guard (1...1_000_000).contains(targetXP) else {
            throw KyndynValidationError.invalidRewardTarget
        }

        let active = goals.filter {
            $0.householdID == household.id && $0.deletedAt == nil
        }
        var archived = [RewardGoal]()
        let goal: RewardGoal
        if resetProgress {
            for value in active {
                value.deletedAt = now
                archived.append(value)
            }
            goal = RewardGoal(
                householdID: household.id, title: title, targetXP: targetXP)
            goal.createdAt = now
            context.insert(goal)
        } else if let existing = ProgressionEngine.currentRewardGoal(
            active, householdID: household.id) {
            existing.title = title
            existing.targetXP = targetXP
            goal = existing
        } else {
            goal = RewardGoal(
                householdID: household.id, title: title, targetXP: targetXP)
            // Adopting the explicit RewardGoal model must not erase progress
            // earned by an existing household.
            goal.createdAt = household.createdAt
            context.insert(goal)
        }

        household.rewardTitle = title
        household.rewardGoalXP = targetXP
        try context.save()
        for value in archived {
            try SyncQueue.enqueue(
                SyncSnapshot.reward(value), operation: .archive,
                context: context)
        }
        try SyncQueue.enqueue(
            SyncSnapshot.reward(goal), operation: .createOrUpdate,
            context: context)
        try SyncQueue.enqueue(
            SyncSnapshot.household(household), operation: .createOrUpdate,
            context: context)
    }

    @discardableResult
    func saveBroadcast(
        _ existing: FamilyBroadcast?, draft: FamilyBroadcastDraft,
        household: Household, context: ModelContext, now: Date = .now
    ) throws -> FamilyBroadcast {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = draft.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw KyndynValidationError.emptyTitle }
        guard title.count <= 80 else { throw KyndynValidationError.titleTooLong }
        guard !message.isEmpty else {
            throw KyndynValidationError.emptyBroadcastMessage
        }
        guard message.count <= 500 else {
            throw KyndynValidationError.broadcastMessageTooLong
        }
        if let expiresAt = draft.expiresAt, expiresAt <= now {
            throw KyndynValidationError.broadcastExpired
        }
        let value = existing ?? FamilyBroadcast(
            householdID: household.id, title: title, message: message,
            createdAt: now)
        value.title = title
        value.message = message
        value.expiresAt = draft.expiresAt
        value.updatedAt = now
        value.deletedAt = nil
        if existing == nil { context.insert(value) }
        try context.save()
        try SyncQueue.enqueue(
            SyncSnapshot.broadcast(value), operation: .createOrUpdate,
            context: context)
        NotificationCenter.default.post(
            name: .kyndynAutomaticSyncRequested, object: nil,
            userInfo: ["trigger": AutomaticSyncTrigger.localMutation.rawValue])
        return value
    }

    func archiveBroadcast(
        _ broadcast: FamilyBroadcast, context: ModelContext, now: Date = .now
    ) throws {
        broadcast.deletedAt = now
        broadcast.updatedAt = now
        try context.save()
        try SyncQueue.enqueue(
            SyncSnapshot.broadcast(broadcast), operation: .archive,
            context: context)
        NotificationCenter.default.post(
            name: .kyndynAutomaticSyncRequested, object: nil,
            userInfo: ["trigger": AutomaticSyncTrigger.localMutation.rawValue])
    }

    private func dueAt(_ draft: QuestDraft, household: Household) -> Date? {
        guard draft.hasDueDate else { return nil }
        let calendar = ProgressionEngine.calendar(timeZoneIdentifier: household.timeZoneIdentifier)
        let time = draft.hasDueTime ? calendar.dateComponents([.hour, .minute], from: draft.dueTime) : DateComponents(hour: 23, minute: 59)
        var date = calendar.dateComponents([.year, .month, .day], from: draft.dueDate)
        date.hour = time.hour; date.minute = time.minute
        return calendar.date(from: date)
    }

    private func updateReminder(for quest: Quest, draft: QuestDraft,
                                household: Household,
                                context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<LocalQuestReminder>())
            .first { $0.questID == quest.id }
        let calendar = ProgressionEngine.calendar(
            timeZoneIdentifier: household.timeZoneIdentifier)
        let components = calendar.dateComponents([.hour, .minute],
                                                  from: draft.reminderTime)
        let value = existing ?? LocalQuestReminder(
            questID: quest.id, isEnabled: draft.reminderEnabled,
            hour: components.hour ?? 16, minute: components.minute ?? 0)
        value.isEnabled = draft.reminderEnabled
        value.hour = components.hour ?? 16
        value.minute = components.minute ?? 0
        if existing == nil { context.insert(value) }
        try context.save()
    }

    func complete(_ quest: Quest, personID: UUID, household: Household, completions: [QuestCompletion], context: ModelContext, now: Date = .now) throws {
        guard quest.deletedAt == nil, quest.participantIDs.contains(personID) else { return }
        guard let occurrence = ProgressionEngine.occurrenceKey(for: quest, on: now, timeZoneIdentifier: household.timeZoneIdentifier) else { return }
        let completionID = CompletionIdentity.id(
            questID: quest.id, personID: personID, occurrenceDay: occurrence)
        let stored = try context.fetch(FetchDescriptor<QuestCompletion>())
        if let existing = stored.first(where: {
            $0.id == completionID ||
            ($0.questID == quest.id && $0.personID == personID &&
             $0.occurrenceDay == occurrence)
        }) {
            guard existing.reversedAt != nil else { return }
            existing.completedAt = now
            existing.awardedXP = ProgressionEngine.effectiveXP(
                base: quest.xp,
                overdueDays: ProgressionEngine.overdueDays(
                    for: quest, now: now,
                    timeZoneIdentifier: household.timeZoneIdentifier))
            existing.reversedAt = nil
            try context.save()
            try SyncQueue.enqueue(SyncSnapshot.completion(existing),
                                  operation: .createOrUpdate, context: context)
            try evaluateCollections(for: personID, household: household,
                                    context: context, now: now)
            refreshReminders(context: context)
            return
        }
        let overdue = ProgressionEngine.overdueDays(for: quest, now: now, timeZoneIdentifier: household.timeZoneIdentifier)
        let completion = QuestCompletion(id: completionID,
                                         householdID: household.id, questID: quest.id,
                                         personID: personID, occurrenceDay: occurrence,
                                         completedAt: now,
                                         awardedXP: ProgressionEngine.effectiveXP(
                                            base: quest.xp, overdueDays: overdue))
        context.insert(completion)
        try context.save()
        try SyncQueue.enqueue(SyncSnapshot.completion(completion),
                              operation: .createOrUpdate, context: context)
        try evaluateCollections(for: personID, household: household,
                                context: context, now: now)
        refreshReminders(context: context)
    }

    func evaluateCollections(
        for personID: UUID, household: Household, context: ModelContext,
        now: Date = .now
    ) throws {
        let people = try context.fetch(FetchDescriptor<Person>())
        guard let person = people.first(where: { $0.id == personID }) else { return }
        let completions = try context.fetch(FetchDescriptor<QuestCompletion>())
        let goals = try context.fetch(FetchDescriptor<RewardGoal>())
        let progress = ProgressionEngine.progress(
            personID: personID, completions: completions, now: now,
            timeZoneIdentifier: household.timeZoneIdentifier,
            startingXPAdjustment: person.startingXPAdjustment)
        let goal = ProgressionEngine.currentRewardGoal(goals, householdID: household.id)
        let rewardReached = goal.map {
            ProgressionEngine.rewardXP(completions, goal: $0) >= $0.targetXP
        } ?? false
        let companions = CollectionCatalog.normalizedCompanions(
            person.earnedCompanionIDs + RecognitionEngine.earnedCompanionIDs(
                progress: progress, familyRewardReached: rewardReached))
        let backgrounds = CollectionCatalog.normalizedBackgrounds(
            person.earnedBackgroundIDs + RecognitionEngine.earnedBackgroundIDs(
                progress: progress, familyRewardReached: rewardReached))
        let badges = RecognitionEngine.badges(
            progress: progress, familyRewardReached: rewardReached)
        let newlyEarnedBadges = badges.filter {
            !person.earnedBadgeIDs.contains($0.id)
        }.map { "badge:\($0.id)" }
        let newlyEarned = companions.filter { !person.earnedCompanionIDs.contains($0) }
            .map { "companion:\($0)" }
            + backgrounds.filter { !person.earnedBackgroundIDs.contains($0) }
                .map { "background:\($0)" }
            + newlyEarnedBadges
        person.earnedCompanionIDs = companions
        person.earnedBackgroundIDs = backgrounds
        person.earnedBadgeIDs = RecognitionEngine.normalizedBadges(
            person.earnedBadgeIDs + badges.map(\.id))
        person.pendingUnlockIDs = Array(Set(person.pendingUnlockIDs + newlyEarned))
        try context.save()
        if !newlyEarned.isEmpty {
            try SyncQueue.enqueue(SyncSnapshot.person(person),
                                  operation: .createOrUpdate, context: context)
        }
    }

    func undo(_ quest: Quest, personID: UUID, household: Household, completions: [QuestCompletion], context: ModelContext, now: Date = .now) throws {
        guard let occurrence = ProgressionEngine.occurrenceKey(for: quest, on: now, timeZoneIdentifier: household.timeZoneIdentifier) else { return }
        let stored = try context.fetch(FetchDescriptor<QuestCompletion>())
        let completion = stored.filter {
            $0.questID == quest.id && $0.personID == personID &&
            $0.occurrenceDay == occurrence && $0.reversedAt == nil
        }.max { $0.completedAt < $1.completedAt }
        completion?.reversedAt = now
        try context.save()
        if let completion {
            try SyncQueue.enqueue(SyncSnapshot.completion(completion),
                                  operation: .createOrUpdate, context: context)
        }
        refreshReminders(context: context)
    }

    func refreshReminders(context: ModelContext) {
        Task { @MainActor in
            guard let household = try? context.fetch(FetchDescriptor<Household>()).first,
                  let setting = try? context.fetch(FetchDescriptor<LocalDeviceSettings>()).first else { return }
            let quests = (try? context.fetch(FetchDescriptor<Quest>())) ?? []
            let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
            let completions = (try? context.fetch(
                FetchDescriptor<QuestCompletion>())) ?? []
            let reminders = (try? context.fetch(
                FetchDescriptor<LocalQuestReminder>())) ?? []
            let candidates = ReminderRules.candidates(quests: quests, people: people, settings: setting,
                                                       household: household,
                                                       completions: completions,
                                                       reminderPreferences: reminders,
                                                       now: .now)
            try? await notificationScheduler.replaceKyndynReminders(with: candidates)
        }
    }
}
