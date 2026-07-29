import Foundation
import SwiftData

enum KyndynSchema {
    static let version = 3
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
        self.schemaVersion = KyndynSchema.version
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
    var devicePersonID: UUID?
    var parentSummaryEligible: Bool = false
    var quietStartHour: Int = 20
    var quietStartMinute: Int = 0
    var quietEndHour: Int = 7
    var quietEndMinute: Int = 0
    var defaultReminderHour: Int = 16
    var defaultReminderMinute: Int = 0
    var showQuestDetailsOnLockScreen: Bool = false
    init() {
        self.id = UUID()
        self.notificationsEnabled = false
        self.reducedCelebrations = false
        self.parentSummaryEligible = false
        self.quietStartHour = 20
        self.quietStartMinute = 0
        self.quietEndHour = 7
        self.quietEndMinute = 0
        self.defaultReminderHour = 16
        self.defaultReminderMinute = 0
        self.showQuestDetailsOnLockScreen = false
    }
}

// MARK: - Cloud Sync 0.3 local-only metadata

enum HouseholdCloudMode: String, Codable, CaseIterable {
    case localOnly, preparing, owner, participant, unavailable, accountChanged
    case paused, recoverableError, needsAttention
}

enum CloudDatabaseScope: String, Codable {
    case privateDatabase, sharedDatabase
}

enum ProvisioningStage: String, Codable, CaseIterable {
    case none, accountVerified, zoneReady, rootReady, initialUploadComplete
    case shareReady, roundTripVerified
}

enum SyncEntityType: String, Codable, CaseIterable {
    case household, person, quest, questSchedule, questCompletion
    case rewardGoal, householdSettings
}

enum SyncOperation: String, Codable {
    case createOrUpdate, archive
}

enum LocalSyncStatus: String, Codable {
    case localOnly, pending, synced, failed, conflicted
}

enum SyncErrorCategory: String, Codable {
    case offline, notSignedIn, restricted, accountChanged, accessRevoked
    case staleChangeToken, serverRejected, incompatibleSchema, malformedShare
    case transient, unknown
}

@Model final class HouseholdCloudState {
    @Attribute(.unique) var householdID: UUID
    var modeRaw: String = HouseholdCloudMode.localOnly.rawValue
    var databaseScopeRaw: String = CloudDatabaseScope.privateDatabase.rawValue
    var provisioningStageRaw: String = ProvisioningStage.none.rawValue
    var zoneName: String?
    var zoneOwnerName: String?
    var rootRecordName: String?
    var shareRecordName: String?
    var sharingHierarchyVersion: Int = 0
    var accountFingerprint: String?
    var changeToken: Data?
    var lastSuccessfulSyncAt: Date?
    var lastErrorCategoryRaw: String?
    var updatedAt: Date = Date()

    var mode: HouseholdCloudMode {
        get { HouseholdCloudMode(rawValue: modeRaw) ?? .localOnly }
        set { modeRaw = newValue.rawValue }
    }
    var databaseScope: CloudDatabaseScope {
        get { CloudDatabaseScope(rawValue: databaseScopeRaw) ?? .privateDatabase }
        set { databaseScopeRaw = newValue.rawValue }
    }
    var provisioningStage: ProvisioningStage {
        get { ProvisioningStage(rawValue: provisioningStageRaw) ?? .none }
        set { provisioningStageRaw = newValue.rawValue }
    }

    init(householdID: UUID) { self.householdID = householdID }
}

@Model final class SyncRecordMetadata {
    @Attribute(.unique) var id: String
    var householdID: UUID
    var entityID: UUID
    var entityTypeRaw: String
    var recordName: String
    var serverVersion: Int64 = 0
    var localModifiedAt: Date
    var lastSuccessfulSyncAt: Date?
    var statusRaw: String = LocalSyncStatus.localOnly.rawValue
    var tombstone: Bool = false
    var originDeviceID: UUID?
    var lastMutationID: UUID?

    var status: LocalSyncStatus {
        get { LocalSyncStatus(rawValue: statusRaw) ?? .localOnly }
        set { statusRaw = newValue.rawValue }
    }

    init(householdID: UUID, entityID: UUID, entityType: SyncEntityType,
         modifiedAt: Date = .now) {
        self.id = "\(entityType.rawValue):\(entityID.uuidString.lowercased())"
        self.householdID = householdID
        self.entityID = entityID
        self.entityTypeRaw = entityType.rawValue
        self.recordName = SyncIdentity.recordName(type: entityType, id: entityID)
        self.localModifiedAt = modifiedAt
    }
}

@Model final class PendingSyncMutation {
    @Attribute(.unique) var mutationID: UUID
    var householdID: UUID
    var entityID: UUID
    var entityTypeRaw: String
    var operationRaw: String
    var payload: Data
    var createdAt: Date
    var nextAttemptAt: Date
    var retryCount: Int = 0
    var lastErrorCategoryRaw: String?

    init(mutationID: UUID = UUID(), householdID: UUID, entityID: UUID,
         entityType: SyncEntityType, operation: SyncOperation, payload: Data,
         createdAt: Date = .now) {
        self.mutationID = mutationID
        self.householdID = householdID
        self.entityID = entityID
        self.entityTypeRaw = entityType.rawValue
        self.operationRaw = operation.rawValue
        self.payload = payload
        self.createdAt = createdAt
        self.nextAttemptAt = createdAt
    }
}

@Model final class SyncConflict {
    @Attribute(.unique) var id: UUID
    var householdID: UUID
    var entityID: UUID
    var entityTypeRaw: String
    var fieldName: String
    var localMutationID: UUID
    var remoteMutationID: UUID
    var createdAt: Date
    var resolvedAt: Date?

    init(householdID: UUID, entityID: UUID, entityType: SyncEntityType,
         fieldName: String, localMutationID: UUID, remoteMutationID: UUID) {
        self.id = UUID()
        self.householdID = householdID
        self.entityID = entityID
        self.entityTypeRaw = entityType.rawValue
        self.fieldName = fieldName
        self.localMutationID = localMutationID
        self.remoteMutationID = remoteMutationID
        self.createdAt = .now
    }
}

@Model final class PendingShareInvitation {
    @Attribute(.unique) var id: UUID
    var shareIdentifier: String
    var expectedSchemaVersion: Int
    var receivedAt: Date
    var stateRaw: String

    init(shareIdentifier: String, expectedSchemaVersion: Int,
         state: String = "pending") {
        self.id = UUID()
        self.shareIdentifier = shareIdentifier
        self.expectedSchemaVersion = expectedSchemaVersion
        self.receivedAt = .now
        self.stateRaw = state
    }
}
