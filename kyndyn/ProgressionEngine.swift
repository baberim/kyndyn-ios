import Foundation

struct PersonProgress: Equatable {
    let xp: Int
    let level: Int
    let currentStreak: Int
    let bestStreak: Int
    let completedCount: Int
}

enum QuestTemporalStatus: String, Equatable {
    case today, upcoming, completed, overdue, inactive
}

enum ProgressionEngine {
    static func calendar(timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar
    }

    static func dayKey(_ date: Date, timeZoneIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar(timeZoneIdentifier: timeZoneIdentifier)
        formatter.timeZone = formatter.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func isScheduled(_ quest: Quest, on date: Date, timeZoneIdentifier: String) -> Bool {
        let calendar = calendar(timeZoneIdentifier: timeZoneIdentifier)
        guard date >= calendar.startOfDay(for: quest.startDate) else { return false }
        switch quest.scheduleKind {
        case .oneTime: return calendar.isDate(date, inSameDayAs: quest.startDate)
        case .daily: return true
        case .weekly:
            return quest.weekdays.contains(calendar.component(.weekday, from: date))
                && isActiveWeek(for: quest, date: date, calendar: calendar)
        }
    }

    private static func isActiveWeek(for quest: Quest, date: Date, calendar: Calendar) -> Bool {
        let interval = max(1, quest.repeatIntervalWeeks)
        guard interval > 1 else { return true }
        guard let anchor = calendar.dateInterval(of: .weekOfYear, for: quest.startDate)?.start,
              let candidate = calendar.dateInterval(of: .weekOfYear, for: date)?.start else {
            return false
        }
        let weeks = calendar.dateComponents([.weekOfYear], from: anchor, to: candidate).weekOfYear ?? 0
        return weeks >= 0 && weeks.isMultiple(of: interval)
    }

    static func occurrenceDate(for quest: Quest, on date: Date, timeZoneIdentifier: String) -> Date? {
        let calendar = calendar(timeZoneIdentifier: timeZoneIdentifier)
        let today = calendar.startOfDay(for: date)
        let start = calendar.startOfDay(for: quest.startDate)
        guard today >= start else { return nil }
        switch quest.scheduleKind {
        case .oneTime:
            return start
        case .daily:
            return today
        case .weekly:
            let searchDays = max(6, max(1, quest.repeatIntervalWeeks) * 7 + 6)
            for offset in 0...searchDays {
                guard let candidate = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
                if candidate >= start && isScheduled(quest, on: candidate, timeZoneIdentifier: timeZoneIdentifier) {
                    return candidate
                }
            }
            return nil
        }
    }

    static func occurrenceKey(for quest: Quest, on date: Date, timeZoneIdentifier: String) -> String? {
        occurrenceDate(for: quest, on: date, timeZoneIdentifier: timeZoneIdentifier)
            .map { dayKey($0, timeZoneIdentifier: timeZoneIdentifier) }
    }

    static func temporalStatus(for quest: Quest, personID: UUID, completions: [QuestCompletion],
                               now: Date, timeZoneIdentifier: String) -> QuestTemporalStatus {
        guard quest.deletedAt == nil, quest.participantIDs.contains(personID) else { return .inactive }
        let calendar = calendar(timeZoneIdentifier: timeZoneIdentifier)
        let today = calendar.startOfDay(for: now)
        let start = calendar.startOfDay(for: quest.startDate)
        if start > today { return .upcoming }
        guard let key = occurrenceKey(for: quest, on: now, timeZoneIdentifier: timeZoneIdentifier) else {
            return .upcoming
        }
        if completions.contains(where: {
            $0.questID == quest.id && $0.personID == personID &&
            $0.occurrenceDay == key && $0.reversedAt == nil
        }) {
            if quest.scheduleKind == .weekly,
               quest.repeatIntervalWeeks > 1,
               !isActiveWeek(for: quest, date: today, calendar: calendar) {
                return .upcoming
            }
            return .completed
        }
        if let dueAt = quest.dueAt, now > dueAt { return .overdue }
        if let occurrence = occurrenceDate(for: quest, on: now, timeZoneIdentifier: timeZoneIdentifier),
           occurrence < today { return .overdue }
        return .today
    }

    static func overdueDays(for quest: Quest, now: Date, timeZoneIdentifier: String) -> Int {
        let calendar = calendar(timeZoneIdentifier: timeZoneIdentifier)
        if let dueAt = quest.dueAt, now > dueAt {
            return max(1, calendar.dateComponents([.day], from: dueAt, to: now).day ?? 1)
        }
        if quest.scheduleKind == .oneTime {
            let start = calendar.startOfDay(for: quest.startDate)
            let today = calendar.startOfDay(for: now)
            return today > start ? max(1, calendar.dateComponents([.day], from: start, to: today).day ?? 1) : 0
        }
        guard quest.scheduleKind == .weekly else { return 0 }
        let today = calendar.startOfDay(for: now)
        let searchDays = max(7, max(1, quest.repeatIntervalWeeks) * 7 + 6)
        for offset in 0...searchDays {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            if isScheduled(quest, on: date, timeZoneIdentifier: timeZoneIdentifier) { return offset }
        }
        return 0
    }

    static func effectiveXP(base: Int, overdueDays: Int) -> Int {
        guard overdueDays > 0 else { return base }
        let penalty = min(overdueDays * 10, 50)
        return max(1, Int((Double(base) * Double(100 - penalty) / 100).rounded()))
    }

    static func progress(personID: UUID, completions: [QuestCompletion], now: Date, timeZoneIdentifier: String) -> PersonProgress {
        let active = completions.filter { $0.personID == personID && $0.reversedAt == nil }
        let xp = active.reduce(0) { $0 + $1.awardedXP }
        let calendar = calendar(timeZoneIdentifier: timeZoneIdentifier)
        let days = Set(active.map { calendar.startOfDay(for: $0.completedAt) }).sorted()
        var best = 0
        var run = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.dateComponents([.day], from: previous, to: day).day == 1 {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        let today = calendar.startOfDay(for: now)
        let last = days.last
        let current: Int
        if let last, let gap = calendar.dateComponents([.day], from: last, to: today).day, gap <= 1 {
            var value = 1
            var cursor = last
            for day in days.dropLast().reversed() {
                guard calendar.dateComponents([.day], from: day, to: cursor).day == 1 else { break }
                value += 1; cursor = day
            }
            current = value
        } else {
            current = 0
        }
        return PersonProgress(xp: xp, level: xp / 100 + 1, currentStreak: current, bestStreak: best, completedCount: active.count)
    }

    static func familyXP(_ completions: [QuestCompletion]) -> Int {
        completions.filter { $0.reversedAt == nil }.reduce(0) { $0 + $1.awardedXP }
    }
}
