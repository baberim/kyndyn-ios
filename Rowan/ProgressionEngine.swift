import Foundation

struct PersonProgress: Equatable {
    let xp: Int
    let level: Int
    let currentStreak: Int
    let bestStreak: Int
    let completedCount: Int
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
        case .weekly: return quest.weekdays.contains(calendar.component(.weekday, from: date))
        }
    }

    static func overdueDays(for quest: Quest, now: Date, timeZoneIdentifier: String) -> Int {
        let calendar = calendar(timeZoneIdentifier: timeZoneIdentifier)
        if let dueAt = quest.dueAt, now > dueAt {
            return max(1, calendar.dateComponents([.day], from: dueAt, to: now).day ?? 1)
        }
        guard quest.scheduleKind == .weekly else { return 0 }
        let today = calendar.startOfDay(for: now)
        for offset in 0...7 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            if quest.weekdays.contains(calendar.component(.weekday, from: date)) { return offset }
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

