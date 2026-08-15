import Foundation

struct PersonProgress: Equatable {
    let xp: Int
    let questXP: Int
    let level: Int
    let currentStreak: Int
    let bestStreak: Int
    let completedCount: Int

    init(xp: Int, level: Int, currentStreak: Int, bestStreak: Int,
         completedCount: Int, questXP: Int? = nil) {
        self.xp = xp
        self.questXP = questXP ?? xp
        self.level = level
        self.currentStreak = currentStreak
        self.bestStreak = bestStreak
        self.completedCount = completedCount
    }
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

    static func isSchedulePaused(on date: Date, household: Household) -> Bool {
        guard let startsAt = household.schedulePauseStartsAt,
              let endsAt = household.schedulePauseEndsAt else { return false }
        let calendar = calendar(timeZoneIdentifier: household.timeZoneIdentifier)
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: startsAt)
            && day <= calendar.startOfDay(for: endsAt)
    }

    static func isScheduled(_ quest: Quest, on date: Date,
                            household: Household) -> Bool {
        !isSchedulePaused(on: date, household: household)
            && isScheduled(quest, on: date,
                           timeZoneIdentifier: household.timeZoneIdentifier)
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
                               now: Date, timeZoneIdentifier: String,
                               household: Household? = nil) -> QuestTemporalStatus {
        guard quest.deletedAt == nil, quest.participantIDs.contains(personID) else { return .inactive }
        if let household, isSchedulePaused(on: now, household: household) {
            return .upcoming
        }
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

    static func progress(personID: UUID, completions: [QuestCompletion], now: Date,
                         timeZoneIdentifier: String,
                         startingXPAdjustment: Int = 0,
                         schedulePauseStartsAt: Date? = nil,
                         schedulePauseEndsAt: Date? = nil) -> PersonProgress {
        let active = completions.filter { $0.personID == personID && $0.reversedAt == nil }
        let questXP = active.reduce(0) { $0 + $1.awardedXP }
        let xp = max(0, questXP + startingXPAdjustment)
        let calendar = calendar(timeZoneIdentifier: timeZoneIdentifier)
        let days = Set(active.map { calendar.startOfDay(for: $0.completedAt) }).sorted()
        var best = 0
        var run = 0
        var previous: Date?
        for day in days {
            if let previous, streakDaysAreConsecutive(
                previous, day, calendar: calendar,
                pauseStart: schedulePauseStartsAt,
                pauseEnd: schedulePauseEndsAt) {
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
        if let last, streakDaysAreConsecutive(
            last, today, calendar: calendar,
            pauseStart: schedulePauseStartsAt,
            pauseEnd: schedulePauseEndsAt) {
            var value = 1
            var cursor = last
            for day in days.dropLast().reversed() {
                guard streakDaysAreConsecutive(
                    day, cursor, calendar: calendar,
                    pauseStart: schedulePauseStartsAt,
                    pauseEnd: schedulePauseEndsAt) else { break }
                value += 1; cursor = day
            }
            current = value
        } else {
            current = 0
        }
        return PersonProgress(xp: xp, level: xp / 100 + 1,
                              currentStreak: current, bestStreak: best,
                              completedCount: active.count, questXP: questXP)
    }

    private static func streakDaysAreConsecutive(
        _ earlier: Date, _ later: Date, calendar: Calendar,
        pauseStart: Date?, pauseEnd: Date?
    ) -> Bool {
        let first = calendar.startOfDay(for: earlier)
        let last = calendar.startOfDay(for: later)
        let gap = calendar.dateComponents([.day], from: first, to: last).day ?? 0
        guard gap > 0 else { return true }
        guard gap > 1, let pauseStart, let pauseEnd else { return gap == 1 }
        let pausedFirst = calendar.startOfDay(for: pauseStart)
        let pausedLast = calendar.startOfDay(for: pauseEnd)
        for offset in 1..<gap {
            guard let day = calendar.date(byAdding: .day, value: offset, to: first),
                  day >= pausedFirst, day <= pausedLast else { return false }
        }
        return true
    }

    static func familyXP(_ completions: [QuestCompletion]) -> Int {
        completions.filter { $0.reversedAt == nil }.reduce(0) { $0 + $1.awardedXP }
    }

    static func currentRewardGoal(
        _ goals: [RewardGoal], householdID: UUID
    ) -> RewardGoal? {
        goals.filter {
            $0.householdID == householdID && $0.deletedAt == nil
        }.max {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    static func rewardXP(
        _ completions: [QuestCompletion], goal: RewardGoal?
    ) -> Int {
        completions.filter { completion in
            guard completion.reversedAt == nil else { return false }
            return goal.map { completion.completedAt >= $0.createdAt } ?? true
        }.reduce(0) { $0 + $1.awardedXP }
    }
}

struct DailyInsight: Identifiable, Equatable {
    let date: Date
    let completed: Int
    let notCompleted: Int
    let waiting: Int
    let xp: Int
    var id: Date { date }
}

struct PersonInsight: Identifiable, Equatable {
    let personID: UUID
    let name: String
    let colorHex: String
    let completed: Int
    let notCompleted: Int
    let waiting: Int
    let xp: Int
    let currentStreak: Int
    let level: Int
    var id: UUID { personID }
    var concluded: Int { completed + notCompleted }
    var completionRate: Int {
        concluded == 0 ? 0 : Int((Double(completed) / Double(concluded) * 100).rounded())
    }
}

struct WeeklyInsight: Identifiable, Equatable {
    let start: Date
    let end: Date
    let days: [DailyInsight]
    let people: [PersonInsight]
    let observations: [String]
    var id: Date { start }
    var completed: Int { days.reduce(0) { $0 + $1.completed } }
    var notCompleted: Int { days.reduce(0) { $0 + $1.notCompleted } }
    var waiting: Int { days.reduce(0) { $0 + $1.waiting } }
    var xp: Int { days.reduce(0) { $0 + $1.xp } }
    var concluded: Int { completed + notCompleted }
    var completionRate: Int {
        concluded == 0 ? 0 : Int((Double(completed) / Double(concluded) * 100).rounded())
    }
}

enum InsightsEngine {
    static func week(
        containing selectedDate: Date, now: Date, household: Household,
        people: [Person], quests: [Quest], completions: [QuestCompletion]
    ) -> WeeklyInsight {
        let calendar = ProgressionEngine.calendar(
            timeZoneIdentifier: household.timeZoneIdentifier)
        let selectedDay = calendar.startOfDay(for: selectedDate)
        let start = calendar.dateInterval(of: .weekOfYear, for: selectedDay)?.start
            ?? selectedDay
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let today = calendar.startOfDay(for: now)
        let activePeople = people.filter {
            $0.householdID == household.id
                && ($0.deletedAt == nil || $0.deletedAt! >= start)
        }
        let householdQuests = quests.filter { $0.householdID == household.id }
        let activeEvents = completions.filter {
            $0.householdID == household.id && $0.reversedAt == nil
        }
        var personCounts: [UUID: (
            completed: Int, missed: Int, waiting: Int, xp: Int
        )] = [:]
        let days = (0..<7).compactMap { offset -> DailyInsight? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start)
            else { return nil }
            var completed = 0, missed = 0, waiting = 0, xp = 0
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            for quest in householdQuests where quest.startDate <= dayEnd {
                if let deleted = quest.deletedAt, deleted < day { continue }
                guard ProgressionEngine.isScheduled(
                    quest, on: day, household: household) else { continue }
                let key = ProgressionEngine.dayKey(
                    day, timeZoneIdentifier: household.timeZoneIdentifier)
                for person in activePeople where quest.participantIDs.contains(person.id) {
                    let event = activeEvents.first {
                        $0.questID == quest.id && $0.personID == person.id
                            && $0.occurrenceDay == key
                    }
                    var counts = personCounts[person.id]
                        ?? (completed: 0, missed: 0, waiting: 0, xp: 0)
                    if let event {
                        completed += 1; xp += event.awardedXP
                        counts.completed += 1; counts.xp += event.awardedXP
                    } else if day < today {
                        missed += 1; counts.missed += 1
                    } else if day == today {
                        waiting += 1; counts.waiting += 1
                    }
                    personCounts[person.id] = counts
                }
            }
            return DailyInsight(date: day, completed: completed,
                                notCompleted: missed, waiting: waiting, xp: xp)
        }
        let personInsights: [PersonInsight] = activePeople.map { person in
            let counts = personCounts[person.id]
                ?? (completed: 0, missed: 0, waiting: 0, xp: 0)
            let progress = ProgressionEngine.progress(
                personID: person.id, completions: completions, now: now,
                timeZoneIdentifier: household.timeZoneIdentifier,
                startingXPAdjustment: person.startingXPAdjustment,
                schedulePauseStartsAt: household.schedulePauseStartsAt,
                schedulePauseEndsAt: household.schedulePauseEndsAt)
            return PersonInsight(
                personID: person.id, name: person.name, colorHex: person.colorHex,
                completed: counts.completed, notCompleted: counts.missed,
                waiting: counts.waiting, xp: counts.xp,
                currentStreak: progress.currentStreak, level: progress.level)
        }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return WeeklyInsight(
            start: start, end: end, days: days, people: personInsights,
            observations: observations(people: personInsights, days: days))
    }

    static func recentWeeks(
        count: Int, now: Date, household: Household, people: [Person],
        quests: [Quest], completions: [QuestCompletion]
    ) -> [WeeklyInsight] {
        let calendar = ProgressionEngine.calendar(
            timeZoneIdentifier: household.timeZoneIdentifier)
        return (0..<max(1, count)).compactMap { offset in
            calendar.date(byAdding: .weekOfYear, value: -offset, to: now)
        }.map {
            week(containing: $0, now: now, household: household, people: people,
                 quests: quests, completions: completions)
        }.reversed()
    }

    private static func observations(
        people: [PersonInsight], days: [DailyInsight]
    ) -> [String] {
        var values: [String] = []
        let missed = days.reduce(0) { $0 + $1.notCompleted }
        if missed > 0 {
            values.append("\(missed) scheduled \(missed == 1 ? "quest was" : "quests were") not completed after the day ended.")
        }
        if let strongest = days.max(by: { $0.completed < $1.completed }),
           strongest.completed > 0 {
            values.append("\(strongest.date.formatted(.dateTime.weekday(.wide))) had the most completed quests this week.")
        }
        if let person = people.first(where: { $0.waiting > 0 }) {
            values.append("\(person.name) still has \(person.waiting) \(person.waiting == 1 ? "quest" : "quests") waiting today.")
        }
        if values.isEmpty {
            values.append("There is nothing that needs attention in this week’s activity yet.")
        }
        return Array(values.prefix(3))
    }
}
