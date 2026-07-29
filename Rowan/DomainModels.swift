import Foundation
import SwiftData

enum RowanSchema {
    static let version = 1
}

enum ProfileRole: String, Codable, CaseIterable {
    case parent, child
}

enum QuestCompletionMode: String, Codable, CaseIterable {
    case individual
    case sharedAll
}

enum ScheduleKind: String, Codable, CaseIterable {
    case oneTime
    case daily
    case weekly
}

@Model final class Household {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    var name: String
    var timeZoneIdentifier: String
    var createdAt: Date
    var deletedAt: Date?
    var rewardTitle: String
    var rewardGoalXP: Int

    init(id: UUID = UUID(), name: String, timeZoneIdentifier: String, rewardTitle: String = "Family Adventure", rewardGoalXP: Int = 300) {
        self.id = id
        self.schemaVersion = RowanSchema.version
        self.name = name
        self.timeZoneIdentifier = timeZoneIdentifier
        self.createdAt = .now
        self.rewardTitle = rewardTitle
        self.rewardGoalXP = rewardGoalXP
    }
}

@Model final class Person {
    @Attribute(.unique) var id: UUID
    var householdID: UUID
    var name: String
    var roleRaw: String
    var colorHex: String
    var companionID: String
    var createdAt: Date
    var deletedAt: Date?

    var role: ProfileRole {
        get { ProfileRole(rawValue: roleRaw) ?? .child }
        set { roleRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), householdID: UUID, name: String, role: ProfileRole, colorHex: String, companionID: String) {
        self.id = id
        self.householdID = householdID
        self.name = name
        self.roleRaw = role.rawValue
        self.colorHex = colorHex
        self.companionID = companionID
        self.createdAt = .now
    }
}

@Model final class Quest {
    @Attribute(.unique) var id: UUID
    var householdID: UUID
    var title: String
    var detail: String
    var xp: Int
    var completionModeRaw: String
    var participantIDs: [UUID]
    var scheduleKindRaw: String
    var weekdays: [Int]
    var startDate: Date
    var dueAt: Date?
    var createdAt: Date
    var deletedAt: Date?

    var completionMode: QuestCompletionMode {
        get { QuestCompletionMode(rawValue: completionModeRaw) ?? .individual }
        set { completionModeRaw = newValue.rawValue }
    }
    var scheduleKind: ScheduleKind {
        get { ScheduleKind(rawValue: scheduleKindRaw) ?? .oneTime }
        set { scheduleKindRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), householdID: UUID, title: String, detail: String = "", xp: Int, participantIDs: [UUID], completionMode: QuestCompletionMode = .individual, scheduleKind: ScheduleKind = .oneTime, weekdays: [Int] = [], startDate: Date = .now, dueAt: Date? = nil) {
        self.id = id
        self.householdID = householdID
        self.title = title
        self.detail = detail
        self.xp = xp
        self.participantIDs = participantIDs
        self.completionModeRaw = participantIDs.count == 1 ? QuestCompletionMode.individual.rawValue : completionMode.rawValue
        self.scheduleKindRaw = scheduleKind.rawValue
        self.weekdays = weekdays
        self.startDate = startDate
        self.dueAt = dueAt
        self.createdAt = .now
    }
}

@Model final class QuestCompletion {
    @Attribute(.unique) var id: UUID
    var householdID: UUID
    var questID: UUID
    var personID: UUID
    var occurrenceDay: String
    var completedAt: Date
    var awardedXP: Int
    var reversedAt: Date?

    init(id: UUID = UUID(), householdID: UUID, questID: UUID, personID: UUID, occurrenceDay: String, completedAt: Date, awardedXP: Int) {
        self.id = id
        self.householdID = householdID
        self.questID = questID
        self.personID = personID
        self.occurrenceDay = occurrenceDay
        self.completedAt = completedAt
        self.awardedXP = awardedXP
    }
}

@Model final class RewardGoal {
    @Attribute(.unique) var id: UUID
    var householdID: UUID
    var title: String
    var targetXP: Int
    var createdAt: Date
    var deletedAt: Date?
    init(householdID: UUID, title: String, targetXP: Int) {
        self.id = UUID(); self.householdID = householdID; self.title = title
        self.targetXP = targetXP; self.createdAt = .now
    }
}

@Model final class FamilyBroadcast {
    @Attribute(.unique) var id: UUID
    var householdID: UUID
    var title: String
    var message: String
    var createdAt: Date
    var expiresAt: Date?
    var deletedAt: Date?
    init(householdID: UUID, title: String, message: String) {
        self.id = UUID(); self.householdID = householdID; self.title = title
        self.message = message; self.createdAt = .now
    }
}

@Model final class Companion {
    @Attribute(.unique) var id: String
    var name: String
    var assetName: String
    var sortOrder: Int
    init(id: String, name: String, assetName: String, sortOrder: Int) {
        self.id = id; self.name = name; self.assetName = assetName; self.sortOrder = sortOrder
    }
}

@Model final class Background {
    @Attribute(.unique) var id: String
    var name: String
    var assetName: String
    init(id: String, name: String, assetName: String) {
        self.id = id; self.name = name; self.assetName = assetName
    }
}

@Model final class HouseholdSettings {
    @Attribute(.unique) var id: UUID
    var householdID: UUID
    var parentProtectionEnabled: Bool
    init(householdID: UUID) {
        self.id = UUID(); self.householdID = householdID; self.parentProtectionEnabled = true
    }
}

@Model final class LocalDeviceSettings {
    @Attribute(.unique) var id: UUID
    var selectedPersonID: UUID?
    var notificationsEnabled: Bool
    var reducedCelebrations: Bool
    init() {
        self.id = UUID(); self.notificationsEnabled = false; self.reducedCelebrations = false
    }
}

