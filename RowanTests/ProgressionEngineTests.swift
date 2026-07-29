import XCTest
import SwiftData
@testable import Rowan

final class ProgressionEngineTests: XCTestCase {
    @MainActor private func models() throws -> (ModelContainer, Household, Person, Quest) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Household.self, Person.self, Quest.self, QuestCompletion.self, configurations: configuration)
        let household = Household(name: "Test", timeZoneIdentifier: "America/New_York")
        let person = Person(householdID: household.id, name: "Avery", role: .child, colorHex: "#000000", companionID: "spark")
        let quest = Quest(householdID: household.id, title: "Test quest", xp: 10, participantIDs: [person.id], scheduleKind: .daily)
        return (container, household, person, quest)
    }

    func testLateXPPenaltyCapsAtHalf() {
        XCTAssertEqual(ProgressionEngine.effectiveXP(base: 20, overdueDays: 2), 16)
        XCTAssertEqual(ProgressionEngine.effectiveXP(base: 20, overdueDays: 9), 10)
    }

    @MainActor func testCompletionIsIdempotentAndUndoRecalculates() throws {
        let (container, household, person, quest) = try models()
        let context = container.mainContext
        context.insert(household)
        context.insert(person)
        context.insert(quest)
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
    }

    @MainActor func testStreakUsesHouseholdDaysAndUndo() throws {
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

    @MainActor func testWeeklyRecurrenceAndHouseholdTime() throws {
        let (_, household, _, quest) = try models()
        quest.scheduleKind = .weekly
        quest.weekdays = [3]
        let calendar = ProgressionEngine.calendar(timeZoneIdentifier: household.timeZoneIdentifier)
        let tuesday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 28, hour: 9))!
        let wednesday = calendar.date(byAdding: .day, value: 1, to: tuesday)!
        XCTAssertTrue(ProgressionEngine.isScheduled(quest, on: tuesday, timeZoneIdentifier: household.timeZoneIdentifier))
        XCTAssertFalse(ProgressionEngine.isScheduled(quest, on: wednesday, timeZoneIdentifier: household.timeZoneIdentifier))
    }
}
