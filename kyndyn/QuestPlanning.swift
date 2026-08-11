import Foundation

struct QuestTemplate: Identifiable, Equatable, Sendable {
    let id: String
    let symbol: String
    let title: String
    let detail: String
    let xp: Int
    let scheduleKind: ScheduleKind
    let weekdays: Set<Int>
    let completionMode: QuestCompletionMode

    func draft(startDate: Date = .now) -> QuestDraft {
        QuestDraft(
            title: title,
            detail: detail,
            xp: xp,
            completionMode: completionMode,
            scheduleKind: scheduleKind,
            weekdays: weekdays,
            startDate: startDate
        )
    }
}

enum QuestTemplateCatalog {
    static let templates: [QuestTemplate] = [
        .init(id: "morning-routine", symbol: "sunrise.fill",
              title: "Morning Routine",
              detail: "A simple daily start-the-day checklist.", xp: 15,
              scheduleKind: .daily, weekdays: [], completionMode: .individual),
        .init(id: "backpack-reset", symbol: "backpack.fill",
              title: "Backpack & Lunchbox Reset",
              detail: "Reset papers, lunchboxes, and supplies for tomorrow.", xp: 10,
              scheduleKind: .weekly, weekdays: [2, 3, 4, 5, 6], completionMode: .individual),
        .init(id: "bedroom-reset", symbol: "bed.double.fill",
              title: "Bedroom Reset",
              detail: "A quick pickup that keeps bedrooms manageable.", xp: 10,
              scheduleKind: .daily, weekdays: [], completionMode: .individual),
        .init(id: "homework-check", symbol: "pencil.and.list.clipboard",
              title: "Homework Check",
              detail: "Make sure homework, folders, and school items are ready.", xp: 10,
              scheduleKind: .weekly, weekdays: [2, 3, 4, 5, 6], completionMode: .individual),
        .init(id: "trash-night", symbol: "trash.fill",
              title: "Trash Night",
              detail: "Take care of trash and recycling before pickup.", xp: 15,
              scheduleKind: .weekly, weekdays: [2], completionMode: .individual),
        .init(id: "pet-care", symbol: "pawprint.fill",
              title: "Pet Care",
              detail: "Food, water, and a quick check-in for family pets.", xp: 10,
              scheduleKind: .daily, weekdays: [], completionMode: .individual),
        .init(id: "dishwasher-unload", symbol: "fork.knife",
              title: "Unload Dishwasher",
              detail: "Clear clean dishes so the kitchen can keep moving.", xp: 10,
              scheduleKind: .daily, weekdays: [], completionMode: .individual),
        .init(id: "reading-time", symbol: "books.vertical.fill",
              title: "Reading Time",
              detail: "A calm daily reading habit.", xp: 10,
              scheduleKind: .daily, weekdays: [], completionMode: .individual),
        .init(id: "weekly-room-clean", symbol: "sparkles",
              title: "Weekly Room Clean",
              detail: "A deeper reset for floors, surfaces, and laundry.", xp: 25,
              scheduleKind: .weekly, weekdays: [7], completionMode: .individual),
        .init(id: "aquarium-maintenance", symbol: "fish.fill",
              title: "Aquarium Maintenance",
              detail: "A weekly aquarium check for feeding, water, and cleanup.", xp: 20,
              scheduleKind: .weekly, weekdays: [1], completionMode: .individual),
        .init(id: "family-reset", symbol: "house.fill",
              title: "Family Reset",
              detail: "Everyone helps tidy shared spaces together.", xp: 15,
              scheduleKind: .daily, weekdays: [], completionMode: .sharedAll)
    ]
}

struct QuestScheduleIssue: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case missingWeekdays
        case invalidWeekdays
        case unsupportedInterval
        case unusedWeeklyInterval
        case dueBeforeStart
    }

    let questID: UUID
    let questTitle: String
    let kind: Kind
    let message: String
    let safelyRepairable: Bool

    var id: String { "\(questID.uuidString):\(kind.rawValue)" }
}

enum QuestScheduleDiagnostics {
    static func issues(for quest: Quest) -> [QuestScheduleIssue] {
        guard quest.deletedAt == nil else { return [] }
        var result = [QuestScheduleIssue]()
        let validWeekdays = quest.weekdays.filter { (1...7).contains($0) }

        if quest.scheduleKind == .weekly && validWeekdays.isEmpty {
            result.append(.init(
                questID: quest.id, questTitle: quest.title,
                kind: .missingWeekdays,
                message: "No active weekday is selected.", safelyRepairable: true))
        }
        if validWeekdays.count != quest.weekdays.count {
            result.append(.init(
                questID: quest.id, questTitle: quest.title,
                kind: .invalidWeekdays,
                message: "The schedule contains an unrecognized weekday.",
                safelyRepairable: true))
        }
        if quest.scheduleKind == .weekly && !(1...2).contains(quest.repeatIntervalWeeks) {
            result.append(.init(
                questID: quest.id, questTitle: quest.title,
                kind: .unsupportedInterval,
                message: "The repeat interval is not supported by this version.",
                safelyRepairable: true))
        }
        if quest.scheduleKind != .weekly && quest.repeatIntervalWeeks != 1 {
            result.append(.init(
                questID: quest.id, questTitle: quest.title,
                kind: .unusedWeeklyInterval,
                message: "A weekly interval is attached to a non-weekly quest.",
                safelyRepairable: true))
        }
        if let dueAt = quest.dueAt, dueAt < quest.startDate {
            result.append(.init(
                questID: quest.id, questTitle: quest.title,
                kind: .dueBeforeStart,
                message: "The deadline is earlier than the start date.",
                safelyRepairable: false))
        }
        return result
    }

    @discardableResult
    static func applySafeRepairs(to quest: Quest,
                                 timeZoneIdentifier: String) -> Bool {
        guard quest.deletedAt == nil else { return false }
        var changed = false
        let valid = Array(Set(quest.weekdays.filter { (1...7).contains($0) })).sorted()
        if valid != quest.weekdays {
            quest.weekdays = valid
            changed = true
        }
        if quest.scheduleKind == .weekly && quest.weekdays.isEmpty {
            let calendar = ProgressionEngine.calendar(
                timeZoneIdentifier: timeZoneIdentifier)
            quest.weekdays = [calendar.component(.weekday, from: quest.startDate)]
            changed = true
        }
        if quest.scheduleKind == .weekly && !(1...2).contains(quest.repeatIntervalWeeks) {
            quest.repeatIntervalWeeks = 1
            changed = true
        } else if quest.scheduleKind != .weekly && quest.repeatIntervalWeeks != 1 {
            quest.repeatIntervalWeeks = 1
            changed = true
        }
        return changed
    }
}

struct QuestScheduleDay: Identifiable, Equatable {
    let date: Date
    let questIDs: [UUID]
    var id: Date { date }
}

enum QuestScheduleProjection {
    static func days(quests: [Quest], starting startDate: Date, count: Int,
                     timeZoneIdentifier: String) -> [QuestScheduleDay] {
        guard count > 0 else { return [] }
        let calendar = ProgressionEngine.calendar(
            timeZoneIdentifier: timeZoneIdentifier)
        let first = calendar.startOfDay(for: startDate)
        let active = quests.filter { $0.deletedAt == nil }
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset,
                                           to: first) else { return nil }
            return QuestScheduleDay(
                date: date,
                questIDs: active.filter {
                    ProgressionEngine.isScheduled(
                        $0, on: date,
                        timeZoneIdentifier: timeZoneIdentifier)
                }.map(\.id)
            )
        }
    }
}
