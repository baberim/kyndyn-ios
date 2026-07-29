import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable final class AppModel {
    var selectedPersonID: UUID?
    var showingParentArea = false
    var errorMessage: String?

    func seedSample(into context: ModelContext) throws {
        let household = Household(name: "Rowan Family", timeZoneIdentifier: TimeZone.current.identifier, rewardTitle: "Family Movie Night", rewardGoalXP: 300)
        context.insert(household)
        let maya = Person(householdID: household.id, name: "Maya", role: .parent, colorHex: "#6F2DBD", companionID: "spark")
        let leo = Person(householdID: household.id, name: "Leo", role: .child, colorHex: "#00A6A6", companionID: "orbit")
        let zoe = Person(householdID: household.id, name: "Zoe", role: .child, colorHex: "#F26B5B", companionID: "pixel")
        [maya, leo, zoe].forEach(context.insert)
        context.insert(Quest(householdID: household.id, title: "Make your bed", detail: "Start the day with a fresh space.", xp: 10, participantIDs: [leo.id], scheduleKind: .daily))
        context.insert(Quest(householdID: household.id, title: "Clear the dinner table", detail: "Everyone checks in when their part is done.", xp: 15, participantIDs: [maya.id, leo.id, zoe.id], completionMode: .sharedAll, scheduleKind: .daily))
        context.insert(Quest(householdID: household.id, title: "Water the plants", xp: 20, participantIDs: [zoe.id], scheduleKind: .weekly, weekdays: [3, 6]))
        try context.save()
        selectedPersonID = leo.id
    }

    func complete(_ quest: Quest, personID: UUID, household: Household, completions: [QuestCompletion], context: ModelContext, now: Date = .now) throws {
        guard quest.participantIDs.contains(personID) else { return }
        let day = ProgressionEngine.dayKey(now, timeZoneIdentifier: household.timeZoneIdentifier)
        guard !completions.contains(where: { $0.questID == quest.id && $0.personID == personID && $0.occurrenceDay == day && $0.reversedAt == nil }) else { return }
        let overdue = ProgressionEngine.overdueDays(for: quest, now: now, timeZoneIdentifier: household.timeZoneIdentifier)
        context.insert(QuestCompletion(householdID: household.id, questID: quest.id, personID: personID, occurrenceDay: day, completedAt: now, awardedXP: ProgressionEngine.effectiveXP(base: quest.xp, overdueDays: overdue)))
        try context.save()
    }

    func undo(_ quest: Quest, personID: UUID, household: Household, completions: [QuestCompletion], context: ModelContext, now: Date = .now) throws {
        let day = ProgressionEngine.dayKey(now, timeZoneIdentifier: household.timeZoneIdentifier)
        let event = completions.filter { $0.questID == quest.id && $0.personID == personID && $0.occurrenceDay == day && $0.reversedAt == nil }.max { $0.completedAt < $1.completedAt }
        event?.reversedAt = now
        try context.save()
    }
}

