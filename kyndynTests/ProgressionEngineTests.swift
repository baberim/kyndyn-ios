import XCTest
import SwiftData
@testable import kyndyn

private final class MemoryHostedCredentialStore:
    HostedNotificationCredentialStoring, @unchecked Sendable {
    var value: HostedNotificationIdentity?
    init(_ value: HostedNotificationIdentity? = nil) { self.value = value }
    func load() -> HostedNotificationIdentity? { value }
    func save(_ identity: HostedNotificationIdentity) throws { value = identity }
    func remove() throws { value = nil }
}

final class HostedNotificationFoundationTests: XCTestCase {
    func testHostedIdentityRoundTripsWithoutDeviceTokenPayload() throws {
        let identity = HostedNotificationIdentity(
            role: .participant, householdID: UUID(), deviceID: UUID(),
            adminCapability: nil, enrollmentCapability: nil,
            deviceCapability: "device-capability")
        let data = try JSONEncoder().encode(identity)
        XCTAssertEqual(
            try JSONDecoder().decode(HostedNotificationIdentity.self, from: data),
            identity)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("deviceToken"))
    }

    func testCapabilitiesAreUniqueAndURLSafe() {
        let first = HostedNotificationServiceClient.randomCapability()
        let second = HostedNotificationServiceClient.randomCapability()
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.count, 43)
        XCTAssertNotNil(first.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression))
    }

    @MainActor func testCoordinatorRestoresOwnerRoleFromSecureStore() {
        let identity = HostedNotificationIdentity(
            role: .owner, householdID: UUID(), deviceID: UUID(),
            adminCapability: "admin", enrollmentCapability: "enroll",
            deviceCapability: nil)
        let coordinator = HostedNotificationCoordinator(
            store: MemoryHostedCredentialStore(identity))
        XCTAssertTrue(coordinator.isConnected)
        XCTAssertTrue(coordinator.isOwner)
        XCTAssertEqual(coordinator.status, "Waiting for Apple")
    }
}

final class DeviceContextPolicyTests: XCTestCase {
    func testWeatherCacheExpiresAfterThirtyMinutes() {
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertTrue(WeatherCachePolicy.isFresh(
            now.addingTimeInterval(-1_799), now: now))
        XCTAssertFalse(WeatherCachePolicy.isFresh(
            now.addingTimeInterval(-1_800), now: now))
        XCTAssertFalse(WeatherCachePolicy.isFresh(nil, now: now))
        XCTAssertFalse(WeatherCachePolicy.isFresh(
            now.addingTimeInterval(1), now: now))
    }
}

final class SystemIntelligenceTests: XCTestCase {
    @MainActor private func fixture() throws -> (
        ModelContainer, Household, Person, Quest, AppModel
    ) {
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: Household.self, Person.self, Quest.self,
            QuestCompletion.self, RewardGoal.self, FamilyBroadcast.self,
            Companion.self, Background.self, HouseholdSettings.self,
            LocalDeviceSettings.self, LocalQuestReminder.self,
            HouseholdImportReceipt.self, HouseholdCloudState.self,
            SyncRecordMetadata.self, PendingSyncMutation.self,
            SyncConflict.self, PendingShareInvitation.self,
            configurations: configuration)
        let household = Household(
            name: "Fictional Intent Family", timeZoneIdentifier: "UTC",
            rewardTitle: "Fictional Movie Night", rewardGoalXP: 100)
        let person = Person(
            householdID: household.id, name: "Avery", role: .child,
            colorHex: "#000000", companionID: "spark")
        let quest = Quest(
            householdID: household.id, title: "Put books away", xp: 10,
            participantIDs: [person.id], scheduleKind: .daily,
            startDate: .distantPast)
        let setting = LocalDeviceSettings()
        setting.selectedPersonID = person.id
        let goal = RewardGoal(
            householdID: household.id, title: household.rewardTitle,
            targetXP: household.rewardGoalXP)
        goal.createdAt = .distantPast
        let cloudState = HouseholdCloudState(householdID: household.id)
        cloudState.mode = .owner
        let context = container.mainContext
        context.insert(household)
        context.insert(person)
        context.insert(quest)
        context.insert(setting)
        context.insert(goal)
        context.insert(cloudState)
        try context.save()
        let app = AppModel()
        KyndynIntentStore.shared.configure(container: container, appModel: app)
        return (container, household, person, quest, app)
    }

    @MainActor func testIntentStoreReturnsPrivateHouseholdSummaries() throws {
        let (container, _, person, _, _) = try fixture()
        defer { KyndynIntentStore.shared.resetForTesting() }
        XCTAssertEqual(try KyndynIntentStore.shared.people().map(\.name),
                       ["Avery"])
        XCTAssertEqual(try KyndynIntentStore.shared.people(
            matching: "ave").map(\.name), ["Avery"])
        XCTAssertEqual(try KyndynIntentStore.shared.people(
            matching: "AVERY").map(\.name), ["Avery"])
        XCTAssertTrue(try KyndynIntentStore.shared.people(
            matching: "missing").isEmpty)
        XCTAssertEqual(try KyndynIntentStore.shared.occurrences(
            matching: "books", includeCompleted: true).count, 1)
        let today = try KyndynIntentStore.shared.todaySummary(
            personID: person.id)
        XCTAssertTrue(today.contains("Put books away"))
        XCTAssertEqual(try KyndynIntentStore.shared.rewardSummary(),
                       "Fictional Movie Night: 0 of 100 XP.")
        withExtendedLifetime(container) {}
    }

    @MainActor func testIntentCompletionAndExactUndoAreIdempotent() throws {
        let (container, _, _, _, _) = try fixture()
        defer { KyndynIntentStore.shared.resetForTesting() }
        let occurrence = try XCTUnwrap(
            KyndynIntentStore.shared.occurrences(
                includeCompleted: true).first)
        XCTAssertFalse(occurrence.isComplete)
        XCTAssertTrue(try KyndynIntentStore.shared.complete(
            occurrenceID: occurrence.id).contains("Completed"))
        XCTAssertThrowsError(try KyndynIntentStore.shared.complete(
            occurrenceID: occurrence.id)) {
            XCTAssertEqual($0 as? KyndynIntentError, .alreadyComplete)
        }
        XCTAssertEqual(try container.mainContext.fetch(
            FetchDescriptor<QuestCompletion>()).count, 1)
        XCTAssertTrue(try KyndynIntentStore.shared.undo(
            occurrenceID: occurrence.id).contains("Undid"))
        let completion = try XCTUnwrap(container.mainContext.fetch(
            FetchDescriptor<QuestCompletion>()).first)
        XCTAssertNotNil(completion.reversedAt)
        XCTAssertGreaterThan(try container.mainContext.fetch(
            FetchDescriptor<PendingSyncMutation>()).count, 0)
    }

    @MainActor func testSiriQuestDraftRequiresReviewWithoutCreatingQuest() throws {
        let (container, _, person, _, app) = try fixture()
        defer { KyndynIntentStore.shared.resetForTesting() }
        let dueDate = Date(timeIntervalSince1970: 2_000_000_000)
        try KyndynIntentStore.shared.prepareQuest(
            title: "  Clean your bedroom  ", personID: person.id,
            xp: 10, dueDate: dueDate)
        XCTAssertEqual(app.pendingSiriQuestDraft?.title,
                       "Clean your bedroom")
        XCTAssertEqual(app.pendingSiriQuestDraft?.personID, person.id)
        XCTAssertEqual(app.pendingSiriQuestDraft?.xp, 10)
        XCTAssertEqual(app.pendingSiriQuestDraft?.dueDate, dueDate)
        XCTAssertEqual(try container.mainContext.fetch(
            FetchDescriptor<Quest>()).count, 1,
            "Preparing a Siri draft must not create a quest.")
    }

    @MainActor func testSiriQuestDraftRejectsUnsafeValues() throws {
        let (container, _, person, _, _) = try fixture()
        defer { KyndynIntentStore.shared.resetForTesting() }
        XCTAssertThrowsError(try KyndynIntentStore.shared.prepareQuest(
            title: "   ", personID: person.id, xp: 10, dueDate: nil))
        XCTAssertThrowsError(try KyndynIntentStore.shared.prepareQuest(
            title: "Quest", personID: person.id, xp: 501, dueDate: nil))
        XCTAssertThrowsError(try KyndynIntentStore.shared.prepareQuest(
            title: "Quest", personID: UUID(), xp: 10, dueDate: nil))
        withExtendedLifetime(container) {}
    }
}

final class ProgressionEngineTests: XCTestCase {
    func testWeeklyInsightsSeparateCompletedMissedWaitingAndStartingXP() throws {
        let household = Household(
            name: "Fictional Insight Family", timeZoneIdentifier: "UTC")
        let person = Person(
            householdID: household.id, name: "Avery", role: .child,
            colorHex: "#6F2DBD", companionID: "spark")
        person.startingXPAdjustment = 250
        let quest = Quest(
            householdID: household.id, title: "Morning routine", xp: 10,
            participantIDs: [person.id], scheduleKind: .daily,
            startDate: ISO8601DateFormatter().date(from: "2026-08-10T00:00:00Z")!)
        let completion = QuestCompletion(
            householdID: household.id, questID: quest.id,
            personID: person.id, occurrenceDay: "2026-08-10",
            completedAt: ISO8601DateFormatter().date(from: "2026-08-10T12:00:00Z")!,
            awardedXP: 10)
        let now = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-12T12:00:00Z"))

        let result = InsightsEngine.week(
            containing: now, now: now, household: household,
            people: [person], quests: [quest], completions: [completion])

        XCTAssertEqual(result.completed, 1)
        XCTAssertEqual(result.notCompleted, 1)
        XCTAssertEqual(result.waiting, 1)
        XCTAssertEqual(result.xp, 10)
        XCTAssertEqual(result.people.first?.level, 3)
        XCTAssertEqual(result.people.first?.xp, 10)
    }

    func testWeeklyInsightsIgnoreUndoneAndFutureOccurrences() throws {
        let household = Household(
            name: "Fictional Insight Family", timeZoneIdentifier: "UTC")
        let person = Person(
            householdID: household.id, name: "Avery", role: .child,
            colorHex: "#6F2DBD", companionID: "spark")
        let quest = Quest(
            householdID: household.id, title: "Daily routine", xp: 15,
            participantIDs: [person.id], scheduleKind: .daily,
            startDate: ISO8601DateFormatter().date(from: "2026-08-10T00:00:00Z")!)
        let event = QuestCompletion(
            householdID: household.id, questID: quest.id,
            personID: person.id, occurrenceDay: "2026-08-10",
            completedAt: ISO8601DateFormatter().date(from: "2026-08-10T12:00:00Z")!,
            awardedXP: 15)
        event.reversedAt = ISO8601DateFormatter().date(from: "2026-08-10T13:00:00Z")!
        let now = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-10T18:00:00Z"))

        let result = InsightsEngine.week(
            containing: now, now: now, household: household,
            people: [person], quests: [quest], completions: [event])

        XCTAssertEqual(result.completed, 0)
        XCTAssertEqual(result.notCompleted, 0)
        XCTAssertEqual(result.waiting, 1)
        XCTAssertEqual(result.xp, 0)
    }

    func testStartingXPAdjustmentChangesXPAndLevelWithoutInventingHistory() {
        let household = Household(
            name: "Fictional Family", timeZoneIdentifier: "UTC")
        let person = Person(
            householdID: household.id, name: "Avery", role: .child,
            colorHex: "#6F2DBD", companionID: "spark")
        let quest = Quest(
            householdID: household.id, title: "Tidy books", xp: 25,
            participantIDs: [person.id])
        let completion = QuestCompletion(
            householdID: household.id, questID: quest.id,
            personID: person.id, occurrenceDay: "2026-08-11",
            completedAt: .now, awardedXP: 25)

        let progress = ProgressionEngine.progress(
            personID: person.id, completions: [completion], now: .now,
            timeZoneIdentifier: "UTC", startingXPAdjustment: 225)

        XCTAssertEqual(progress.xp, 250)
        XCTAssertEqual(progress.questXP, 25)
        XCTAssertEqual(progress.level, 3)
        XCTAssertEqual(progress.completedCount, 1)
        XCTAssertEqual(progress.currentStreak, 1)
        XCTAssertEqual(RecognitionEngine.badges(progress: progress).map(\.id),
                       ["first-step"])
    }

    func testEarnedStreakBadgeRemainsEarnedAfterStreakEnds() {
        let progress = PersonProgress(
            xp: 40, level: 1, currentStreak: 0, bestStreak: 1,
            completedCount: 4, questXP: 40)

        let badges = RecognitionEngine.badges(
            progress: progress, earnedBadgeIDs: ["streak-three"])

        XCTAssertTrue(badges.contains { $0.id == "streak-three" })
        XCTAssertFalse(badges.contains { $0.id == "streak-seven" })
    }

    func testBadgeMilestonesExplainCollectionUnlocks() {
        XCTAssertEqual(
            RecognitionEngine.badgeCollectionMilestones.map(\.badgeCount),
            [3, 5])
        XCTAssertEqual(
            RecognitionEngine.collectionMilestone(reachedWith: 3)?.itemNames,
            ["Aquarium background", "Cloud companion"])
        XCTAssertEqual(
            RecognitionEngine.collectionMilestone(reachedWith: 5)?.itemNames,
            ["Deer companion", "Moon Garden background"])
        XCTAssertNil(RecognitionEngine.collectionMilestone(reachedWith: 4))
    }

    @MainActor private func models() throws -> (ModelContainer, Household, Person, Quest) {
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: Household.self, Person.self, Quest.self, QuestCompletion.self,
            RewardGoal.self, LocalDeviceSettings.self, LocalQuestReminder.self,
            HouseholdCloudState.self, SyncRecordMetadata.self,
            PendingSyncMutation.self, configurations: configuration)
        let household = Household(name: "Fictional Test Family", timeZoneIdentifier: "America/New_York")
        let person = Person(householdID: household.id, name: "Avery", role: .child, colorHex: "#000000", companionID: "spark")
        let quest = Quest(householdID: household.id, title: "Test quest", xp: 10, participantIDs: [person.id], scheduleKind: .daily)
        quest.startDate = .distantPast
        return (container, household, person, quest)
    }

    func testLateXPPenaltyCapsAtHalf() {
        XCTAssertEqual(ProgressionEngine.effectiveXP(base: 20, overdueDays: 2), 16)
        XCTAssertEqual(ProgressionEngine.effectiveXP(base: 20, overdueDays: 9), 10)
    }

    @MainActor func testCompletionIsIdempotentAndUndoRecalculates() throws {
        let (container, household, person, quest) = try models()
        let context = container.mainContext
        context.insert(household); context.insert(person); context.insert(quest)
        let model = AppModel()
        let now = ISO8601DateFormatter().date(from: "2026-07-28T14:00:00Z")!
        try model.complete(quest, personID: person.id, household: household, completions: [], context: context, now: now)
        var events = try context.fetch(FetchDescriptor<QuestCompletion>())
        try model.complete(quest, personID: person.id, household: household, completions: events, context: context, now: now)
        events = try context.fetch(FetchDescriptor<QuestCompletion>())
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(ProgressionEngine.progress(personID: person.id, completions: events, now: now, timeZoneIdentifier: household.timeZoneIdentifier).xp, 10)
        try model.undo(quest, personID: person.id, household: household, completions: events, context: context, now: now)
        XCTAssertEqual(ProgressionEngine.familyXP(events), 0)
        XCTAssertNotNil(events.first?.reversedAt)
    }

    @MainActor func testRapidCompletionWithStaleQueryCannotDuplicateXP() throws {
        let (container, household, person, quest) = try models()
        let context = container.mainContext
        context.insert(household); context.insert(person); context.insert(quest)
        let model = AppModel()
        let now = ISO8601DateFormatter().date(
            from: "2026-07-28T14:00:00Z")!
        try model.complete(quest, personID: person.id, household: household,
                           completions: [], context: context, now: now)
        try model.complete(quest, personID: person.id, household: household,
                           completions: [], context: context, now: now)
        let events = try context.fetch(FetchDescriptor<QuestCompletion>())
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.id, CompletionIdentity.id(
            questID: quest.id, personID: person.id,
            occurrenceDay: "2026-07-28"))
        XCTAssertEqual(ProgressionEngine.familyXP(events), quest.xp)
    }

    func testCompletionIdentityConvergesAcrossDevices() {
        let questID = UUID()
        let personID = UUID()
        XCTAssertEqual(
            CompletionIdentity.id(questID: questID, personID: personID,
                                  occurrenceDay: "2026-08-03"),
            CompletionIdentity.id(questID: questID, personID: personID,
                                  occurrenceDay: "2026-08-03"))
        XCTAssertNotEqual(
            CompletionIdentity.id(questID: questID, personID: personID,
                                  occurrenceDay: "2026-08-03"),
            CompletionIdentity.id(questID: questID, personID: personID,
                                  occurrenceDay: "2026-08-04"))
    }

    @MainActor func testFamilyRewardResetStartsNewCounterWithoutRemovingXP()
        throws {
        let (container, household, person, quest) = try models()
        let context = container.mainContext
        let formatter = ISO8601DateFormatter()
        let before = formatter.date(from: "2026-08-01T12:00:00Z")!
        let resetAt = formatter.date(from: "2026-08-02T12:00:00Z")!
        let after = formatter.date(from: "2026-08-03T12:00:00Z")!
        household.createdAt = before.addingTimeInterval(-100)
        let first = QuestCompletion(
            householdID: household.id, questID: quest.id,
            personID: person.id, occurrenceDay: "2026-08-01",
            completedAt: before, awardedXP: 20)
        let second = QuestCompletion(
            householdID: household.id, questID: quest.id,
            personID: person.id, occurrenceDay: "2026-08-03",
            completedAt: after, awardedXP: 30)
        context.insert(household); context.insert(person); context.insert(quest)
        context.insert(first); context.insert(second)

        let model = AppModel()
        try model.saveFamilyReward(
            title: "Fictional Campout", targetXP: 250,
            resetProgress: false, household: household, goals: [],
            context: context, now: before)
        var goals = try context.fetch(FetchDescriptor<RewardGoal>())
        XCTAssertEqual(ProgressionEngine.rewardXP([first, second],
                                                  goal: goals.first), 50)

        try model.saveFamilyReward(
            title: "Fictional Pizza Night", targetXP: 100,
            resetProgress: true, household: household, goals: goals,
            context: context, now: resetAt)
        goals = try context.fetch(FetchDescriptor<RewardGoal>())
        let active = goals.first { $0.deletedAt == nil }
        XCTAssertEqual(active?.title, "Fictional Pizza Night")
        XCTAssertEqual(active?.targetXP, 100)
        XCTAssertEqual(ProgressionEngine.rewardXP([first, second], goal: active), 30)
        XCTAssertEqual(ProgressionEngine.familyXP([first, second]), 50)
        XCTAssertNotNil(goals.first { $0.deletedAt != nil })
        XCTAssertEqual(household.rewardTitle, "Fictional Pizza Night")
        XCTAssertEqual(household.rewardGoalXP, 100)
    }

    @MainActor func testWeeklyPlanValidatesWholeBatchBeforeCreatingAnything() throws {
        let (container, household, person, _) = try models()
        let context = container.mainContext
        context.insert(household); context.insert(person)
        let valid = QuestDraft(title: "Pack lunch", xp: 10,
                               participantIDs: [person.id], scheduleKind: .oneTime,
                               startDate: .now, hasDueDate: true, dueDate: .now)
        let invalid = QuestDraft(title: "", xp: 10,
                                 participantIDs: [person.id], scheduleKind: .oneTime,
                                 startDate: .now, hasDueDate: true, dueDate: .now)

        XCTAssertThrowsError(try AppModel().createPlannedQuests(
            [PlannedQuestDraft(draft: valid), PlannedQuestDraft(draft: invalid)],
            household: household, people: [person], context: context))
        XCTAssertTrue(try context.fetch(FetchDescriptor<Quest>()).isEmpty)
    }

    @MainActor func testWeeklyPlanCreatesEveryValidatedQuest() throws {
        let (container, household, person, _) = try models()
        let context = container.mainContext
        context.insert(household); context.insert(person)
        let first = QuestDraft(title: "Pack lunch", xp: 10,
                               participantIDs: [person.id], scheduleKind: .oneTime,
                               startDate: .now, hasDueDate: true, dueDate: .now)
        let second = QuestDraft(title: "Set out clothes", xp: 15,
                                participantIDs: [person.id], scheduleKind: .oneTime,
                                startDate: .now, hasDueDate: true, dueDate: .now)

        let created = try AppModel().createPlannedQuests(
            [PlannedQuestDraft(draft: first), PlannedQuestDraft(draft: second)],
            household: household, people: [person], context: context)

        XCTAssertEqual(created.count, 2)
        XCTAssertEqual(Set(created.map(\.title)), ["Pack lunch", "Set out clothes"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Quest>()).count, 2)
    }

    func testPlannerCopyPreservesIdentityFieldsAndUsesDestinationDay() {
        let householdID = UUID(), personID = UUID()
        let quest = Quest(householdID: householdID, title: "Water plants",
                          detail: "Use the small cup", xp: 12,
                          participantIDs: [personID], scheduleKind: .daily)
        let destination = Date(timeIntervalSince1970: 2_000_000)
        let copy = WeeklyPlannerRules.oneTimeCopy(of: quest, on: destination)
        XCTAssertEqual(copy.title, quest.title)
        XCTAssertEqual(copy.detail, quest.detail)
        XCTAssertEqual(copy.participantIDs, Set([personID]))
        XCTAssertEqual(copy.scheduleKind, .oneTime)
        XCTAssertEqual(copy.startDate, destination)
        XCTAssertEqual(copy.dueDate, destination)
    }

    @MainActor func testPreparedRewardActivationCarriesOnlyRewardProgress() throws {
        let (container, household, person, quest) = try models()
        let context = container.mainContext
        context.insert(household); context.insert(person); context.insert(quest)
        let active = RewardGoal(householdID: household.id, title: "Movie", targetXP: 100)
        active.createdAt = .distantPast
        context.insert(active)
        let completion = QuestCompletion(
            householdID: household.id, questID: quest.id, personID: person.id,
            occurrenceDay: "2026-08-26", completedAt: .now, awardedXP: 30)
        context.insert(completion)
        let model = AppModel()
        let prepared = try model.prepareFamilyReward(
            title: "Picnic", targetXP: 200, note: "Saturday",
            household: household, goals: [active], context: context)

        try model.activatePreparedReward(
            prepared, carryProgress: true, household: household,
            goals: [active, prepared], completions: [completion], context: context)

        XCTAssertEqual(active.state, .concluded)
        XCTAssertEqual(active.endingXP, 30)
        XCTAssertEqual(prepared.state, .active)
        XCTAssertEqual(prepared.startingXP, 30)
        XCTAssertEqual(ProgressionEngine.rewardXP([], goal: prepared), 30)
        XCTAssertEqual(ProgressionEngine.familyXP([completion]), 30)
    }

    @MainActor func testIndividualAndSharedParticipantsHaveSeparateEvents() throws {
        let (container, household, first, quest) = try models()
        let second = Person(householdID: household.id, name: "Jordan", role: .child, colorHex: "#123456", companionID: "orbit")
        quest.participantIDs = [first.id, second.id]
        quest.completionMode = .sharedAll
        let context = container.mainContext
        [household].forEach(context.insert); context.insert(first); context.insert(second); context.insert(quest)
        let model = AppModel()
        let now = ISO8601DateFormatter().date(from: "2026-07-28T14:00:00Z")!
        try model.complete(quest, personID: first.id, household: household, completions: [], context: context, now: now)
        let firstEvents = try context.fetch(FetchDescriptor<QuestCompletion>())
        try model.complete(quest, personID: second.id, household: household, completions: firstEvents, context: context, now: now)
        let events = try context.fetch(FetchDescriptor<QuestCompletion>())
        XCTAssertEqual(Set(events.map(\.personID)), Set([first.id, second.id]))
        XCTAssertEqual(ProgressionEngine.familyXP(events), 20)
    }

    @MainActor func testStreakUsesHouseholdDaysAcrossDSTAndUndo() throws {
        let (_, household, person, quest) = try models()
        let f = ISO8601DateFormatter()
        let dates = ["2026-03-07T23:30:00Z", "2026-03-08T23:30:00Z", "2026-03-09T23:30:00Z"].map { f.date(from: $0)! }
        let events = dates.map { QuestCompletion(householdID: household.id, questID: quest.id, personID: person.id, occurrenceDay: ProgressionEngine.dayKey($0, timeZoneIdentifier: household.timeZoneIdentifier), completedAt: $0, awardedXP: 40) }
        var progress = ProgressionEngine.progress(personID: person.id, completions: events, now: dates.last!, timeZoneIdentifier: household.timeZoneIdentifier)
        XCTAssertEqual(progress.bestStreak, 3)
        XCTAssertEqual(progress.level, 2)
        events[1].reversedAt = dates.last
        progress = ProgressionEngine.progress(personID: person.id, completions: events, now: dates.last!, timeZoneIdentifier: household.timeZoneIdentifier)
        XCTAssertEqual(progress.bestStreak, 1)
    }

    @MainActor func testWeeklyOccurrenceCrossesWeekBoundary() throws {
        let (_, household, _, quest) = try models()
        quest.scheduleKind = .weekly
        quest.weekdays = [2]
        let calendar = ProgressionEngine.calendar(timeZoneIdentifier: household.timeZoneIdentifier)
        let monday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 27, hour: 9))!
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 8, day: 2, hour: 23))!
        XCTAssertTrue(ProgressionEngine.isScheduled(quest, on: monday, timeZoneIdentifier: household.timeZoneIdentifier))
        XCTAssertEqual(ProgressionEngine.occurrenceKey(for: quest, on: sunday, timeZoneIdentifier: household.timeZoneIdentifier),
                       ProgressionEngine.dayKey(monday, timeZoneIdentifier: household.timeZoneIdentifier))
    }

    @MainActor func testHouseholdSchedulePauseIsInclusiveAndResumes() throws {
        let (_, household, person, quest) = try models()
        quest.scheduleKind = .daily
        quest.startDate = .distantPast
        let calendar = ProgressionEngine.calendar(
            timeZoneIdentifier: household.timeZoneIdentifier)
        let start = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 10, hour: 12))!
        let end = calendar.date(byAdding: .day, value: 2, to: start)!
        household.schedulePauseStartsAt = start
        household.schedulePauseEndsAt = end

        XCTAssertFalse(ProgressionEngine.isScheduled(
            quest, on: start, household: household))
        XCTAssertFalse(ProgressionEngine.isScheduled(
            quest, on: end, household: household))
        XCTAssertEqual(ProgressionEngine.temporalStatus(
            for: quest, personID: person.id, completions: [], now: end,
            timeZoneIdentifier: household.timeZoneIdentifier,
            household: household), .upcoming)
        let resumed = calendar.date(byAdding: .day, value: 1, to: end)!
        XCTAssertTrue(ProgressionEngine.isScheduled(
            quest, on: resumed, household: household))

        let before = QuestCompletion(
            householdID: household.id, questID: quest.id,
            personID: person.id,
            occurrenceDay: ProgressionEngine.dayKey(
                calendar.date(byAdding: .day, value: -1, to: start)!,
                timeZoneIdentifier: household.timeZoneIdentifier),
            completedAt: calendar.date(byAdding: .day, value: -1, to: start)!,
            awardedXP: 10)
        let after = QuestCompletion(
            householdID: household.id, questID: quest.id,
            personID: person.id,
            occurrenceDay: ProgressionEngine.dayKey(
                resumed, timeZoneIdentifier: household.timeZoneIdentifier),
            completedAt: resumed, awardedXP: 10)
        let progress = ProgressionEngine.progress(
            personID: person.id, completions: [before, after], now: resumed,
            timeZoneIdentifier: household.timeZoneIdentifier,
            schedulePauseStartsAt: start, schedulePauseEndsAt: end)
        XCTAssertEqual(progress.currentStreak, 2)
        XCTAssertEqual(progress.bestStreak, 2)
    }

    @MainActor func testEveryOtherWeekUsesStartWeekAsAnchor() throws {
        let (_, household, _, quest) = try models()
        quest.scheduleKind = .weekly
        quest.weekdays = [2]
        quest.repeatIntervalWeeks = 2
        let calendar = ProgressionEngine.calendar(
            timeZoneIdentifier: household.timeZoneIdentifier)
        quest.startDate = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 3, hour: 9))!
        let firstMonday = quest.startDate
        let skippedMonday = calendar.date(byAdding: .day, value: 7,
                                           to: firstMonday)!
        let nextMonday = calendar.date(byAdding: .day, value: 14,
                                        to: firstMonday)!

        XCTAssertTrue(ProgressionEngine.isScheduled(
            quest, on: firstMonday,
            timeZoneIdentifier: household.timeZoneIdentifier))
        XCTAssertFalse(ProgressionEngine.isScheduled(
            quest, on: skippedMonday,
            timeZoneIdentifier: household.timeZoneIdentifier))
        XCTAssertTrue(ProgressionEngine.isScheduled(
            quest, on: nextMonday,
            timeZoneIdentifier: household.timeZoneIdentifier))
        XCTAssertEqual(ProgressionEngine.occurrenceKey(
            for: quest, on: skippedMonday,
            timeZoneIdentifier: household.timeZoneIdentifier),
            ProgressionEngine.dayKey(firstMonday,
                timeZoneIdentifier: household.timeZoneIdentifier))

        let completion = QuestCompletion(
            householdID: household.id, questID: quest.id,
            personID: quest.participantIDs[0],
            occurrenceDay: ProgressionEngine.dayKey(firstMonday,
                timeZoneIdentifier: household.timeZoneIdentifier),
            completedAt: firstMonday, awardedXP: quest.xp)
        XCTAssertEqual(ProgressionEngine.temporalStatus(
            for: quest, personID: quest.participantIDs[0],
            completions: [completion], now: skippedMonday,
            timeZoneIdentifier: household.timeZoneIdentifier), .upcoming)
    }

    @MainActor func testEveryOtherWeekRemainsAnchoredAcrossDST() throws {
        let (_, household, _, quest) = try models()
        quest.scheduleKind = .weekly
        quest.weekdays = [2]
        quest.repeatIntervalWeeks = 2
        let calendar = ProgressionEngine.calendar(
            timeZoneIdentifier: household.timeZoneIdentifier)
        quest.startDate = calendar.date(from: DateComponents(
            year: 2026, month: 3, day: 2, hour: 9))!
        let afterDST = calendar.date(from: DateComponents(
            year: 2026, month: 3, day: 16, hour: 9))!
        XCTAssertTrue(ProgressionEngine.isScheduled(
            quest, on: afterDST,
            timeZoneIdentifier: household.timeZoneIdentifier))
    }

    @MainActor func testMidnightUsesHouseholdNotUTC() throws {
        let (_, household, _, quest) = try models()
        let date = ISO8601DateFormatter().date(from: "2026-07-29T02:30:00Z")!
        XCTAssertEqual(ProgressionEngine.dayKey(date, timeZoneIdentifier: household.timeZoneIdentifier), "2026-07-28")
        XCTAssertEqual(ProgressionEngine.occurrenceKey(for: quest, on: date, timeZoneIdentifier: household.timeZoneIdentifier), "2026-07-28")
    }

    @MainActor func testTemporalStatesUpcomingOverdueCompletedAndArchived() throws {
        let (_, household, person, quest) = try models()
        let calendar = ProgressionEngine.calendar(timeZoneIdentifier: household.timeZoneIdentifier)
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 28, hour: 12))!
        quest.scheduleKind = .oneTime
        quest.startDate = calendar.date(byAdding: .day, value: 1, to: now)!
        XCTAssertEqual(ProgressionEngine.temporalStatus(for: quest, personID: person.id, completions: [], now: now, timeZoneIdentifier: household.timeZoneIdentifier), .upcoming)
        quest.startDate = calendar.date(byAdding: .day, value: -1, to: now)!
        XCTAssertEqual(ProgressionEngine.temporalStatus(for: quest, personID: person.id, completions: [], now: now, timeZoneIdentifier: household.timeZoneIdentifier), .overdue)
        let key = ProgressionEngine.occurrenceKey(for: quest, on: now, timeZoneIdentifier: household.timeZoneIdentifier)!
        let event = QuestCompletion(householdID: household.id, questID: quest.id, personID: person.id, occurrenceDay: key, completedAt: now, awardedXP: 10)
        XCTAssertEqual(ProgressionEngine.temporalStatus(for: quest, personID: person.id, completions: [event], now: now, timeZoneIdentifier: household.timeZoneIdentifier), .completed)
        quest.deletedAt = now
        XCTAssertEqual(ProgressionEngine.temporalStatus(for: quest, personID: person.id, completions: [event], now: now, timeZoneIdentifier: household.timeZoneIdentifier), .inactive)
    }

    func testQuestTemplateCatalogMatchesApprovedRowanRoutines() {
        XCTAssertEqual(QuestTemplateCatalog.templates.count, 11)
        XCTAssertEqual(Set(QuestTemplateCatalog.templates.map(\.id)).count, 11)
        XCTAssertTrue(QuestTemplateCatalog.templates.contains {
            $0.id == "family-reset" && $0.completionMode == .sharedAll
        })
        XCTAssertEqual(
            QuestTemplateCatalog.templates.first { $0.id == "backpack-reset" }?.weekdays,
            Set(2...6))
    }

    @MainActor func testScheduleDiagnosticsRepairOnlySafeRecurrenceFields() throws {
        let (_, household, person, quest) = try models()
        quest.scheduleKind = .weekly
        quest.weekdays = [9]
        quest.repeatIntervalWeeks = 4
        quest.startDate = ISO8601DateFormatter().date(
            from: "2026-08-03T12:00:00Z")!
        quest.dueAt = ISO8601DateFormatter().date(
            from: "2026-08-01T12:00:00Z")!
        let completion = QuestCompletion(
            householdID: household.id, questID: quest.id,
            personID: person.id, occurrenceDay: "2026-07-27",
            completedAt: .now, awardedXP: 17)

        let issues = QuestScheduleDiagnostics.issues(for: quest)
        XCTAssertEqual(Set(issues.map(\.kind)), [
            .missingWeekdays, .invalidWeekdays, .unsupportedInterval,
            .dueBeforeStart
        ])
        XCTAssertTrue(QuestScheduleDiagnostics.applySafeRepairs(
            to: quest, timeZoneIdentifier: household.timeZoneIdentifier))
        XCTAssertEqual(quest.weekdays, [2])
        XCTAssertEqual(quest.repeatIntervalWeeks, 1)
        XCTAssertNotNil(quest.dueAt, "Unsafe deadline intent must remain for review")
        XCTAssertEqual(completion.awardedXP, 17)
        XCTAssertNil(completion.reversedAt)
    }

    @MainActor func testTwoWeekProjectionRespectsBiweeklyAnchor() throws {
        let (_, household, _, quest) = try models()
        let calendar = ProgressionEngine.calendar(
            timeZoneIdentifier: household.timeZoneIdentifier)
        quest.scheduleKind = .weekly
        quest.weekdays = [2]
        quest.repeatIntervalWeeks = 2
        quest.startDate = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 3, hour: 9))!
        let days = QuestScheduleProjection.days(
            quests: [quest], starting: quest.startDate, count: 15,
            timeZoneIdentifier: household.timeZoneIdentifier)
        XCTAssertTrue(days[0].questIDs.contains(quest.id))
        XCTAssertFalse(days[7].questIDs.contains(quest.id))
        XCTAssertTrue(days[14].questIDs.contains(quest.id))
    }
}

final class ConfigurationAndAdaptiveLayoutTests: XCTestCase {
    func testCloudConfigurationFailsClearlyUntilEnabledAndNamed() {
        XCTAssertEqual(
            KyndynCloudConfiguration(info: [:]).readiness,
            .disabled
        )
        XCTAssertEqual(
            KyndynCloudConfiguration(info: [
                KyndynCloudConfiguration.enabledInfoKey: true
            ]).readiness,
            .missingContainerIdentifier
        )
        XCTAssertEqual(
            KyndynCloudConfiguration(info: [
                KyndynCloudConfiguration.enabledInfoKey: true,
                KyndynCloudConfiguration.containerInfoKey: "not-a-container"
            ]).readiness,
            .invalidContainerIdentifier
        )
    }

    func testUITestOverrideKeepsLiveCloudConfigurationDeterministic() {
        let configuration = KyndynCloudConfiguration(
            info: [
                KyndynCloudConfiguration.enabledInfoKey: "YES",
                KyndynCloudConfiguration.containerInfoKey:
                    "iCloud.com.example.kyndyn"
            ],
            arguments: ["-ui-testing-cloud-unconfigured"]
        )
        XCTAssertEqual(configuration.readiness, .disabled)
    }

    func testDevelopmentCloudConfigurationIsExplicit() {
        let configuration = KyndynCloudConfiguration(info: [
            KyndynCloudConfiguration.enabledInfoKey: "YES",
            KyndynCloudConfiguration.containerInfoKey: "iCloud.com.example.kyndyn",
            KyndynCloudConfiguration.environmentInfoKey: "development"
        ])
        XCTAssertEqual(
            configuration.readiness,
            .ready(containerIdentifier: "iCloud.com.example.kyndyn",
                   environment: .development)
        )
    }

    func testAdaptiveBreakpointsCoverPhoneSplitViewTabletAndSquare() {
        XCTAssertEqual(AdaptiveLayout.dashboardColumns(for: 320), 1)
        XCTAssertEqual(AdaptiveLayout.questColumns(for: 520), 1)
        XCTAssertEqual(AdaptiveLayout.dashboardColumns(for: 834), 2)
        XCTAssertEqual(AdaptiveLayout.questColumns(for: 1_024), 2)
    }

    func testProfilePaletteHasHumanReadableNames() {
        XCTAssertEqual(ProfilePalette.name(for: "#00A6A6"), "Teal")
        XCTAssertEqual(ProfilePalette.name(for: "#abcdef"), "Custom")
    }
}

final class LifecycleRulesTests: XCTestCase {
    @MainActor func testUpgradedHouseholdGetsMissingDeviceSettings() throws {
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: Household.self, Person.self, Quest.self, QuestCompletion.self,
            LocalDeviceSettings.self, LocalQuestReminder.self,
            configurations: configuration)
        let context = container.mainContext
        context.insert(Household(name: "Upgrade Test", timeZoneIdentifier: "UTC"))
        try context.save()
        XCTAssertTrue(try context.fetch(
            FetchDescriptor<LocalDeviceSettings>()).isEmpty)
        let settings = try AppModel().ensureLocalDeviceSettings(in: context)
        XCTAssertFalse(settings.notificationsEnabled)
        XCTAssertEqual(try context.fetch(
            FetchDescriptor<LocalDeviceSettings>()).count, 1)
    }

    @MainActor func testPersonValidationAndDuplicateNames() throws {
        XCTAssertThrowsError(try LifecycleRules.validate(person: PersonDraft(name: "   "))) { XCTAssertEqual($0 as? KyndynValidationError, .emptyName) }
        XCTAssertThrowsError(try LifecycleRules.validate(person: PersonDraft(name: String(repeating: "A", count: 41)))) { XCTAssertEqual($0 as? KyndynValidationError, .nameTooLong) }
        XCTAssertEqual(try LifecycleRules.validate(person: PersonDraft(name: " Avery ")), "Avery")
        XCTAssertEqual(try LifecycleRules.validate(person: PersonDraft(name: "Avery")), "Avery")
    }

    @MainActor func testLastParentCannotBeArchived() {
        let householdID = UUID()
        let parent = Person(householdID: householdID, name: "Parent One", role: .parent, colorHex: "#000000", companionID: "spark")
        let child = Person(householdID: householdID, name: "Child", role: .child, colorHex: "#000000", companionID: "orbit")
        XCTAssertFalse(LifecycleRules.canArchive(person: parent, people: [parent, child]))
        let other = Person(householdID: householdID, name: "Parent Two", role: .parent, colorHex: "#000000", companionID: "bop")
        XCTAssertTrue(LifecycleRules.canArchive(person: parent, people: [parent, other, child]))
    }

    @MainActor func testQuestRejectsArchivedAssigneeAndEmptyWeekdays() {
        let householdID = UUID()
        let person = Person(householdID: householdID, name: "Avery", role: .child, colorHex: "#000000", companionID: "spark")
        var draft = QuestDraft(title: "Tidy room", participantIDs: [person.id], scheduleKind: .weekly)
        XCTAssertThrowsError(try LifecycleRules.validate(quest: draft, people: [person])) { XCTAssertEqual($0 as? KyndynValidationError, .noWeekdays) }
        draft.weekdays = [2]
        person.deletedAt = .now
        XCTAssertThrowsError(try LifecycleRules.validate(quest: draft, people: [person])) { XCTAssertEqual($0 as? KyndynValidationError, .archivedParticipant) }
    }

    func testQuestScheduleValidationPreventsInvalidInput() throws {
        var draft = QuestDraft(scheduleKind: .weekly, weekdays: [0, 2])
        XCTAssertThrowsError(try LifecycleRules.validateSchedule(
            draft, timeZoneIdentifier: "America/New_York")) {
            XCTAssertEqual($0 as? KyndynValidationError, .invalidWeekdays)
        }

        draft.weekdays = [2]
        draft.repeatIntervalWeeks = 3
        XCTAssertThrowsError(try LifecycleRules.validateSchedule(
            draft, timeZoneIdentifier: "America/New_York")) {
            XCTAssertEqual($0 as? KyndynValidationError,
                           .invalidRepeatInterval)
        }

        draft.scheduleKind = .daily
        draft.repeatIntervalWeeks = 2
        XCTAssertThrowsError(try LifecycleRules.validateSchedule(
            draft, timeZoneIdentifier: "America/New_York")) {
            XCTAssertEqual($0 as? KyndynValidationError,
                           .invalidRepeatInterval)
        }

        draft.repeatIntervalWeeks = 1
        draft.hasDueDate = true
        draft.startDate = ISO8601DateFormatter().date(
            from: "2026-03-09T04:00:00Z")!
        draft.dueDate = ISO8601DateFormatter().date(
            from: "2026-03-07T18:00:00Z")!
        XCTAssertThrowsError(try LifecycleRules.validateSchedule(
            draft, timeZoneIdentifier: "America/New_York")) {
            XCTAssertEqual($0 as? KyndynValidationError,
                           .deadlineBeforeStart)
        }

        draft.dueDate = draft.startDate
        XCTAssertNoThrow(try LifecycleRules.validateSchedule(
            draft, timeZoneIdentifier: "America/New_York"))
    }

    @MainActor func testArchivePreservesHistoryAndStableIDs() throws {
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Household.self, Person.self, Quest.self, QuestCompletion.self, configurations: configuration)
        let context = container.mainContext
        let household = Household(name: "Test", timeZoneIdentifier: "UTC")
        let first = Person(householdID: household.id, name: "Parent One", role: .parent, colorHex: "#000", companionID: "spark")
        let second = Person(householdID: household.id, name: "Parent Two", role: .parent, colorHex: "#111", companionID: "bop")
        let quest = Quest(householdID: household.id, title: "Test", xp: 10, participantIDs: [first.id])
        let event = QuestCompletion(householdID: household.id, questID: quest.id, personID: first.id, occurrenceDay: "2026-07-28", completedAt: .now, awardedXP: 10)
        [household].forEach(context.insert); context.insert(first); context.insert(second); context.insert(quest); context.insert(event)
        let personID = first.id; let questID = quest.id; let eventID = event.id
        try AppModel().archivePerson(first, people: [first, second], quests: [quest], context: context)
        XCTAssertEqual(first.id, personID)
        XCTAssertEqual(quest.id, questID)
        XCTAssertEqual(event.id, eventID)
        XCTAssertNotNil(first.deletedAt)
        XCTAssertNotNil(quest.deletedAt)
        XCTAssertEqual(event.awardedXP, 10)
    }
}

final class HouseholdTransferTests: XCTestCase {
    @MainActor private func transferContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(
            for: Household.self, Person.self, Quest.self,
            QuestCompletion.self, RewardGoal.self, HouseholdSettings.self,
            FamilyBroadcast.self,
            LocalDeviceSettings.self, LocalQuestReminder.self,
            HouseholdImportReceipt.self,
            HouseholdCloudState.self, SyncRecordMetadata.self,
            PendingSyncMutation.self, SyncConflict.self,
            configurations: configuration)
    }

    @MainActor func testBackupRoundTripPreservesStableHistoryAndUndo() throws {
        let source = try transferContainer()
        let context = source.mainContext
        let household = Household(
            name: "Fictional Harbor Family",
            timeZoneIdentifier: "America/New_York",
            rewardTitle: "Fictional Picnic", rewardGoalXP: 240)
        household.schedulePauseStartsAt = Date(timeIntervalSince1970: 1_786_320_000)
        household.schedulePauseEndsAt = Date(timeIntervalSince1970: 1_786_579_200)
        let parent = Person(
            householdID: household.id, name: "Avery", role: .parent,
            colorHex: "#6F2DBD", companionID: "spark")
        parent.earnedCompanionIDs = CollectionCatalog.normalizedCompanions(["penguin", "bee"])
        parent.backgroundID = "aquarium"
        parent.earnedBackgroundIDs = CollectionCatalog.normalizedBackgrounds(["aquarium"])
        parent.earnedBadgeIDs = RecognitionEngine.normalizedBadges(
            ["first-step", "quest-ten"])
        let quest = Quest(
            householdID: household.id, title: "Sort art supplies",
            xp: 17, participantIDs: [parent.id], scheduleKind: .weekly,
            weekdays: [2], repeatIntervalWeeks: 2)
        let event = QuestCompletion(
            householdID: household.id, questID: quest.id,
            personID: parent.id, occurrenceDay: "2026-07-27",
            completedAt: Date(timeIntervalSince1970: 1_775_000_000),
            awardedXP: 13)
        event.reversedAt = event.completedAt.addingTimeInterval(60)
        let settings = HouseholdSettings(householdID: household.id)
        let broadcast = FamilyBroadcast(
            householdID: household.id, title: "Tonight",
            message: "Fictional game night after dinner")
        [household].forEach(context.insert)
        context.insert(parent); context.insert(quest); context.insert(event)
        context.insert(settings)
        context.insert(broadcast)
        let data = try HouseholdTransferCodec.export(
            household: household, people: [parent], quests: [quest],
            completions: [event], goals: [], settings: settings,
            broadcasts: [broadcast])
        let verification = try HouseholdTransferCodec.verifyExport(data)
        XCTAssertEqual(verification.people, 1)
        XCTAssertEqual(verification.broadcasts, 1)
        XCTAssertFalse(verification.fingerprint.isEmpty)

        let destination = try transferContainer()
        let restored = try HouseholdRestoreService.restore(
            data, context: destination.mainContext)
        let restoredEvents = try destination.mainContext.fetch(
            FetchDescriptor<QuestCompletion>())
        XCTAssertEqual(restored.id, household.id)
        XCTAssertEqual(restored.schedulePauseStartsAt,
                       household.schedulePauseStartsAt)
        XCTAssertEqual(restored.schedulePauseEndsAt,
                       household.schedulePauseEndsAt)
        XCTAssertEqual(restoredEvents.map(\.id), [event.id])
        XCTAssertEqual(restoredEvents.first?.awardedXP, 13)
        XCTAssertNotNil(restoredEvents.first?.reversedAt)
        let restoredQuest = try destination.mainContext.fetch(
            FetchDescriptor<Quest>()).first
        XCTAssertEqual(restoredQuest?.repeatIntervalWeeks, 2)
        let restoredPerson = try destination.mainContext.fetch(
            FetchDescriptor<Person>()).first
        XCTAssertTrue(restoredPerson?.earnedCompanionIDs.contains("penguin") == true)
        XCTAssertTrue(restoredPerson?.earnedCompanionIDs.contains("bee") == true)
        XCTAssertEqual(restoredPerson?.backgroundID, "aquarium")
        XCTAssertTrue(restoredPerson?.earnedBackgroundIDs.contains("aquarium") == true)
        XCTAssertEqual(restoredPerson?.earnedBadgeIDs,
                       ["first-step", "quest-ten"])
        XCTAssertEqual(ProgressionEngine.familyXP(restoredEvents), 0)
        XCTAssertEqual(try destination.mainContext.fetch(
            FetchDescriptor<HouseholdImportReceipt>()).count, 1)
        XCTAssertEqual(try destination.mainContext.fetch(
            FetchDescriptor<FamilyBroadcast>()).first?.message,
            "Fictional game night after dinner")
    }

    @MainActor func testLocalHouseholdRemovalRequiresExactNameAndLeavesNoQueue()
        throws {
        let container = try transferContainer()
        let context = container.mainContext
        let household = Household(
            name: "Fictional Harbor Family", timeZoneIdentifier: "UTC")
        let parent = Person(
            householdID: household.id, name: "Avery", role: .parent,
            colorHex: "#6F2DBD", companionID: "spark")
        let quest = Quest(
            householdID: household.id, title: "Pack a picnic", xp: 10,
            participantIDs: [parent.id])
        context.insert(household); context.insert(parent); context.insert(quest)
        context.insert(FamilyBroadcast(
            householdID: household.id, title: "Update", message: "Bring hats"))
        context.insert(HouseholdCloudState(householdID: household.id))
        try context.save()
        let app = AppModel()

        XCTAssertThrowsError(try app.removeHouseholdFromDevice(
            household, confirmation: "wrong", context: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Household>()).count, 1)

        try app.removeHouseholdFromDevice(
            household, confirmation: household.name, context: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Household>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Person>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Quest>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<FamilyBroadcast>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingSyncMutation>()).isEmpty)
    }

    @MainActor func testHouseholdSafetyAuditFindsRecoveryRisksWithoutContent()
        throws {
        let container = try transferContainer()
        let context = container.mainContext
        let household = Household(
            name: "Fictional Lighthouse Family", timeZoneIdentifier: "UTC")
        let parent = Person(
            householdID: household.id, name: "Jordan", role: .parent,
            colorHex: "#6F2DBD", companionID: "spark")
        let quest = Quest(
            householdID: household.id, title: "Water the moon garden", xp: 10,
            participantIDs: [UUID()])
        let state = HouseholdCloudState(householdID: household.id)
        state.mode = .accountChanged
        context.insert(household); context.insert(parent); context.insert(quest)
        context.insert(state)
        try context.save()
        let now = Date(timeIntervalSince1970: 2_000_000)

        let report = try HouseholdSafetyAudit.inspect(
            household: household, context: context,
            lastBackupExportTimestamp: 0, now: now)

        XCTAssertEqual(report.status, .review)
        XCTAssertEqual(report.activeProfiles, 1)
        XCTAssertEqual(report.activeQuests, 1)
        XCTAssertTrue(report.notes.contains {
            $0.contains("valid profile assignment")
        })
        XCTAssertTrue(report.notes.contains {
            $0.contains("Family sync needs attention")
        })
        XCTAssertTrue(report.notes.contains {
            $0.contains("fresh private backup")
        })
        XCTAssertFalse(report.notes.joined().contains("Jordan"))
        XCTAssertFalse(report.notes.joined().contains("moon garden"))
    }

    @MainActor func testHouseholdSafetyAuditReportsReadyForHealthyLocalData()
        throws {
        let container = try transferContainer()
        let context = container.mainContext
        let household = Household(
            name: "Fictional Cove Family", timeZoneIdentifier: "UTC")
        let parent = Person(
            householdID: household.id, name: "Riley", role: .parent,
            colorHex: "#6F2DBD", companionID: "spark")
        let quest = Quest(
            householdID: household.id, title: "Pack towels", xp: 10,
            participantIDs: [parent.id])
        context.insert(household); context.insert(parent); context.insert(quest)
        try context.save()
        let now = Date(timeIntervalSince1970: 2_000_000)

        let report = try HouseholdSafetyAudit.inspect(
            household: household, context: context,
            lastBackupExportTimestamp: now.timeIntervalSince1970 - 60,
            now: now)

        XCTAssertEqual(report.status, .ready)
        XCTAssertTrue(report.notes.isEmpty)
    }

    @MainActor func testRestoreRequiresEmptyHouseholdAndRejectsMalformedVersion()
        throws {
        let container = try transferContainer()
        let context = container.mainContext
        let household = Household(name: "Existing", timeZoneIdentifier: "UTC")
        context.insert(household); try context.save()
        XCTAssertThrowsError(try HouseholdRestoreService.restore(
            Data("{}".utf8), context: context)) {
                XCTAssertEqual(
                    $0 as? HouseholdTransferError, .householdNotEmpty)
            }
        XCTAssertThrowsError(try HouseholdTransferCodec.validateBackup(
            Data(#"{"format":"kyndyn-household-backup","version":99}"#.utf8)))
    }

    @MainActor func testBackupExcludesDeviceLocalSecretsAndCloudMetadata()
        throws {
        let household = Household(name: "Fictional", timeZoneIdentifier: "UTC")
        let parent = Person(
            householdID: household.id, name: "Morgan", role: .parent,
            colorHex: "#007AFF", companionID: "orbit")
        let data = try HouseholdTransferCodec.export(
            household: household, people: [parent], quests: [],
            completions: [], goals: [], settings: nil)
        let text = String(decoding: data, as: UTF8.self).lowercased()
        for forbidden in [
            "pin", "keychain", "token", "accountfingerprint",
            "changetoken", "notification", "quietstarthour",
            "devicepersonid", "recordname", "zoneowner"
        ] {
            XCTAssertFalse(text.contains(forbidden), forbidden)
        }
    }

    func testRowanDryRunHandlesNumericIDsDuplicatesUndoAndPartialInvalidity()
        throws {
        let data = Data(Self.rowanFixture.utf8)
        let result = try RowanTransferConverter.dryRun(data)
        XCTAssertTrue(result.report.canImport)
        XCTAssertEqual(result.backup.people.count, 2)
        XCTAssertEqual(result.backup.quests.count, 2)
        XCTAssertEqual(result.backup.completions.count, 2)
        XCTAssertGreaterThanOrEqual(result.report.skipped, 1)
        XCTAssertGreaterThanOrEqual(result.report.invalid, 1)
        XCTAssertGreaterThanOrEqual(result.report.unsupported, 2)
        XCTAssertNotNil(result.backup.completions.first {
            $0.awardedXP == 19
        }?.reversedAt)
    }

    func testRowanStableMappingAndDSTOccurrenceAreDeterministic() throws {
        let first = try RowanTransferConverter.dryRun(
            Data(Self.rowanFixture.utf8)).backup
        let second = try RowanTransferConverter.dryRun(
            Data(Self.rowanFixture.utf8)).backup
        XCTAssertEqual(first.household.id, second.household.id)
        XCTAssertEqual(first.people.map(\.id), second.people.map(\.id))
        XCTAssertEqual(first.quests.map(\.id), second.quests.map(\.id))
        XCTAssertTrue(first.completions.contains {
            $0.occurrenceDay == "2026-03-08"
        })
    }

    private static let rowanFixture = #"""
    {
      "format": "rowan-pwa-transfer",
      "version": 1,
      "family": {
        "name": "Fictional Lighthouse Family",
        "timezone": "America/New_York",
        "current_reward": "Fictional Museum Day",
        "goal_xp": 425
      },
      "people": [
        {"id": 7, "name": "Morgan", "role": "parent", "color": "#007AFF", "companion": "orbit", "active": true},
        {"id": 8, "name": "Riley", "role": "child", "color": "bad-color", "companion": "legacy-dragon", "active": true},
        {"id": 8, "name": "Duplicate Riley", "role": "child", "active": true}
      ],
      "quests": [
        {"id": 41, "title": "Pack library books", "xp": 20, "assignees": [8], "frequency": "weekdays", "completion_mode": "individual", "active": true},
        {"id": "42", "title": "Choose Saturday music", "description": "A fictional scheduled quest.", "xp": 15, "assigned_to": 7, "frequency": "scheduled", "scheduled_days": [7], "active": false},
        {"id": 43, "title": "Unsupported claim", "xp": 10, "assignees": [8], "frequency": "daily", "completion_mode": "claim_once", "active": true},
        {"id": 44, "title": "Unknown assignment", "xp": 10, "assignees": [999], "frequency": "daily", "active": true},
        {"id": 45, "title": "Unsupported recurrence", "xp": 10, "assignees": [8], "frequency": "monthly", "active": true}
      ],
      "completion_history": [
        {"id": 501, "quest_id": 41, "person_id": 8, "completed_at": "2026-03-08T07:30:00Z", "awarded_xp": 19, "active": false, "undone_at": "2026-03-08T08:00:00Z"},
        {"id": 502, "quest_id": "42", "person_id": 7, "completed_at": "2026-07-25T18:00:00Z", "awarded_xp": 15, "active": true},
        {"id": 502, "quest_id": "42", "person_id": 7, "completed_at": "2026-07-25T18:00:00Z", "awarded_xp": 15, "active": true},
        {"id": 503, "quest_id": 999, "person_id": 8, "completed_at": "not-a-date", "awarded_xp": 10, "active": true}
      ],
      "settings": {
        "household_name": "Ignored fallback",
        "timezone": "UTC",
        "parent_pin": "never-import",
        "calendar_url": "https://example.invalid/private",
        "weather_location": "private",
        "push_subscriptions": ["secret"]
      }
    }
    """#
}

final class RecognitionEngineTests: XCTestCase {
    func testCompleteCollectionCatalogHasBundledArtwork() {
        XCTAssertEqual(CollectionCatalog.companions.count, 18)
        XCTAssertEqual(CollectionCatalog.backgrounds.count, 10)
        XCTAssertEqual(Set(CollectionCatalog.companionIDs).count,
                       CollectionCatalog.companions.count)
        XCTAssertEqual(Set(CollectionCatalog.backgrounds.map(\.id)).count,
                       CollectionCatalog.backgrounds.count)

        for companion in CollectionCatalog.companions {
            XCTAssertNotNil(
                Bundle.main.path(forResource: companion.id, ofType: "png"),
                "Missing artwork for \(companion.name)")
        }
        for background in CollectionCatalog.backgrounds {
            XCTAssertNotNil(
                Bundle.main.path(forResource: background.assetName, ofType: "png"),
                "Missing artwork for \(background.name)")
        }
    }

    func testCollectionUnlockThresholdsAreDeterministic() {
        let early = PersonProgress(xp: 10, level: 1, currentStreak: 1,
                                   bestStreak: 1, completedCount: 1)
        XCTAssertEqual(RecognitionEngine.badges(progress: early).map(\.id),
                       ["first-step"])
        XCTAssertTrue(RecognitionEngine.earnedCompanionIDs(progress: early)
            .contains("penguin"))
        XCTAssertFalse(RecognitionEngine.earnedCompanionIDs(progress: early)
            .contains("bee"))

        let established = PersonProgress(xp: 250, level: 3, currentStreak: 3,
                                         bestStreak: 3, completedCount: 25)
        let establishedCompanions = RecognitionEngine.earnedCompanionIDs(
            progress: established)
        XCTAssertTrue(establishedCompanions.contains("star"))
        XCTAssertFalse(establishedCompanions.contains("astronaut"))
        XCTAssertFalse(establishedCompanions.contains("jellyfish"))

        let mature = PersonProgress(xp: 2_000, level: 10, currentStreak: 7,
                                    bestStreak: 7, completedCount: 100)
        XCTAssertEqual(RecognitionEngine.badges(
            progress: mature, familyRewardReached: true).count, 11)
        XCTAssertEqual(Set(RecognitionEngine.earnedCompanionIDs(
            progress: mature, familyRewardReached: true)),
            Set(CollectionCatalog.companionIDs))
        XCTAssertEqual(Set(RecognitionEngine.earnedBackgroundIDs(
            progress: mature, familyRewardReached: true)),
            Set(CollectionCatalog.backgrounds.map(\.id)))
    }

    func testNormalizationPreservesStartersAndRejectsUnknownIDs() {
        XCTAssertEqual(RecognitionEngine.normalizedBadges(
            ["quest-ten", "not-a-badge"]), ["quest-ten"])
        XCTAssertEqual(Set(CollectionCatalog.normalizedCompanions(
            ["penguin", "not-a-companion"])),
            Set(CollectionCatalog.starterCompanionIDs + ["penguin"]))
        XCTAssertEqual(CollectionCatalog.normalizedBackgrounds(
            ["aquarium", "not-a-background"]), ["aquarium", "bedroom", "meadow"])
    }
}

private struct FakeAuthenticator: DeviceAuthenticating {
    let result: ParentAuthenticationResult
    func authenticate(reason: String) async -> ParentAuthenticationResult { result }
}
private final class MemoryPINStore: ParentPINStoring, @unchecked Sendable {
    var pin: String?
    func hasPIN() -> Bool { pin != nil }
    func verify(_ value: String) -> Bool { value == pin }
    func set(_ value: String) throws { pin = value }
    func remove() throws { pin = nil }
}

final class ParentAuthenticationTests: XCTestCase {
    @MainActor func testDeviceAuthenticationSuccessUnlocksParentArea() {
        let success = ParentAccessController(authenticator: FakeAuthenticator(result: .authenticated), pinStore: MemoryPINStore())
        success.handleAuthenticationResult(.authenticated)
        XCTAssertTrue(success.isUnlocked)
    }

    @MainActor func testCanceledDeviceAuthenticationStaysLocked() {
        let controller = ParentAccessController(authenticator: FakeAuthenticator(result: .userCanceled), pinStore: MemoryPINStore())
        controller.handleAuthenticationResult(.userCanceled)
        XCTAssertFalse(controller.isUnlocked)
        XCTAssertNotNil(controller.message)
    }

    @MainActor func testFailedDeviceAuthenticationStaysLocked() {
        let failed = ParentAccessController(authenticator: FakeAuthenticator(result: .failed("Try again")), pinStore: MemoryPINStore())
        failed.handleAuthenticationResult(.failed("Try again"))
        XCTAssertFalse(failed.isUnlocked)
        XCTAssertEqual(failed.message, "Try again")
    }

    @MainActor func testUnavailableDeviceAuthenticationOffersPINFallback() {
        let store = MemoryPINStore(); store.pin = "246810"
        let fallback = ParentAccessController(authenticator: FakeAuthenticator(result: .unavailable), pinStore: store)
        fallback.handleAuthenticationResult(.unavailable)
        XCTAssertTrue(fallback.hasPIN)
        XCTAssertFalse(fallback.unlock(pin: "111111"))
        XCTAssertTrue(fallback.unlock(pin: "246810"))
    }

    @MainActor func testRelocksAfterBackgroundInterval() {
        let store = MemoryPINStore(); store.pin = "246810"
        let access = ParentAccessController(authenticator: FakeAuthenticator(result: .unavailable), pinStore: store, relockInterval: 120)
        XCTAssertTrue(access.unlock(pin: "246810"))
        let start = Date(timeIntervalSince1970: 1_000)
        access.didEnterBackground(at: start)
        access.didBecomeActive(at: start.addingTimeInterval(121))
        XCTAssertFalse(access.isUnlocked)
    }

    func testPINValidation() {
        XCTAssertNotNil(PINValidation.message(for: "123"))
        XCTAssertNotNil(PINValidation.message(for: "aaaaaa"))
        XCTAssertNotNil(PINValidation.message(for: "111111"))
        XCTAssertNil(PINValidation.message(for: "246810"))
    }
}

final class ReminderRulesTests: XCTestCase {
    @MainActor private func fixture() -> (Household, Person, Quest, LocalDeviceSettings, Date) {
        let household = Household(name: "Fictional", timeZoneIdentifier: "America/New_York")
        let person = Person(householdID: household.id, name: "Avery", role: .child, colorHex: "#000", companionID: "spark")
        let quest = Quest(householdID: household.id, title: "Pack backpack", xp: 10, participantIDs: [person.id], scheduleKind: .daily)
        quest.startDate = .distantPast
        let settings = LocalDeviceSettings()
        settings.notificationsEnabled = true; settings.devicePersonID = person.id
        settings.defaultReminderHour = 16; settings.defaultReminderMinute = 0
        let calendar = ProgressionEngine.calendar(timeZoneIdentifier: household.timeZoneIdentifier)
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 28, hour: 12))!
        return (household, person, quest, settings, now)
    }

    @MainActor func testSelectionPrivacyAndDeterministicDeduplicationID() {
        let (household, person, quest, settings, now) = fixture()
        let first = ReminderRules.candidates(quests: [quest, quest], people: [person], settings: settings, household: household, now: now)
        XCTAssertEqual(Set(first.map(\.identifier)).count, 1)
        XCTAssertTrue(first.first?.body.contains("Open kyndyn") == true)
        settings.showQuestDetailsOnLockScreen = true
        XCTAssertEqual(ReminderRules.candidates(quests: [quest], people: [person], settings: settings, household: household, now: now).first?.body, quest.title)
    }

    @MainActor func testHouseholdPauseSuppressesQuestAndParentReminders() {
        let (household, person, quest, settings, now) = fixture()
        household.schedulePauseStartsAt = now
        household.schedulePauseEndsAt = now
        settings.parentSummaryEligible = true
        XCTAssertTrue(ReminderRules.candidates(
            quests: [quest], people: [person], settings: settings,
            household: household, now: now).isEmpty)
    }

    @MainActor func testDisabledArchivedAndWrongProfileCancelCandidates() {
        let (household, person, quest, settings, now) = fixture()
        settings.notificationsEnabled = false
        XCTAssertTrue(ReminderRules.candidates(quests: [quest], people: [person], settings: settings, household: household, now: now).isEmpty)
        settings.notificationsEnabled = true; settings.devicePersonID = UUID()
        XCTAssertTrue(ReminderRules.candidates(quests: [quest], people: [person], settings: settings, household: household, now: now).isEmpty)
        settings.devicePersonID = person.id; quest.deletedAt = now
        XCTAssertTrue(ReminderRules.candidates(quests: [quest], people: [person], settings: settings, household: household, now: now).isEmpty)
    }

    @MainActor func testQuietHoursMoveReminderToEnd() {
        let (household, person, quest, settings, now) = fixture()
        settings.defaultReminderHour = 21
        settings.quietStartHour = 20; settings.quietEndHour = 7
        let candidate = ReminderRules.candidates(quests: [quest], people: [person], settings: settings, household: household, now: now).first!
        let calendar = ProgressionEngine.calendar(timeZoneIdentifier: household.timeZoneIdentifier)
        XCTAssertEqual(calendar.component(.hour, from: candidate.fireDate), 7)
        XCTAssertEqual(calendar.component(.day, from: candidate.fireDate), 29)
    }

    @MainActor func testPerQuestReminderCanUpdateAndCancel() {
        let (household, person, quest, settings, now) = fixture()
        let preference = LocalQuestReminder(
            questID: quest.id, isEnabled: true, hour: 18, minute: 30)
        var candidate = ReminderRules.candidates(
            quests: [quest], people: [person], settings: settings,
            household: household, reminderPreferences: [preference],
            now: now).first
        let calendar = ProgressionEngine.calendar(
            timeZoneIdentifier: household.timeZoneIdentifier)
        XCTAssertEqual(calendar.component(.hour,
                                          from: candidate!.fireDate), 18)
        XCTAssertEqual(calendar.component(.minute,
                                          from: candidate!.fireDate), 30)
        preference.hour = 19
        candidate = ReminderRules.candidates(
            quests: [quest], people: [person], settings: settings,
            household: household, reminderPreferences: [preference],
            now: now).first
        XCTAssertEqual(calendar.component(.hour,
                                          from: candidate!.fireDate), 19)
        preference.isEnabled = false
        XCTAssertTrue(ReminderRules.candidates(
            quests: [quest], people: [person], settings: settings,
            household: household, reminderPreferences: [preference],
            now: now).isEmpty)
    }

    @MainActor func testCompletionCancelsOccurrenceReminder() {
        let (household, person, quest, settings, now) = fixture()
        let occurrence = ProgressionEngine.occurrenceKey(
            for: quest, on: now,
            timeZoneIdentifier: household.timeZoneIdentifier)!
        let completion = QuestCompletion(
            householdID: household.id, questID: quest.id,
            personID: person.id, occurrenceDay: occurrence,
            completedAt: now, awardedXP: quest.xp)
        XCTAssertTrue(ReminderRules.candidates(
            quests: [quest], people: [person], settings: settings,
            household: household, completions: [completion], now: now).isEmpty)
        completion.reversedAt = now
        XCTAssertEqual(ReminderRules.candidates(
            quests: [quest], people: [person], settings: settings,
            household: household, completions: [completion], now: now).count, 1)
    }

    @MainActor func testCandidateRetainsHouseholdTimeZone() {
        let (household, person, quest, settings, now) = fixture()
        XCTAssertEqual(ReminderRules.candidates(
            quests: [quest], people: [person], settings: settings,
            household: household, now: now).first?.timeZoneIdentifier,
            "America/New_York")
    }
}
