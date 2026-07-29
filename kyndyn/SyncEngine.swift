import CloudKit
import CryptoKit
import Foundation
import Network
import Observation
import OSLog
import SwiftData

enum SyncIdentity {
    static func recordName(type: SyncEntityType, id: UUID) -> String {
        "\(type.rawValue)-\(id.uuidString.lowercased())"
    }

    static func zoneName(householdID: UUID) -> String {
        "kyndyn-household-\(householdID.uuidString.lowercased())"
    }
}

enum CloudAccountAvailability: Equatable, Sendable {
    case available(fingerprint: String)
    case noAccount
    case restricted
    case temporarilyUnavailable
}

struct FieldStamp: Codable, Equatable, Sendable, Comparable {
    let serverSequence: Int64
    let mutationID: UUID

    static func < (lhs: FieldStamp, rhs: FieldStamp) -> Bool {
        if lhs.serverSequence != rhs.serverSequence {
            return lhs.serverSequence < rhs.serverSequence
        }
        return lhs.mutationID.uuidString < rhs.mutationID.uuidString
    }
}

struct CloudRecordEnvelope: Codable, Equatable, Sendable {
    var type: SyncEntityType
    var entityID: UUID
    var householdID: UUID
    var recordName: String
    var fields: [String: String]
    var fieldStamps: [String: FieldStamp]
    var modifiedAt: Date
    var mutationID: UUID
    var serverSequence: Int64
    var tombstone: Bool
    var cloudSystemFields: Data?

    init(type: SyncEntityType, entityID: UUID, householdID: UUID,
         fields: [String: String], modifiedAt: Date = .now,
         mutationID: UUID = UUID(), serverSequence: Int64 = 0,
         tombstone: Bool = false) {
        self.type = type
        self.entityID = entityID
        self.householdID = householdID
        self.recordName = SyncIdentity.recordName(type: type, id: entityID)
        self.fields = fields
        self.modifiedAt = modifiedAt
        self.mutationID = mutationID
        self.serverSequence = serverSequence
        self.tombstone = tombstone
        self.cloudSystemFields = nil
        self.fieldStamps = Dictionary(uniqueKeysWithValues: fields.keys.map {
            ($0, FieldStamp(serverSequence: serverSequence, mutationID: mutationID))
        })
    }
}

struct RemoteChangeBatch: Equatable, Sendable {
    var records: [CloudRecordEnvelope]
    var deletedRecordNames: [String]
    var changeToken: Data?
    var moreComing: Bool
}

struct HouseholdShareDescriptor: Equatable, Sendable {
    var shareRecordName: String
    var title: String
}

struct ShareInvitation: Equatable, Sendable {
    var shareIdentifier: String
    var rootRecordName: String
    var zoneName: String = ""
    var zoneOwnerName: String? = nil
    var schemaVersion: Int
    var alreadyAccepted: Bool
}

enum CloudGatewayError: Error, Equatable, Sendable {
    case offline
    case notSignedIn
    case restricted
    case accessRevoked
    case staleChangeToken
    case incompatibleSchema
    case malformedInvitation
    case serverRejected
    case transient

    var category: SyncErrorCategory {
        switch self {
        case .offline: return .offline
        case .notSignedIn: return .notSignedIn
        case .restricted: return .restricted
        case .accessRevoked: return .accessRevoked
        case .staleChangeToken: return .staleChangeToken
        case .incompatibleSchema: return .incompatibleSchema
        case .malformedInvitation: return .malformedShare
        case .serverRejected: return .serverRejected
        case .transient: return .transient
        }
    }

    var retryable: Bool {
        switch self {
        case .offline, .transient, .staleChangeToken: return true
        default: return false
        }
    }
}

protocol CloudAccountChecking: Sendable {
    func accountAvailability() async throws -> CloudAccountAvailability
}

protocol HouseholdCloudTransport: CloudAccountChecking {
    func prepareZone(named zoneName: String, scope: CloudDatabaseScope) async throws
    func save(records: [CloudRecordEnvelope], zoneName: String,
              zoneOwnerName: String?,
              scope: CloudDatabaseScope) async throws -> [CloudRecordEnvelope]
    func fetchChanges(zoneName: String, scope: CloudDatabaseScope,
                      zoneOwnerName: String?,
                      after token: Data?) async throws -> RemoteChangeBatch
    func verifyRecord(recordName: String, zoneName: String,
                      scope: CloudDatabaseScope) async throws -> Bool
    func createShare(rootRecordName: String, zoneName: String,
                     title: String) async throws -> HouseholdShareDescriptor
    func accept(invitation: ShareInvitation) async throws
    func participantSummary(shareRecordName: String) async throws -> [String]
    func ensureChangeSubscription(zoneName: String, zoneOwnerName: String?,
                                  scope: CloudDatabaseScope) async throws
}

extension HouseholdCloudTransport {
    func ensureChangeSubscription(zoneName: String, zoneOwnerName: String?,
                                  scope: CloudDatabaseScope) async throws {}

    func save(records: [CloudRecordEnvelope], zoneName: String,
              scope: CloudDatabaseScope) async throws -> [CloudRecordEnvelope] {
        try await save(records: records, zoneName: zoneName,
                       zoneOwnerName: nil, scope: scope)
    }

    func fetchChanges(zoneName: String, scope: CloudDatabaseScope,
                      after token: Data?) async throws -> RemoteChangeBatch {
        try await fetchChanges(zoneName: zoneName, scope: scope,
                               zoneOwnerName: nil, after: token)
    }

    func verifyRecord(recordName: String, zoneName: String,
                      scope: CloudDatabaseScope) async throws -> Bool {
        let batch = try await fetchChanges(
            zoneName: zoneName, scope: scope, after: nil)
        return batch.records.contains { $0.recordName == recordName }
    }
}

struct UnconfiguredCloudTransport: HouseholdCloudTransport {
    func accountAvailability() async throws -> CloudAccountAvailability {
        .temporarilyUnavailable
    }
    func prepareZone(named: String, scope: CloudDatabaseScope) async throws {
        throw CloudGatewayError.transient
    }
    func save(records: [CloudRecordEnvelope], zoneName: String,
              zoneOwnerName: String?,
              scope: CloudDatabaseScope) async throws -> [CloudRecordEnvelope] {
        throw CloudGatewayError.transient
    }
    func fetchChanges(zoneName: String, scope: CloudDatabaseScope,
                      zoneOwnerName: String?,
                      after: Data?) async throws -> RemoteChangeBatch {
        throw CloudGatewayError.transient
    }
    func createShare(rootRecordName: String, zoneName: String,
                     title: String) async throws -> HouseholdShareDescriptor {
        throw CloudGatewayError.transient
    }
    func accept(invitation: ShareInvitation) async throws {
        throw CloudGatewayError.transient
    }
    func participantSummary(shareRecordName: String) async throws -> [String] { [] }
}

enum CloudTransportFactory {
    static func make() -> any HouseholdCloudTransport {
        switch KyndynCloudContainerFactory.make() {
        case let .success(container):
            return CloudKitHouseholdTransport(container: container)
        case .failure:
            return UnconfiguredCloudTransport()
        }
    }
}

enum InvitationRoutingState: Equatable {
    case none, pending, accepting, joined, alreadyAccepted
    case malformed, incompatible, revoked, failed
}

@MainActor
@Observable final class InvitationRouter {
    private(set) var state: InvitationRoutingState = .none
    private(set) var invitation: ShareInvitation?
    private let transport: HouseholdCloudTransport

    init(transport: HouseholdCloudTransport) { self.transport = transport }

    func receive(_ invitation: ShareInvitation) {
        self.invitation = invitation
        guard !invitation.shareIdentifier.isEmpty,
              !invitation.rootRecordName.isEmpty else {
            state = .malformed
            return
        }
        guard invitation.schemaVersion <= KyndynSchema.version else {
            state = .incompatible
            return
        }
        state = invitation.alreadyAccepted ? .alreadyAccepted : .pending
    }

    func accept() async {
        guard let invitation,
              state == .pending || state == .alreadyAccepted else { return }
        if invitation.alreadyAccepted {
            state = .alreadyAccepted
            return
        }
        state = .accepting
        do {
            try await transport.accept(invitation: invitation)
            state = .joined
        } catch CloudGatewayError.accessRevoked {
            state = .revoked
        } catch CloudGatewayError.incompatibleSchema {
            state = .incompatible
        } catch CloudGatewayError.malformedInvitation {
            state = .malformed
        } catch {
            state = .failed
        }
    }
}

enum SyncMergeEngine {
    struct MergeResult: Equatable {
        var record: CloudRecordEnvelope
        var conflictedFields: [String]
    }

    static func merge(_ lhs: CloudRecordEnvelope,
                      _ rhs: CloudRecordEnvelope) -> MergeResult {
        precondition(lhs.recordName == rhs.recordName)
        if lhs.tombstone != rhs.tombstone {
            if lhs.serverSequence == rhs.serverSequence {
                let archive = lhs.tombstone ? lhs : rhs
                return MergeResult(record: archive, conflictedFields: [])
            }
            let winner = lhs.serverSequence > rhs.serverSequence ? lhs : rhs
            return MergeResult(record: winner, conflictedFields: [])
        }
        if lhs.tombstone && rhs.tombstone {
            let winner = lhs.serverSequence >= rhs.serverSequence ? lhs : rhs
            return MergeResult(record: winner, conflictedFields: [])
        }
        var result = lhs
        var conflicts: [String] = []
        for field in Set(lhs.fields.keys).union(rhs.fields.keys) {
            let leftStamp = lhs.fieldStamps[field]
            let rightStamp = rhs.fieldStamps[field]
            guard let rightStamp else { continue }
            guard let leftStamp else {
                result.fields[field] = rhs.fields[field]
                result.fieldStamps[field] = rightStamp
                continue
            }
            if lhs.fields[field] != rhs.fields[field],
               leftStamp.serverSequence == rightStamp.serverSequence,
               leftStamp.mutationID != rightStamp.mutationID {
                conflicts.append(field)
            }
            if leftStamp < rightStamp {
                result.fields[field] = rhs.fields[field]
                result.fieldStamps[field] = rightStamp
            }
        }
        result.serverSequence = max(lhs.serverSequence, rhs.serverSequence)
        result.modifiedAt = max(lhs.modifiedAt, rhs.modifiedAt)
        result.mutationID = max(lhs.mutationID.uuidString, rhs.mutationID.uuidString)
            == lhs.mutationID.uuidString ? lhs.mutationID : rhs.mutationID
        return MergeResult(record: result, conflictedFields: conflicts.sorted())
    }
}

enum SyncPayloadCodec {
    static func encode(_ envelope: CloudRecordEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

    static func decode(_ data: Data) throws -> CloudRecordEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CloudRecordEnvelope.self, from: data)
    }
}

enum SyncSnapshot {
    static func household(_ value: Household, mutationID: UUID = UUID()) -> CloudRecordEnvelope {
        CloudRecordEnvelope(type: .household, entityID: value.id,
            householdID: value.id, fields: [
                "schemaVersion": String(value.schemaVersion),
                "name": value.name,
                "timeZoneIdentifier": value.timeZoneIdentifier,
                "createdAt": value.createdAt.ISO8601Format(),
                "deletedAt": value.deletedAt?.ISO8601Format() ?? "",
                "rewardTitle": value.rewardTitle,
                "rewardGoalXP": String(value.rewardGoalXP)
            ], mutationID: mutationID, tombstone: value.deletedAt != nil)
    }

    static func person(_ value: Person, mutationID: UUID = UUID()) -> CloudRecordEnvelope {
        CloudRecordEnvelope(type: .person, entityID: value.id,
            householdID: value.householdID, fields: [
                "name": value.name, "role": value.roleRaw,
                "colorHex": value.colorHex, "companionID": value.companionID,
                "createdAt": value.createdAt.ISO8601Format(),
                "deletedAt": value.deletedAt?.ISO8601Format() ?? ""
            ], mutationID: mutationID, tombstone: value.deletedAt != nil)
    }

    static func quest(_ value: Quest, mutationID: UUID = UUID()) -> [CloudRecordEnvelope] {
        let quest = CloudRecordEnvelope(type: .quest, entityID: value.id,
            householdID: value.householdID, fields: [
                "title": value.title, "detail": value.detail, "xp": String(value.xp),
                "completionMode": value.completionModeRaw,
                "participantIDs": value.participantIDs.map(\.uuidString).sorted().joined(separator: ","),
                "createdAt": value.createdAt.ISO8601Format(),
                "deletedAt": value.deletedAt?.ISO8601Format() ?? ""
            ], mutationID: mutationID, tombstone: value.deletedAt != nil)
        let schedule = CloudRecordEnvelope(type: .questSchedule, entityID: value.id,
            householdID: value.householdID, fields: [
                "questID": value.id.uuidString, "kind": value.scheduleKindRaw,
                "weekdays": value.weekdays.sorted().map(String.init).joined(separator: ","),
                "startDate": value.startDate.ISO8601Format(),
                "dueAt": value.dueAt?.ISO8601Format() ?? ""
            ], mutationID: UUID(), tombstone: value.deletedAt != nil)
        return [quest, schedule]
    }

    static func completion(_ value: QuestCompletion,
                           mutationID: UUID = UUID()) -> CloudRecordEnvelope {
        CloudRecordEnvelope(type: .questCompletion, entityID: value.id,
            householdID: value.householdID, fields: [
                "questID": value.questID.uuidString,
                "personID": value.personID.uuidString,
                "occurrenceDay": value.occurrenceDay,
                "completedAt": value.completedAt.ISO8601Format(),
                "awardedXP": String(value.awardedXP),
                "reversedAt": value.reversedAt?.ISO8601Format() ?? ""
            ], mutationID: mutationID)
    }

    static func reward(_ value: RewardGoal, mutationID: UUID = UUID()) -> CloudRecordEnvelope {
        CloudRecordEnvelope(type: .rewardGoal, entityID: value.id,
            householdID: value.householdID, fields: [
                "title": value.title, "targetXP": String(value.targetXP),
                "createdAt": value.createdAt.ISO8601Format(),
                "deletedAt": value.deletedAt?.ISO8601Format() ?? ""
            ], mutationID: mutationID, tombstone: value.deletedAt != nil)
    }

    static func settings(_ value: HouseholdSettings,
                         mutationID: UUID = UUID()) -> CloudRecordEnvelope {
        CloudRecordEnvelope(type: .householdSettings, entityID: value.id,
            householdID: value.householdID,
            fields: ["parentProtectionEnabled": String(value.parentProtectionEnabled)],
            mutationID: mutationID)
    }
}

@MainActor
enum SyncQueue {
    static func enqueue(_ envelope: CloudRecordEnvelope, operation: SyncOperation,
                        context: ModelContext, onlyWhenCloudEnabled: Bool = true) throws {
        if onlyWhenCloudEnabled {
            let householdID = envelope.householdID
            let states = try context.fetch(FetchDescriptor<HouseholdCloudState>(
                predicate: #Predicate { $0.householdID == householdID }
            ))
            guard let state = states.first,
                  [.preparing, .owner, .participant, .recoverableError]
                    .contains(state.mode) else { return }
        }
        let payload = try SyncPayloadCodec.encode(envelope)
        context.insert(PendingSyncMutation(
            mutationID: envelope.mutationID, householdID: envelope.householdID,
            entityID: envelope.entityID, entityType: envelope.type,
            operation: operation, payload: payload, createdAt: envelope.modifiedAt
        ))
        let metadataID = "\(envelope.type.rawValue):\(envelope.entityID.uuidString.lowercased())"
        let allMetadata = try context.fetch(FetchDescriptor<SyncRecordMetadata>())
        let metadata = allMetadata.first { $0.id == metadataID }
            ?? SyncRecordMetadata(householdID: envelope.householdID,
                                  entityID: envelope.entityID,
                                  entityType: envelope.type)
        if metadata.modelContext == nil { context.insert(metadata) }
        metadata.localModifiedAt = envelope.modifiedAt
        metadata.lastMutationID = envelope.mutationID
        metadata.tombstone = envelope.tombstone
        metadata.status = .pending
        try context.save()
        AutomaticSyncSignalCenter.shared.send(.localMutation)
    }

    static func backoff(retryCount: Int, base: TimeInterval = 2,
                        maximum: TimeInterval = 3600) -> TimeInterval {
        min(maximum, base * pow(2, Double(max(0, retryCount))))
    }
}

struct ProvisioningPreview: Equatable {
    var people: Int
    var quests: Int
    var completions: Int
    var goals: Int
    var totalRecords: Int
}

@MainActor
@Observable final class CloudSyncController {
    private(set) var isWorking = false
    private(set) var statusMessage = "Stored only on this device"
    private(set) var lastErrorCategory: SyncErrorCategory?
    private let transport: HouseholdCloudTransport
    private let notificationScheduler: NotificationScheduling

    init(transport: HouseholdCloudTransport,
         notificationScheduler: NotificationScheduling = UserNotificationScheduler()) {
        self.transport = transport
        self.notificationScheduler = notificationScheduler
    }

    func ensureChangeSubscription(for state: HouseholdCloudState) async -> Bool {
        guard let zoneName = state.zoneName,
              [.owner, .participant, .recoverableError].contains(state.mode) else {
            return false
        }
        do {
            try await transport.ensureChangeSubscription(
                zoneName: zoneName, zoneOwnerName: state.zoneOwnerName,
                scope: state.databaseScope)
            return true
        } catch {
            // Subscriptions improve promptness, but foreground and relaunch
            // catch-up remain the correctness path.
            return false
        }
    }

    func preview(household: Household, people: [Person], quests: [Quest],
                 completions: [QuestCompletion], goals: [RewardGoal]) -> ProvisioningPreview {
        ProvisioningPreview(people: people.count, quests: quests.count,
            completions: completions.count, goals: goals.count,
            totalRecords: 1 + people.count + quests.count * 2 +
                completions.count + goals.count)
    }

    func provisionOwner(household: Household, records: [CloudRecordEnvelope],
                        state: HouseholdCloudState, context: ModelContext) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        state.mode = .preparing
        state.zoneName = state.zoneName ?? SyncIdentity.zoneName(householdID: household.id)
        state.rootRecordName = SyncIdentity.recordName(type: .household, id: household.id)
        do {
            let account = try await transport.accountAvailability()
            guard case .available(let fingerprint) = account else {
                if account == .restricted { throw CloudGatewayError.restricted }
                if account == .noAccount { throw CloudGatewayError.notSignedIn }
                throw CloudGatewayError.transient
            }
            if let existing = state.accountFingerprint, existing != fingerprint {
                state.mode = .accountChanged
                throw CloudGatewayError.serverRejected
            }
            state.accountFingerprint = fingerprint
            if state.provisioningStage == .none {
                state.provisioningStage = .accountVerified
                try context.save()
            }

            let zone = state.zoneName!
            if state.provisioningStage.precedes(.zoneReady) {
                try await transport.prepareZone(
                    named: zone, scope: .privateDatabase)
                state.provisioningStage = .zoneReady
                try context.save()
            }

            if state.provisioningStage.precedes(.rootReady),
               let root = records.first(where: { $0.type == .household }) {
                _ = try await transport.save(records: [root], zoneName: zone,
                                             scope: .privateDatabase)
                state.provisioningStage = .rootReady
                try context.save()
            }

            if state.provisioningStage.precedes(.initialUploadComplete) {
                _ = try await transport.save(
                    records: records, zoneName: zone, scope: .privateDatabase)
                state.sharingHierarchyVersion = 1
                state.provisioningStage = .initialUploadComplete
                try context.save()
            }

            if state.provisioningStage.precedes(.shareReady) ||
                state.shareRecordName == nil {
                let share = try await transport.createShare(
                    rootRecordName: state.rootRecordName!, zoneName: zone,
                    title: "kyndyn family")
                state.shareRecordName = share.shareRecordName
                state.provisioningStage = .shareReady
                try context.save()
            }

            guard try await transport.verifyRecord(
                recordName: state.rootRecordName!, zoneName: zone,
                scope: .privateDatabase
            ) else { throw CloudGatewayError.serverRejected }
            state.provisioningStage = .roundTripVerified
            state.mode = .owner
            state.lastSuccessfulSyncAt = .now
            state.lastErrorCategoryRaw = nil
            statusMessage = "Family sync is on"
            lastErrorCategory = nil
            try context.save()
        } catch is CancellationError {
            statusMessage = "Waiting for the next safe sync opportunity."
            return
        } catch let error as CloudGatewayError {
            apply(error: error, state: state)
            try? context.save()
        } catch {
            apply(error: .transient, state: state)
            try? context.save()
        }
    }

    func synchronize(state: HouseholdCloudState, context: ModelContext,
                     now: Date = .now) async {
        guard let zone = state.zoneName,
              [.owner, .participant, .recoverableError].contains(state.mode),
              !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let account = try await transport.accountAvailability()
            guard case .available(let fingerprint) = account else {
                if account == .restricted { throw CloudGatewayError.restricted }
                if account == .noAccount { throw CloudGatewayError.notSignedIn }
                throw CloudGatewayError.transient
            }
            guard state.accountFingerprint == nil ||
                    state.accountFingerprint == fingerprint else {
                state.mode = .accountChanged
                statusMessage = "Your iCloud account changed. Sync is paused."
                try context.save()
                return
            }
            let householdID = state.householdID
            if state.databaseScope == .privateDatabase,
               state.sharingHierarchyVersion < 1 {
                let records = try sharingRecords(
                    householdID: householdID, context: context)
                _ = try await transport.save(
                    records: records, zoneName: zone,
                    zoneOwnerName: nil, scope: .privateDatabase)
                state.sharingHierarchyVersion = 1
                try context.save()
            }
            let pending = try context.fetch(FetchDescriptor<PendingSyncMutation>(
                predicate: #Predicate {
                    $0.householdID == householdID && $0.nextAttemptAt <= now
                }, sortBy: [SortDescriptor(\.createdAt)]
            ))
            for mutation in pending {
                let envelope = try SyncPayloadCodec.decode(mutation.payload)
                let confirmed = try await transport.save(
                    records: [envelope], zoneName: zone,
                    zoneOwnerName: state.zoneOwnerName,
                    scope: state.databaseScope)
                if !confirmed.isEmpty { context.delete(mutation) }
            }
            do {
                let changes = try await transport.fetchChanges(
                    zoneName: zone, scope: state.databaseScope,
                    zoneOwnerName: state.zoneOwnerName,
                    after: state.changeToken)
                try SyncRemoteApplier.apply(changes.records, context: context)
                await refreshRemindersIfNeeded(changes.records, context: context)
                state.changeToken = changes.changeToken
            } catch CloudGatewayError.staleChangeToken {
                state.changeToken = nil
                let changes = try await transport.fetchChanges(
                    zoneName: zone, scope: state.databaseScope,
                    zoneOwnerName: state.zoneOwnerName, after: nil)
                try SyncRemoteApplier.apply(changes.records, context: context)
                await refreshRemindersIfNeeded(changes.records, context: context)
                state.changeToken = changes.changeToken
            }
            state.mode = state.databaseScope == .privateDatabase ? .owner : .participant
            state.lastSuccessfulSyncAt = now
            state.lastErrorCategoryRaw = nil
            statusMessage = "Up to date"
            lastErrorCategory = nil
            try context.save()
        } catch is CancellationError {
            statusMessage = "Waiting for the next safe sync opportunity."
            return
        } catch let error as CloudGatewayError {
            let householdID = state.householdID
            let pending = (try? context.fetch(FetchDescriptor<PendingSyncMutation>(
                predicate: #Predicate { $0.householdID == householdID }
            ))) ?? []
            for mutation in pending {
                mutation.lastErrorCategoryRaw = error.category.rawValue
                if error.retryable {
                    mutation.retryCount += 1
                    mutation.nextAttemptAt = now.addingTimeInterval(
                        SyncQueue.backoff(retryCount: mutation.retryCount))
                }
            }
            apply(error: error, state: state)
            try? context.save()
        } catch {
            apply(error: .transient, state: state)
            try? context.save()
        }
    }

    @discardableResult
    func acceptInvitation(_ invitation: ShareInvitation,
                          context: ModelContext) async -> HouseholdCloudState? {
        guard !invitation.zoneName.isEmpty,
              invitation.schemaVersion <= KyndynSchema.version else {
            statusMessage = invitation.zoneName.isEmpty
                ? "This invitation isn’t a valid kyndyn family."
                : "Update kyndyn to join this family."
            return nil
        }
        isWorking = true
        defer { isWorking = false }
        do {
            try await transport.accept(invitation: invitation)
            let changes = try await fetchAcceptedShareChanges(
                invitation: invitation)
            guard let root = changes.records.first(where: {
                $0.type == .household &&
                $0.recordName == invitation.rootRecordName
            }) else { throw CloudGatewayError.malformedInvitation }
            try SyncRemoteApplier.apply(changes.records, context: context)
            let existing = try context.fetch(FetchDescriptor<HouseholdCloudState>())
                .first { $0.householdID == root.householdID }
            let state = existing ?? HouseholdCloudState(
                householdID: root.householdID)
            if existing == nil { context.insert(state) }
            state.mode = .participant
            state.databaseScope = .sharedDatabase
            state.zoneName = invitation.zoneName
            state.zoneOwnerName = invitation.zoneOwnerName
            state.rootRecordName = invitation.rootRecordName
            state.changeToken = changes.changeToken
            state.provisioningStage = .roundTripVerified
            state.lastSuccessfulSyncAt = .now
            statusMessage = "Joined family"
            try context.save()
            await refreshRemindersIfNeeded(changes.records, context: context)
            return state
        } catch let error as CloudGatewayError {
            lastErrorCategory = error.category
            statusMessage = error == .accessRevoked
                ? "This invitation is no longer available."
                : "kyndyn couldn’t join this family yet."
            return nil
        } catch {
            lastErrorCategory = .unknown
            statusMessage = "kyndyn couldn’t join this family yet."
            return nil
        }
    }

    private func fetchAcceptedShareChanges(
        invitation: ShareInvitation
    ) async throws -> RemoteChangeBatch {
        var lastError: CloudGatewayError = .transient
        for attempt in 0..<4 {
            do {
                return try await transport.fetchChanges(
                    zoneName: invitation.zoneName,
                    scope: .sharedDatabase,
                    zoneOwnerName: invitation.zoneOwnerName,
                    after: nil)
            } catch let error as CloudGatewayError {
                lastError = error
                guard error.retryable, attempt < 3 else { throw error }
                try await Task.sleep(
                    for: .milliseconds(500 * (1 << attempt)))
            }
        }
        throw lastError
    }

    private func sharingRecords(
        householdID: UUID, context: ModelContext
    ) throws -> [CloudRecordEnvelope] {
        guard let household = try context.fetch(FetchDescriptor<Household>())
            .first(where: { $0.id == householdID }) else {
            throw CloudGatewayError.serverRejected
        }
        var records = [SyncSnapshot.household(household)]
        records += try context.fetch(FetchDescriptor<Person>())
            .filter { $0.householdID == householdID }
            .map { SyncSnapshot.person($0) }
        records += try context.fetch(FetchDescriptor<Quest>())
            .filter { $0.householdID == householdID }
            .flatMap { SyncSnapshot.quest($0) }
        records += try context.fetch(FetchDescriptor<QuestCompletion>())
            .filter { $0.householdID == householdID }
            .map { SyncSnapshot.completion($0) }
        records += try context.fetch(FetchDescriptor<RewardGoal>())
            .filter { $0.householdID == householdID }
            .map { SyncSnapshot.reward($0) }
        records += try context.fetch(FetchDescriptor<HouseholdSettings>())
            .filter { $0.householdID == householdID }
            .map { SyncSnapshot.settings($0) }
        return records
    }

    private func refreshRemindersIfNeeded(
        _ records: [CloudRecordEnvelope], context: ModelContext
    ) async {
        guard records.contains(where: {
            [.person, .quest, .questSchedule].contains($0.type)
        }), let household = try? context.fetch(FetchDescriptor<Household>()).first,
              let settings = try? context.fetch(
                FetchDescriptor<LocalDeviceSettings>()).first else { return }
        let quests = (try? context.fetch(FetchDescriptor<Quest>())) ?? []
        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        let candidates = ReminderRules.candidates(
            quests: quests, people: people, settings: settings,
            household: household, now: .now)
        try? await notificationScheduler.replaceKyndynReminders(with: candidates)
    }

    private func apply(error: CloudGatewayError, state: HouseholdCloudState) {
        lastErrorCategory = error.category
        state.lastErrorCategoryRaw = error.category.rawValue
        state.mode = error.retryable ? .recoverableError : .needsAttention
        switch error {
        case .offline: statusMessage = "Offline. Changes will sync when you reconnect."
        case .notSignedIn: statusMessage = "Sign in to iCloud to continue family sync."
        case .restricted: statusMessage = "iCloud access is restricted on this device."
        case .accessRevoked: statusMessage = "Access to this shared family was removed."
        case .incompatibleSchema: statusMessage = "Update kyndyn to open this family."
        default: statusMessage = error.retryable
            ? "Sync paused temporarily. Your changes are safe on this device."
            : "Family sync needs your attention."
        }
    }
}

private extension ProvisioningStage {
    func precedes(_ other: ProvisioningStage) -> Bool {
        guard let current = Self.allCases.firstIndex(of: self),
              let target = Self.allCases.firstIndex(of: other) else {
            return true
        }
        return current < target
    }
}

@MainActor
enum SyncRemoteApplier {
    static func apply(_ records: [CloudRecordEnvelope],
                      context: ModelContext) throws {
        let order: [SyncEntityType: Int] = [
            .household: 0, .person: 1, .quest: 2, .questSchedule: 3,
            .questCompletion: 4, .rewardGoal: 5, .householdSettings: 6
        ]
        for record in records.sorted(by: {
            order[$0.type, default: 99] < order[$1.type, default: 99]
        }) {
            switch record.type {
            case .household:
                let id = record.entityID
                let existing = try context.fetch(FetchDescriptor<Household>(
                    predicate: #Predicate { $0.id == id }
                )).first
                let household = existing ?? Household(
                    id: id, name: record.fields["name"] ?? "Shared family",
                    timeZoneIdentifier: record.fields["timeZoneIdentifier"] ?? "UTC")
                if existing == nil { context.insert(household) }
                household.schemaVersion = Int(record.fields["schemaVersion"] ?? "")
                    ?? KyndynSchema.version
                household.name = record.fields["name"] ?? household.name
                household.timeZoneIdentifier =
                    record.fields["timeZoneIdentifier"] ?? household.timeZoneIdentifier
                household.rewardTitle =
                    record.fields["rewardTitle"] ?? household.rewardTitle
                household.rewardGoalXP = Int(record.fields["rewardGoalXP"] ?? "")
                    ?? household.rewardGoalXP
                household.deletedAt = date(record.fields["deletedAt"])
            case .person:
                let id = record.entityID
                let existing = try context.fetch(FetchDescriptor<Person>(
                    predicate: #Predicate { $0.id == id }
                )).first
                let person = existing ?? Person(
                    id: id, householdID: record.householdID,
                    name: record.fields["name"] ?? "Family member",
                    role: ProfileRole(rawValue: record.fields["role"] ?? "") ?? .child,
                    colorHex: record.fields["colorHex"] ?? "#6F2DBD",
                    companionID: record.fields["companionID"] ?? "spark")
                if existing == nil { context.insert(person) }
                person.name = record.fields["name"] ?? person.name
                person.roleRaw = record.fields["role"] ?? person.roleRaw
                person.colorHex = record.fields["colorHex"] ?? person.colorHex
                person.companionID =
                    record.fields["companionID"] ?? person.companionID
                person.deletedAt = date(record.fields["deletedAt"])
            case .quest:
                let id = record.entityID
                let participants = uuidList(record.fields["participantIDs"])
                let existing = try context.fetch(FetchDescriptor<Quest>(
                    predicate: #Predicate { $0.id == id }
                )).first
                let quest = existing ?? Quest(
                    id: id, householdID: record.householdID,
                    title: record.fields["title"] ?? "Shared quest",
                    detail: record.fields["detail"] ?? "",
                    xp: Int(record.fields["xp"] ?? "") ?? 1,
                    participantIDs: participants)
                if existing == nil { context.insert(quest) }
                quest.title = record.fields["title"] ?? quest.title
                quest.detail = record.fields["detail"] ?? quest.detail
                quest.xp = Int(record.fields["xp"] ?? "") ?? quest.xp
                quest.participantIDs = participants
                quest.completionModeRaw =
                    record.fields["completionMode"] ?? quest.completionModeRaw
                quest.deletedAt = date(record.fields["deletedAt"])
            case .questSchedule:
                let id = record.entityID
                if let quest = try context.fetch(FetchDescriptor<Quest>(
                    predicate: #Predicate { $0.id == id }
                )).first {
                    quest.scheduleKindRaw =
                        record.fields["kind"] ?? quest.scheduleKindRaw
                    quest.weekdays = intList(record.fields["weekdays"])
                    quest.startDate = date(record.fields["startDate"])
                        ?? quest.startDate
                    quest.dueAt = date(record.fields["dueAt"])
                    if record.tombstone { quest.deletedAt = record.modifiedAt }
                }
            case .questCompletion:
                let id = record.entityID
                let existing = try context.fetch(FetchDescriptor<QuestCompletion>(
                    predicate: #Predicate { $0.id == id }
                )).first
                if let existing {
                    if existing.reversedAt == nil,
                       let text = record.fields["reversedAt"], !text.isEmpty {
                        existing.reversedAt = ISO8601DateFormatter().date(from: text)
                    }
                } else if let questID = UUID(uuidString: record.fields["questID"] ?? ""),
                          let personID = UUID(uuidString: record.fields["personID"] ?? ""),
                          let completed = ISO8601DateFormatter().date(
                            from: record.fields["completedAt"] ?? "") {
                    let completion = QuestCompletion(
                        id: id, householdID: record.householdID,
                        questID: questID, personID: personID,
                        occurrenceDay: record.fields["occurrenceDay"] ?? "",
                        completedAt: completed,
                        awardedXP: Int(record.fields["awardedXP"] ?? "") ?? 0)
                    completion.reversedAt = ISO8601DateFormatter().date(
                        from: record.fields["reversedAt"] ?? "")
                    context.insert(completion)
                }
            case .rewardGoal:
                let id = record.entityID
                let existing = try context.fetch(FetchDescriptor<RewardGoal>(
                    predicate: #Predicate { $0.id == id }
                )).first
                let reward = existing ?? RewardGoal(
                    householdID: record.householdID,
                    title: record.fields["title"] ?? "Family reward",
                    targetXP: Int(record.fields["targetXP"] ?? "") ?? 1)
                if existing == nil {
                    reward.id = id
                    context.insert(reward)
                }
                reward.title = record.fields["title"] ?? reward.title
                reward.targetXP = Int(record.fields["targetXP"] ?? "")
                    ?? reward.targetXP
                reward.deletedAt = date(record.fields["deletedAt"])
            case .householdSettings:
                let id = record.entityID
                let existing = try context.fetch(FetchDescriptor<HouseholdSettings>(
                    predicate: #Predicate { $0.id == id }
                )).first
                let settings = existing ?? HouseholdSettings(
                    householdID: record.householdID)
                if existing == nil {
                    settings.id = id
                    context.insert(settings)
                }
                settings.parentProtectionEnabled =
                    record.fields["parentProtectionEnabled"] == "true"
            }
            let metadataID = "\(record.type.rawValue):\(record.entityID.uuidString.lowercased())"
            let metadata = try context.fetch(FetchDescriptor<SyncRecordMetadata>())
                .first { $0.id == metadataID }
                ?? SyncRecordMetadata(householdID: record.householdID,
                                      entityID: record.entityID,
                                      entityType: record.type)
            if metadata.modelContext == nil { context.insert(metadata) }
            metadata.serverVersion = record.serverSequence
            metadata.lastSuccessfulSyncAt = .now
            metadata.tombstone = record.tombstone
            metadata.status = .synced
        }
    }

    private static func date(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }

    private static func uuidList(_ text: String?) -> [UUID] {
        text?.split(separator: ",").compactMap {
            UUID(uuidString: String($0))
        } ?? []
    }

    private static func intList(_ text: String?) -> [Int] {
        text?.split(separator: ",").compactMap {
            Int($0)
        } ?? []
    }
}

actor InMemoryCloudTransport: HouseholdCloudTransport {
    struct StoredZone {
        var records: [String: CloudRecordEnvelope] = [:]
        var changes: [(Int64, CloudRecordEnvelope)] = []
        var sequence: Int64 = 0
    }
    private var zones: [String: StoredZone] = [:]
    private var shares: [String: String] = [:]
    private var availability: CloudAccountAvailability
    private var injectedFailures: [CloudGatewayError] = []
    private var expireTokenOnNextFetch = false
    private var subscriptions: Set<String> = []

    init(accountFingerprint: String = "test-account") {
        availability = .available(fingerprint: accountFingerprint)
    }

    func setAvailability(_ value: CloudAccountAvailability) {
        availability = value
    }

    func failNext(_ error: CloudGatewayError) {
        injectedFailures.append(error)
    }

    func expireNextChangeToken() {
        expireTokenOnNextFetch = true
    }

    func accountAvailability() async throws -> CloudAccountAvailability {
        try consumeFailure()
        return availability
    }

    func prepareZone(named zoneName: String,
                     scope: CloudDatabaseScope) async throws {
        try consumeFailure()
        if zones[zoneName] == nil { zones[zoneName] = StoredZone() }
    }

    func save(records: [CloudRecordEnvelope], zoneName: String,
              zoneOwnerName: String?,
              scope: CloudDatabaseScope) async throws -> [CloudRecordEnvelope] {
        try consumeFailure()
        var zone = zones[zoneName] ?? StoredZone()
        var confirmed: [CloudRecordEnvelope] = []
        for incoming in records {
            if let current = zone.records[incoming.recordName],
               current.mutationID == incoming.mutationID {
                confirmed.append(current)
                continue
            }
            zone.sequence += 1
            var stamped = incoming
            stamped.serverSequence = zone.sequence
            stamped.fieldStamps = Dictionary(uniqueKeysWithValues:
                stamped.fields.keys.map {
                    ($0, FieldStamp(serverSequence: zone.sequence,
                                    mutationID: stamped.mutationID))
                })
            let merged = zone.records[stamped.recordName].map {
                SyncMergeEngine.merge($0, stamped).record
            } ?? stamped
            zone.records[stamped.recordName] = merged
            zone.changes.append((zone.sequence, merged))
            confirmed.append(merged)
        }
        zones[zoneName] = zone
        return confirmed
    }

    func fetchChanges(zoneName: String, scope: CloudDatabaseScope,
                      zoneOwnerName: String?,
                      after token: Data?) async throws -> RemoteChangeBatch {
        try consumeFailure()
        if expireTokenOnNextFetch {
            expireTokenOnNextFetch = false
            throw CloudGatewayError.staleChangeToken
        }
        let sequence = token.flatMap { String(data: $0, encoding: .utf8) }
            .flatMap(Int64.init) ?? 0
        let zone = zones[zoneName] ?? StoredZone()
        let records = zone.changes.filter { $0.0 > sequence }.map(\.1)
        return RemoteChangeBatch(records: records, deletedRecordNames: [],
            changeToken: Data(String(zone.sequence).utf8), moreComing: false)
    }

    func createShare(rootRecordName: String, zoneName: String,
                     title: String) async throws -> HouseholdShareDescriptor {
        try consumeFailure()
        guard zones[zoneName]?.records[rootRecordName] != nil else {
            throw CloudGatewayError.serverRejected
        }
        let shareName = "share-\(rootRecordName)"
        shares[shareName] = rootRecordName
        return HouseholdShareDescriptor(shareRecordName: shareName, title: title)
    }

    func accept(invitation: ShareInvitation) async throws {
        try consumeFailure()
        guard invitation.schemaVersion <= KyndynSchema.version else {
            throw CloudGatewayError.incompatibleSchema
        }
        guard !invitation.shareIdentifier.isEmpty,
              !invitation.rootRecordName.isEmpty else {
            throw CloudGatewayError.malformedInvitation
        }
    }

    func participantSummary(shareRecordName: String) async throws -> [String] {
        try consumeFailure()
        return shares[shareRecordName] == nil ? [] : ["Owner", "Participant"]
    }

    func ensureChangeSubscription(zoneName: String, zoneOwnerName: String?,
                                  scope: CloudDatabaseScope) async throws {
        try consumeFailure()
        let key = scope == .sharedDatabase
            ? scope.rawValue
            : "\(scope.rawValue):\(zoneOwnerName ?? ""):\(zoneName)"
        subscriptions.insert(key)
    }

    func subscriptionCount() -> Int { subscriptions.count }

    func allRecords(zoneName: String) -> [CloudRecordEnvelope] {
        Array(zones[zoneName]?.records.values ?? [:].values)
    }

    private func consumeFailure() throws {
        guard !injectedFailures.isEmpty else { return }
        throw injectedFailures.removeFirst()
    }
}

/// Live CloudKit account boundary. Record operations are intentionally
/// unavailable until an authorized iCloud container is injected by app
/// configuration; no container identifier is guessed in source.
struct CloudKitAccountChecker: CloudAccountChecking, @unchecked Sendable {
    let container: CKContainer

    func accountAvailability() async throws -> CloudAccountAvailability {
        switch try await container.accountStatus() {
        case .available:
            let identifier = try await container.userRecordID().recordName
            let digest = SHA256.hash(data: Data(identifier.utf8))
            return .available(fingerprint: digest.map {
                String(format: "%02x", $0)
            }.joined())
        case .noAccount: return .noAccount
        case .restricted: return .restricted
        case .couldNotDetermine, .temporarilyUnavailable:
            return .temporarilyUnavailable
        @unknown default:
            return .temporarilyUnavailable
        }
    }
}

private struct UnsafeShareMetadata: @unchecked Sendable {
    let value: CKShare.Metadata
}

actor CloudKitShareMetadataVault {
    static let shared = CloudKitShareMetadataVault()
    private var values: [String: UnsafeShareMetadata] = [:]

    func store(_ metadata: CKShare.Metadata) {
        values[metadata.share.recordID.recordName] =
            UnsafeShareMetadata(value: metadata)
    }

    func value(identifier: String) -> CKShare.Metadata? {
        values[identifier]?.value
    }
}

struct CloudKitHouseholdTransport: HouseholdCloudTransport, @unchecked Sendable {
    let container: CKContainer
    private static let logger = Logger(
        subsystem: "com.kyndynfamily.kyndyn", category: "CloudKit")

    func accountAvailability() async throws -> CloudAccountAvailability {
        try await CloudKitAccountChecker(container: container).accountAvailability()
    }

    func prepareZone(named zoneName: String,
                     scope: CloudDatabaseScope) async throws {
        do {
            _ = try await database(scope).save(CKRecordZone(
                zoneID: CKRecordZone.ID(zoneName: zoneName)))
        } catch {
            throw map(error, operation: "prepare-zone")
        }
    }

    func save(records: [CloudRecordEnvelope], zoneName: String,
              zoneOwnerName: String?,
              scope: CloudDatabaseScope) async throws -> [CloudRecordEnvelope] {
        let zoneID = zoneID(name: zoneName, ownerName: zoneOwnerName)
        let cloudRecords = try records.map { envelope in
            let record: CKRecord
            if let systemFields = envelope.cloudSystemFields,
               let restored = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: CKRecord.self, from: systemFields) {
                record = restored
            } else {
                record = CKRecord(
                    recordType: cloudRecordType(envelope.type),
                    recordID: CKRecord.ID(recordName: envelope.recordName,
                                          zoneID: zoneID))
            }
            record["kyndynPayload"] = try SyncPayloadCodec.encode(envelope) as NSData
            record["householdID"] = envelope.householdID.uuidString as NSString
            record["schemaVersion"] = KyndynSchema.version as NSNumber
            record["mutationID"] = envelope.mutationID.uuidString as NSString
            record["tombstone"] = envelope.tombstone as NSNumber
            if envelope.type != .household {
                record.parent = CKRecord.Reference(
                    recordID: CKRecord.ID(
                        recordName: SyncIdentity.recordName(
                            type: .household, id: envelope.householdID),
                        zoneID: zoneID),
                    action: .none)
            }
            return record
        }
        do {
            let results = try await database(scope).modifyRecords(
                saving: cloudRecords, deleting: [], savePolicy: .changedKeys,
                atomically: false)
            return try results.saveResults.compactMap { _, result in
                let record = try result.get()
                return try envelope(from: record)
            }
        } catch {
            throw map(error, operation: "save-records")
        }
    }

    func fetchChanges(zoneName: String, scope: CloudDatabaseScope,
                      zoneOwnerName: String?,
                      after token: Data?) async throws -> RemoteChangeBatch {
        let decodedToken = token.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: CKServerChangeToken.self, from: $0)
        }
        do {
            let result = try await database(scope).recordZoneChanges(
                inZoneWith: zoneID(name: zoneName, ownerName: zoneOwnerName),
                since: decodedToken)
            let records = try result.modificationResultsByID.values.compactMap {
                change -> CloudRecordEnvelope? in
                let modification = try change.get()
                guard modification.record.recordType != CKRecord.SystemType.share,
                      modification.record["kyndynPayload"] is Data else {
                    return nil
                }
                return try envelope(from: modification.record)
            }
            let encoded = try NSKeyedArchiver.archivedData(
                withRootObject: result.changeToken,
                requiringSecureCoding: true)
            return RemoteChangeBatch(
                records: records,
                deletedRecordNames: result.deletions.map(\.recordID.recordName),
                changeToken: encoded, moreComing: result.moreComing)
        } catch let error as CKError where error.code == .changeTokenExpired {
            throw CloudGatewayError.staleChangeToken
        } catch {
            throw map(error, operation: "fetch-changes")
        }
    }

    func verifyRecord(recordName: String, zoneName: String,
                      scope: CloudDatabaseScope) async throws -> Bool {
        do {
            _ = try await database(scope).record(for: CKRecord.ID(
                recordName: recordName,
                zoneID: CKRecordZone.ID(zoneName: zoneName)))
            return true
        } catch let error as CKError where error.code == .unknownItem {
            return false
        } catch {
            throw map(error, operation: "verify-record")
        }
    }

    func createShare(rootRecordName: String, zoneName: String,
                     title: String) async throws -> HouseholdShareDescriptor {
        let database = database(.privateDatabase)
        do {
            let root = try await database.record(for: CKRecord.ID(
                recordName: rootRecordName,
                zoneID: CKRecordZone.ID(zoneName: zoneName)))
            let share = CKShare(rootRecord: root)
            share[CKShare.SystemFieldKey.title] = title as NSString
            _ = try await database.modifyRecords(
                saving: [root, share], deleting: [],
                savePolicy: .ifServerRecordUnchanged, atomically: true)
            return HouseholdShareDescriptor(
                shareRecordName: share.recordID.recordName, title: title)
        } catch let error as CKError where error.code == .serverRecordChanged {
            let shareName = "share-\(rootRecordName)"
            return HouseholdShareDescriptor(
                shareRecordName: shareName, title: title)
        } catch {
            throw map(error, operation: "create-share")
        }
    }

    func accept(invitation: ShareInvitation) async throws {
        guard let metadata = await CloudKitShareMetadataVault.shared.value(
            identifier: invitation.shareIdentifier) else {
            throw CloudGatewayError.malformedInvitation
        }
        if metadata.participantStatus == .accepted { return }
        do {
            try await container.accept(metadata)
        } catch {
            throw map(error, operation: "accept-share")
        }
    }

    func participantSummary(shareRecordName: String) async throws -> [String] {
        // Participant identities are intentionally reduced to role labels.
        // The system sharing UI remains the source for management.
        ["Owner", "Invited family members"]
    }

    func ensureChangeSubscription(zoneName: String, zoneOwnerName: String?,
                                  scope: CloudDatabaseScope) async throws {
        let zone = zoneID(name: zoneName, ownerName: zoneOwnerName)
        let identity = scope == .sharedDatabase
            ? scope.rawValue
            : "\(scope.rawValue):\(zone.ownerName):\(zone.zoneName)"
        let digest = SHA256.hash(data: Data(identity.utf8))
        let identifier = "kyndyn-zone-" + digest.prefix(12).map {
            String(format: "%02x", $0)
        }.joined()
        let database = database(scope)
        do {
            _ = try await database.subscription(for: identifier)
        } catch let error as CKError where error.code == .unknownItem {
            let subscription: CKSubscription = scope == .sharedDatabase
                ? CKDatabaseSubscription(subscriptionID: identifier)
                : CKRecordZoneSubscription(
                    zoneID: zone, subscriptionID: identifier)
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            subscription.notificationInfo = info
            do {
                _ = try await database.save(subscription)
            } catch {
                throw map(error, operation: "save-subscription")
            }
        } catch {
            throw map(error, operation: "fetch-subscription")
        }
    }

    private func database(_ scope: CloudDatabaseScope) -> CKDatabase {
        scope == .privateDatabase
            ? container.privateCloudDatabase : container.sharedCloudDatabase
    }

    private func zoneID(name: String, ownerName: String?) -> CKRecordZone.ID {
        if let ownerName, !ownerName.isEmpty {
            return CKRecordZone.ID(zoneName: name, ownerName: ownerName)
        }
        return CKRecordZone.ID(zoneName: name)
    }

    private func cloudRecordType(_ type: SyncEntityType) -> String {
        switch type {
        case .household: return "kyndynHousehold"
        case .person: return "kyndynPerson"
        case .quest: return "kyndynQuest"
        case .questSchedule: return "kyndynQuestSchedule"
        case .questCompletion: return "kyndynQuestCompletion"
        case .rewardGoal: return "kyndynRewardGoal"
        case .householdSettings: return "kyndynHouseholdSettings"
        }
    }

    private func envelope(from record: CKRecord) throws -> CloudRecordEnvelope {
        guard let data = record["kyndynPayload"] as? Data else {
            throw CloudGatewayError.serverRejected
        }
        var value = try SyncPayloadCodec.decode(data)
        value.cloudSystemFields = try NSKeyedArchiver.archivedData(
            withRootObject: record, requiringSecureCoding: true)
        return value
    }

    private func map(_ error: Error, operation: StaticString) -> CloudGatewayError {
        if let gatewayError = error as? CloudGatewayError {
            return gatewayError
        }
        guard let cloudError = error as? CKError else {
            Self.logger.error(
                "\(operation): non-CloudKit failure \(String(describing: type(of: error)), privacy: .public)")
            return .transient
        }
        Self.logger.error(
            "\(operation): CKError code \(cloudError.errorCode, privacy: .public)")
        switch cloudError.code {
        case .networkUnavailable, .networkFailure: return .offline
        case .notAuthenticated: return .notSignedIn
        case .permissionFailure: return .accessRevoked
        case .changeTokenExpired: return .staleChangeToken
        case .serverRejectedRequest, .invalidArguments: return .serverRejected
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return .transient
        default: return .transient
        }
    }
}

enum AutomaticSyncTrigger: String, Hashable, Sendable {
    case launch
    case becameActive
    case returnedToForeground
    case localMutation
    case connectivityRestored
    case remoteNotification
    case shareAccepted
    case accountRecovery
    case backgroundRefresh
    case foregroundCatchUp
    case manual

    var shouldDebounce: Bool { self == .localMutation }
}

extension Notification.Name {
    static let kyndynAutomaticSyncRequested =
        Notification.Name("com.kyndynfamily.kyndyn.automatic-sync-requested")
}

@MainActor
final class AutomaticSyncSignalCenter {
    static let shared = AutomaticSyncSignalCenter()

    func send(_ trigger: AutomaticSyncTrigger) {
        NotificationCenter.default.post(
            name: .kyndynAutomaticSyncRequested,
            object: nil,
            userInfo: ["trigger": trigger.rawValue])
    }
}

enum AutomaticSyncDisplayState: Equatable {
    case localOnly
    case waiting
    case synchronizing
    case upToDate(Date)
    case offline
    case needsAttention
}

@MainActor
@Observable final class AutomaticSyncCoordinator {
    typealias Run = @MainActor () async -> Void

    private(set) var displayState: AutomaticSyncDisplayState = .localOnly
    private(set) var isRunning = false
    private(set) var completedRunCount = 0
    private(set) var lastTriggers: Set<AutomaticSyncTrigger> = []

    private let debounceNanoseconds: UInt64
    private var run: Run?
    private var pendingTriggers: Set<AutomaticSyncTrigger> = []
    private var scheduledTask: Task<Void, Never>?
    private var consecutiveRetryCount = 0

    init(debounceNanoseconds: UInt64 = 650_000_000) {
        self.debounceNanoseconds = debounceNanoseconds
    }

    func configure(run: @escaping Run) {
        self.run = run
    }

    func configure(controller: CloudSyncController, context: ModelContext) {
        configure { [weak self] in
            let states = (try? context.fetch(
                FetchDescriptor<HouseholdCloudState>())) ?? []
            let eligible = states.filter {
                [.owner, .participant, .recoverableError].contains($0.mode)
            }
            guard !eligible.isEmpty else {
                self?.displayState = .localOnly
                return
            }
            var subscriptionReady = true
            for state in eligible {
                if Task.isCancelled { return }
                subscriptionReady =
                    await controller.ensureChangeSubscription(for: state)
                    && subscriptionReady
                if Task.isCancelled { return }
                await controller.synchronize(state: state, context: context)
            }
            if controller.lastErrorCategory == .offline {
                self?.displayState = .offline
            } else if controller.lastErrorCategory == .transient ||
                        controller.lastErrorCategory == .staleChangeToken {
                self?.displayState = .waiting
            } else if let error = controller.lastErrorCategory,
                      ![.offline, .transient, .staleChangeToken].contains(error) {
                self?.displayState = .needsAttention
            } else if let date = eligible.compactMap(\.lastSuccessfulSyncAt).max() {
                self?.displayState = .upToDate(date)
            } else {
                self?.displayState = .waiting
            }
            _ = subscriptionReady
        }
    }

    func request(_ trigger: AutomaticSyncTrigger) {
        pendingTriggers.insert(trigger)
        displayState = .waiting
        guard !isRunning else { return }

        let delay = pendingTriggers.allSatisfy(\.shouldDebounce)
            ? debounceNanoseconds : 0
        scheduledTask?.cancel()
        scheduledTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled else { return }
            await self?.drain()
        }
    }

    func cancelForBackgroundExpiration() {
        scheduledTask?.cancel()
        scheduledTask = nil
        if isRunning { displayState = .waiting }
    }

    func waitUntilIdle() async {
        while isRunning || !pendingTriggers.isEmpty {
            await Task.yield()
        }
    }

    private func drain() async {
        guard !isRunning, let run else { return }
        isRunning = true
        while !pendingTriggers.isEmpty, !Task.isCancelled {
            lastTriggers = pendingTriggers
            pendingTriggers.removeAll()
            displayState = .synchronizing
            await run()
            completedRunCount += 1
        }
        isRunning = false
        scheduledTask = nil
        if displayState == .waiting, !Task.isCancelled {
            consecutiveRetryCount = min(consecutiveRetryCount + 1, 5)
            let seconds = min(60, 2 << (consecutiveRetryCount - 1))
            scheduledTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                self?.scheduledTask = nil
                self?.request(.accountRecovery)
            }
        } else if case .upToDate = displayState {
            consecutiveRetryCount = 0
        }
    }
}

final class ConnectivityRestorationMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(
        label: "com.kyndynfamily.kyndyn.connectivity")
    private var wasUnavailable = false

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            if path.status == .satisfied {
                if self.wasUnavailable {
                    Task { @MainActor in
                        AutomaticSyncSignalCenter.shared.send(
                            .connectivityRestored)
                    }
                }
                self.wasUnavailable = false
            } else {
                self.wasUnavailable = true
            }
        }
        monitor.start(queue: queue)
    }

    func cancel() { monitor.cancel() }
}
