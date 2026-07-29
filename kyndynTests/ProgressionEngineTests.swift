import XCTest
import SwiftData
@testable import kyndyn

final class ProgressionEngineTests: XCTestCase {
    @MainActor private func models() throws -> (ModelContainer, Household, Person, Quest) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Household.self, Person.self, Quest.self, QuestCompletion.self, LocalDeviceSettings.self, configurations: configuration)
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
}

final class LifecycleRulesTests: XCTestCase {
    @MainActor func testUpgradedHouseholdGetsMissingDeviceSettings() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Household.self, Person.self, Quest.self, QuestCompletion.self,
            LocalDeviceSettings.self, configurations: configuration)
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

    @MainActor func testArchivePreservesHistoryAndStableIDs() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
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
}
