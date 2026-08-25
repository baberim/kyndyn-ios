import Foundation
import SwiftData
import XCTest
@testable import kyndyn

private actor InterruptingTransport: HouseholdCloudTransport {
    let base: InMemoryCloudTransport
    var calls = 0
    var failureCall: Int?

    init(failureCall: Int?) {
        self.failureCall = failureCall
        self.base = InMemoryCloudTransport()
    }

    private func interruptIfNeeded() throws {
        calls += 1
        if calls == failureCall {
            failureCall = nil
            throw CloudGatewayError.offline
        }
    }

    func accountAvailability() async throws -> CloudAccountAvailability {
        try interruptIfNeeded()
        return try await base.accountAvailability()
    }
    func prepareZone(named name: String, scope: CloudDatabaseScope) async throws {
        try interruptIfNeeded()
        try await base.prepareZone(named: name, scope: scope)
    }
    func save(records: [CloudRecordEnvelope], zoneName: String,
              zoneOwnerName: String?,
              scope: CloudDatabaseScope) async throws -> [CloudRecordEnvelope] {
        try interruptIfNeeded()
        return try await base.save(
            records: records, zoneName: zoneName,
            zoneOwnerName: zoneOwnerName, scope: scope)
    }
    func fetchChanges(zoneName: String, scope: CloudDatabaseScope,
                      zoneOwnerName: String?,
                      after token: Data?) async throws -> RemoteChangeBatch {
        try interruptIfNeeded()
        return try await base.fetchChanges(
            zoneName: zoneName, scope: scope,
            zoneOwnerName: zoneOwnerName, after: token)
    }
    func createShare(rootRecordName: String, zoneName: String,
                     title: String) async throws -> HouseholdShareDescriptor {
        try interruptIfNeeded()
        return try await base.createShare(rootRecordName: rootRecordName,
                                          zoneName: zoneName, title: title)
    }
    func accept(invitation: ShareInvitation) async throws {
        try interruptIfNeeded()
        try await base.accept(invitation: invitation)
    }
    func participantSummary(shareRecordName: String) async throws -> [String] {
        try interruptIfNeeded()
        return try await base.participantSummary(shareRecordName: shareRecordName)
    }
}

private actor PaginatedTransport: HouseholdCloudTransport {
    let records: [CloudRecordEnvelope]
    let pageSize: Int

    init(records: [CloudRecordEnvelope], pageSize: Int = 1) {
        self.records = records
        self.pageSize = pageSize
    }

    func accountAvailability() async throws -> CloudAccountAvailability {
        .available(fingerprint: "paged-test-account")
    }

    func prepareZone(named: String, scope: CloudDatabaseScope) async throws {}

    func save(records: [CloudRecordEnvelope], zoneName: String,
              zoneOwnerName: String?, scope: CloudDatabaseScope) async throws
        -> [CloudRecordEnvelope] { records }

    func fetchChanges(zoneName: String, scope: CloudDatabaseScope,
                      zoneOwnerName: String?, after token: Data?) async throws
        -> RemoteChangeBatch {
        let start = token.flatMap { String(data: $0, encoding: .utf8) }
            .flatMap(Int.init) ?? 0
        let end = min(records.count, start + pageSize)
        return RemoteChangeBatch(
            records: Array(records[start..<end]),
            deletedRecordNames: [],
            changeToken: Data(String(end).utf8),
            moreComing: end < records.count)
    }

    func createShare(rootRecordName: String, zoneName: String,
                     title: String) async throws -> HouseholdShareDescriptor {
        HouseholdShareDescriptor(shareRecordName: "paged-share", title: title)
    }
    func accept(invitation: ShareInvitation) async throws {}
    func participantSummary(shareRecordName: String) async throws -> [String] { [] }
}

private actor ExplicitPageTransport: HouseholdCloudTransport {
    let pages: [RemoteChangeBatch]

    init(pages: [RemoteChangeBatch]) { self.pages = pages }

    func accountAvailability() async throws -> CloudAccountAvailability {
        .available(fingerprint: "explicit-page-account")
    }
    func prepareZone(named: String, scope: CloudDatabaseScope) async throws {}
    func save(records: [CloudRecordEnvelope], zoneName: String,
              zoneOwnerName: String?, scope: CloudDatabaseScope) async throws
        -> [CloudRecordEnvelope] { records }
    func fetchChanges(zoneName: String, scope: CloudDatabaseScope,
                      zoneOwnerName: String?, after token: Data?) async throws
        -> RemoteChangeBatch {
        let index = token.flatMap { String(data: $0, encoding: .utf8) }
            .flatMap(Int.init) ?? 0
        return pages[index]
    }
    func createShare(rootRecordName: String, zoneName: String,
                     title: String) async throws -> HouseholdShareDescriptor {
        HouseholdShareDescriptor(shareRecordName: "explicit-share", title: title)
    }
    func accept(invitation: ShareInvitation) async throws {}
    func participantSummary(shareRecordName: String) async throws -> [String] { [] }
}

private actor RecordingNotificationScheduler: NotificationScheduling {
    private(set) var replacements = 0
    private(set) var latest: [ReminderCandidate] = []
    private(set) var broadcastIDs: [UUID] = []
    func permissionState() async -> NotificationPermissionState { .authorized }
    func requestPermission() async -> NotificationPermissionState { .authorized }
    func replaceKyndynReminders(with candidates: [ReminderCandidate]) async throws {
        replacements += 1
        latest = candidates
    }
    func notifyBroadcast(
        id: UUID, title: String, message: String, showDetails: Bool
    ) async throws {
        broadcastIDs.append(id)
    }
}

@MainActor
final class SyncMetadataAndQueueTests: XCTestCase {
    func testSyncHealthSummaryIsPrivacySafeAndDeterministic() {
        let state = HouseholdCloudState(householdID: UUID())
        state.mode = .owner
        state.lastSuccessfulSyncAt = Date(timeIntervalSince1970: 1_000)

        let healthy = SyncHealthSummary.make(
            state: state, pendingCount: 0,
            now: Date(timeIntervalSince1970: 1_030))
        XCTAssertEqual(healthy.title, "No problems detected")
        XCTAssertEqual(healthy.detail, "A sync finished just now.")
        XCTAssertEqual(healthy.tone, .healthy)

        let waiting = SyncHealthSummary.make(state: state, pendingCount: 2)
        XCTAssertEqual(waiting.title, "Waiting to finish")
        XCTAssertTrue(waiting.detail.contains("2 local changes"))
        XCTAssertFalse(waiting.detail.contains(state.householdID.uuidString))
    }

    func testSyncHealthSummaryExplainsActionableFailureWithoutRawError() {
        let state = HouseholdCloudState(householdID: UUID())
        state.mode = .needsAttention
        state.lastErrorCategoryRaw = SyncErrorCategory.accessRevoked.rawValue

        let summary = SyncHealthSummary.make(state: state, pendingCount: 0)
        XCTAssertEqual(summary.title, "Family sync needs attention")
        XCTAssertEqual(summary.detail,
                       "Access to the shared household was removed.")
        XCTAssertEqual(summary.tone, .attention)
    }

    private func schema() -> Schema {
        Schema([
            Household.self, Person.self, Quest.self, QuestCompletion.self,
            RewardGoal.self, FamilyBroadcast.self, Companion.self,
            Background.self, HouseholdSettings.self, LocalDeviceSettings.self,
            LocalQuestReminder.self,
            HouseholdImportReceipt.self,
            HouseholdCloudState.self, SyncRecordMetadata.self,
            PendingSyncMutation.self, SyncConflict.self,
            PendingShareInvitation.self
        ])
    }

    private func container() throws -> ModelContainer {
        try ModelContainer(for: schema(), configurations:
            ModelConfiguration(
                schema: schema(), isStoredInMemoryOnly: true,
                cloudKitDatabase: .none))
    }

    func testLocalOnlyHouseholdDoesNotQueueOrRequireCloud() throws {
        let container = try container()
        let context = container.mainContext
        let household = Household(name: "Fictional Family", timeZoneIdentifier: "UTC")
        let person = Person(householdID: household.id, name: "Avery",
                            role: .parent, colorHex: "#000", companionID: "spark")
        context.insert(household); context.insert(person)
        try context.save()
        try SyncQueue.enqueue(SyncSnapshot.person(person),
                              operation: .createOrUpdate, context: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingSyncMutation>()).isEmpty)
        XCTAssertEqual(household.name, "Fictional Family")
    }

    func testEnabledHouseholdQueuesIdempotentPayloadWithoutDeviceSettings() throws {
        let container = try container()
        let context = container.mainContext
        let household = Household(name: "Test Household", timeZoneIdentifier: "UTC")
        let person = Person(householdID: household.id, name: "Alex",
                            role: .child, colorHex: "#123", companionID: "spark")
        person.earnedCompanionIDs = CollectionCatalog.normalizedCompanions(["penguin"])
        person.backgroundID = "aquarium"
        person.earnedBackgroundIDs = CollectionCatalog.normalizedBackgrounds(["aquarium"])
        person.earnedBadgeIDs = RecognitionEngine.normalizedBadges(["first-step"])
        person.startingXPAdjustment = 619
        let state = HouseholdCloudState(householdID: household.id)
        state.mode = .owner
        context.insert(household); context.insert(person); context.insert(state)
        context.insert(LocalDeviceSettings())
        try context.save()
        let envelope = SyncSnapshot.person(person,
            mutationID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!)
        try SyncQueue.enqueue(envelope, operation: .createOrUpdate, context: context)
        let mutation = try XCTUnwrap(
            context.fetch(FetchDescriptor<PendingSyncMutation>()).first)
        let decoded = try SyncPayloadCodec.decode(mutation.payload)
        XCTAssertEqual(decoded.recordName, envelope.recordName)
        XCTAssertEqual(decoded.fields, envelope.fields)
        XCTAssertEqual(decoded.mutationID, envelope.mutationID)
        XCTAssertEqual(decoded.fields["backgroundID"], "aquarium")
        XCTAssertTrue(decoded.fields["earnedCompanionIDs"]?.contains("penguin") == true)
        XCTAssertTrue(decoded.fields["earnedBackgroundIDs"]?.contains("aquarium") == true)
        XCTAssertEqual(decoded.fields["earnedBadgeIDs"], "first-step")
        XCTAssertEqual(decoded.fields["startingXPAdjustment"], "619")
        let text = String(data: mutation.payload, encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("quietStart"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("pin"))
        XCTAssertEqual(mutation.mutationID, envelope.mutationID)
    }

    func testQuestAndScheduleUseDistinctQueueMutationIdentities() throws {
        let container = try container()
        let context = container.mainContext
        let household = Household(
            name: "Fictional Family", timeZoneIdentifier: "UTC")
        let state = HouseholdCloudState(householdID: household.id)
        state.mode = .owner
        let quest = Quest(
            householdID: household.id, title: "Test both cloud records",
            xp: 10, participantIDs: [], scheduleKind: .daily)
        context.insert(household)
        context.insert(state)
        context.insert(quest)
        try context.save()

        for envelope in SyncSnapshot.quest(quest) {
            try SyncQueue.enqueue(
                envelope, operation: .createOrUpdate, context: context)
        }

        let pending = try context.fetch(
            FetchDescriptor<PendingSyncMutation>())
        XCTAssertEqual(pending.count, 2)
        XCTAssertEqual(Set(pending.map(\.mutationID)).count, 2)
        XCTAssertEqual(
            Set(pending.map(\.entityTypeRaw)),
            [SyncEntityType.quest.rawValue,
             SyncEntityType.questSchedule.rawValue])
    }

    func testBackoffIsCappedAndDeterministic() {
        XCTAssertEqual(SyncQueue.backoff(retryCount: 0), 2)
        XCTAssertEqual(SyncQueue.backoff(retryCount: 3), 16)
        XCTAssertEqual(SyncQueue.backoff(retryCount: 99), 3600)
    }

    nonisolated func testSynchronizationConsumesEveryRemotePageBeforeAdvancingToken() async throws {
        let householdID = UUID()
        let records = (0..<3).map { index in
            CloudRecordEnvelope(
                type: .person, entityID: UUID(), householdID: householdID,
                fields: ["name": "Person \(index)"])
        }
        let transport = PaginatedTransport(records: [
            records[0], records[1], records[2]
        ])
        let batch = try await transport.fetchAllChanges(
            zoneName: "kyndyn-household-paged", scope: .privateDatabase,
            zoneOwnerName: nil, after: nil)

        XCTAssertEqual(batch.records.count, 3)
        XCTAssertEqual(Set(batch.records.map(\.recordName)).count, 3)
        XCTAssertEqual(
            String(data: try XCTUnwrap(batch.changeToken), encoding: .utf8),
            "3")
        XCTAssertFalse(batch.moreComing)
    }

    nonisolated func testFullRecoveryKeepsNewestRevisionAcrossPages() async throws {
        let householdID = UUID()
        let personID = UUID()
        let old = CloudRecordEnvelope(
            type: .person, entityID: personID, householdID: householdID,
            fields: ["name": "Avery", "startingXPAdjustment": "100"])
        let newest = CloudRecordEnvelope(
            type: .person, entityID: personID, householdID: householdID,
            fields: ["name": "Avery", "startingXPAdjustment": "875"])
        let transport = ExplicitPageTransport(pages: [
            RemoteChangeBatch(
                records: [old], deletedRecordNames: [],
                changeToken: Data("1".utf8), moreComing: true),
            RemoteChangeBatch(
                records: [newest], deletedRecordNames: [],
                changeToken: Data("2".utf8), moreComing: false)
        ])

        let batch = try await transport.fetchAllChanges(
            zoneName: "kyndyn-household-history", scope: .privateDatabase,
            zoneOwnerName: nil, after: nil)

        XCTAssertEqual(batch.records.count, 1)
        XCTAssertEqual(batch.records.first?.fields["startingXPAdjustment"], "875")
        XCTAssertEqual(
            String(data: try XCTUnwrap(batch.changeToken), encoding: .utf8),
            "2")
    }

    func testAdditiveSchemaOpensLocalCoreDataWithoutCloudRows() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "kyndyn.store")
        let oldSchema = Schema([
            Household.self, Person.self, Quest.self, QuestCompletion.self,
            RewardGoal.self, FamilyBroadcast.self, Companion.self,
            Background.self, HouseholdSettings.self, LocalDeviceSettings.self
        ])
        do {
            let old = try ModelContainer(for: oldSchema,
                configurations: ModelConfiguration(
                    schema: oldSchema, url: url, cloudKitDatabase: .none))
            old.mainContext.insert(Household(
                name: "Pre 0.3 Fictional", timeZoneIdentifier: "UTC"))
            try old.mainContext.save()
        }
        let migrated = try ModelContainer(for: schema(),
            configurations: ModelConfiguration(
                schema: schema(), url: url, cloudKitDatabase: .none))
        XCTAssertEqual(try migrated.mainContext.fetch(
            FetchDescriptor<Household>()).first?.name, "Pre 0.3 Fictional")
        XCTAssertTrue(try migrated.mainContext.fetch(
            FetchDescriptor<HouseholdCloudState>()).isEmpty)
    }
}

@MainActor
final class AutomaticSyncCoordinatorTests: XCTestCase {
    func testRapidMutationTriggersAreDebouncedAndCoalesced() async {
        let coordinator = AutomaticSyncCoordinator(
            debounceNanoseconds: 20_000_000)
        var runs = 0
        coordinator.configure { runs += 1 }

        coordinator.request(.localMutation)
        coordinator.request(.localMutation)
        coordinator.request(.localMutation)
        await coordinator.waitUntilIdle()

        XCTAssertEqual(runs, 1)
        XCTAssertEqual(coordinator.completedRunCount, 1)
        XCTAssertEqual(coordinator.lastTriggers, [.localMutation])
    }

    func testTriggerDuringRunDoesNotOverlapAndRunsOnceMore() async {
        let coordinator = AutomaticSyncCoordinator(debounceNanoseconds: 0)
        var active = 0
        var maximumActive = 0
        var runs = 0
        coordinator.configure {
            active += 1
            maximumActive = max(maximumActive, active)
            runs += 1
            if runs == 1 {
                coordinator.request(.remoteNotification)
                coordinator.request(.becameActive)
            }
            await Task.yield()
            active -= 1
        }

        coordinator.request(.launch)
        await coordinator.waitUntilIdle()

        XCTAssertEqual(maximumActive, 1)
        XCTAssertEqual(runs, 2)
        XCTAssertEqual(coordinator.lastTriggers,
                       [.remoteNotification, .becameActive])
    }

    func testImmediateTriggerPreemptsMutationDebounce() async {
        let coordinator = AutomaticSyncCoordinator(
            debounceNanoseconds: 1_000_000_000)
        var runs = 0
        coordinator.configure { runs += 1 }

        coordinator.request(.localMutation)
        coordinator.request(.remoteNotification)
        await coordinator.waitUntilIdle()

        XCTAssertEqual(runs, 1)
        XCTAssertEqual(coordinator.lastTriggers,
                       [.localMutation, .remoteNotification])
    }

    func testSubscriptionCreationIsIdempotentAcrossRepairCalls() async throws {
        let transport = InMemoryCloudTransport()
        try await transport.ensureChangeSubscription(
            zoneName: "fictional-zone", zoneOwnerName: nil,
            scope: .privateDatabase)
        try await transport.ensureChangeSubscription(
            zoneName: "fictional-zone", zoneOwnerName: nil,
            scope: .privateDatabase)

        let subscriptionCount = await transport.subscriptionCount()
        XCTAssertEqual(subscriptionCount, 1)
    }

    func testSharedDatabaseUsesOneSubscriptionAcrossKnownZones() async throws {
        let transport = InMemoryCloudTransport()
        try await transport.ensureChangeSubscription(
            zoneName: "first-shared-zone", zoneOwnerName: "fictional-owner",
            scope: .sharedDatabase)
        try await transport.ensureChangeSubscription(
            zoneName: "second-shared-zone", zoneOwnerName: "fictional-owner",
            scope: .sharedDatabase)

        let subscriptionCount = await transport.subscriptionCount()
        XCTAssertEqual(subscriptionCount, 1)
    }

    func testSubscriptionFailureDoesNotDisableLocalQueue() async throws {
        let transport = InMemoryCloudTransport()
        await transport.failNext(.transient)
        do {
            try await transport.ensureChangeSubscription(
                zoneName: "fictional-zone", zoneOwnerName: nil,
                scope: .privateDatabase)
            XCTFail("Expected injected subscription failure")
        } catch {
            XCTAssertEqual(error as? CloudGatewayError, .transient)
        }

        try await transport.prepareZone(
            named: "fictional-zone", scope: .privateDatabase)
        let subscriptionCount = await transport.subscriptionCount()
        XCTAssertEqual(subscriptionCount, 0)
    }
}

final class SyncMergeTests: XCTestCase {
    private let householdID = UUID(uuidString:
        "11111111-1111-1111-1111-111111111111")!
    private let entityID = UUID(uuidString:
        "22222222-2222-2222-2222-222222222222")!

    func testStableIdentityAndNonOverlappingFieldsMerge() {
        let leftID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let rightID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        var left = CloudRecordEnvelope(type: .person, entityID: entityID,
            householdID: householdID, fields: ["name": "Avery"],
            mutationID: leftID, serverSequence: 2)
        var right = CloudRecordEnvelope(type: .person, entityID: entityID,
            householdID: householdID, fields: ["colorHex": "#123456"],
            mutationID: rightID, serverSequence: 3)
        left.fieldStamps["name"] = FieldStamp(serverSequence: 2, mutationID: leftID)
        right.fieldStamps["colorHex"] = FieldStamp(serverSequence: 3, mutationID: rightID)
        let merged = SyncMergeEngine.merge(left, right)
        XCTAssertEqual(merged.record.fields["name"], "Avery")
        XCTAssertEqual(merged.record.fields["colorHex"], "#123456")
        XCTAssertTrue(merged.conflictedFields.isEmpty)
        XCTAssertEqual(merged.record.recordName,
            "person-22222222-2222-2222-2222-222222222222")
    }

    func testSameFieldTieIsDeterministicAndReported() {
        let lower = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let higher = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let left = CloudRecordEnvelope(type: .quest, entityID: entityID,
            householdID: householdID, fields: ["title": "Morning"],
            mutationID: lower, serverSequence: 4)
        let right = CloudRecordEnvelope(type: .quest, entityID: entityID,
            householdID: householdID, fields: ["title": "Before school"],
            mutationID: higher, serverSequence: 4)
        let forward = SyncMergeEngine.merge(left, right)
        let reverse = SyncMergeEngine.merge(right, left)
        XCTAssertEqual(forward.record.fields["title"], reverse.record.fields["title"])
        XCTAssertEqual(forward.conflictedFields, ["title"])
    }

    func testArchiveWinsOverConcurrentEdit() {
        let edit = CloudRecordEnvelope(type: .person, entityID: entityID,
            householdID: householdID, fields: ["name": "Edited"])
        let archive = CloudRecordEnvelope(type: .person, entityID: entityID,
            householdID: householdID, fields: ["name": "Old"], tombstone: true)
        XCTAssertTrue(SyncMergeEngine.merge(edit, archive).record.tombstone)
        XCTAssertTrue(SyncMergeEngine.merge(archive, edit).record.tombstone)
    }

    func testLaterExplicitRestoreWinsButConcurrentArchiveWins() {
        var archive = CloudRecordEnvelope(
            type: .quest, entityID: entityID, householdID: householdID,
            fields: ["title": "Archived"], serverSequence: 5,
            tombstone: true
        )
        var restore = CloudRecordEnvelope(
            type: .quest, entityID: entityID, householdID: householdID,
            fields: ["title": "Restored"], serverSequence: 6,
            tombstone: false
        )
        XCTAssertFalse(SyncMergeEngine.merge(archive, restore).record.tombstone)
        XCTAssertFalse(SyncMergeEngine.merge(restore, archive).record.tombstone)

        restore.serverSequence = 5
        archive.serverSequence = 5
        XCTAssertTrue(SyncMergeEngine.merge(archive, restore).record.tombstone)
        XCTAssertTrue(SyncMergeEngine.merge(restore, archive).record.tombstone)
    }
}

@MainActor
final class ACloudProvisioningAndLifecycleTests: XCTestCase {
    private func fixture() throws -> (ModelContainer, Household,
        HouseholdCloudState, [CloudRecordEnvelope]) {
        let schema = Schema([
            Household.self, Person.self, Quest.self, QuestCompletion.self,
            RewardGoal.self, FamilyBroadcast.self, Companion.self,
            Background.self, HouseholdSettings.self, LocalDeviceSettings.self,
            LocalQuestReminder.self,
            HouseholdImportReceipt.self,
            HouseholdCloudState.self, SyncRecordMetadata.self,
            PendingSyncMutation.self, SyncConflict.self,
            PendingShareInvitation.self
        ])
        let container = try ModelContainer(for: schema, configurations:
            ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true,
                cloudKitDatabase: .none))
        let household = Household(name: "Provision Test", timeZoneIdentifier: "UTC")
        let state = HouseholdCloudState(householdID: household.id)
        container.mainContext.insert(household)
        container.mainContext.insert(state)
        try container.mainContext.save()
        return (container, household, state, [SyncSnapshot.household(household)])
    }

    func testHouseholdSchedulePauseSnapshotRoundTrips() throws {
        let (container, household, _, _) = try fixture()
        let start = Date(timeIntervalSince1970: 1_786_320_000)
        let end = start.addingTimeInterval(3 * 86_400)
        household.schedulePauseStartsAt = start
        household.schedulePauseEndsAt = end
        let snapshot = SyncSnapshot.household(household)
        container.mainContext.delete(household)
        try container.mainContext.save()
        try SyncRemoteApplier.apply([snapshot], context: container.mainContext)
        let restored = try container.mainContext.fetch(
            FetchDescriptor<Household>()).first
        XCTAssertEqual(restored?.schedulePauseStartsAt, start)
        XCTAssertEqual(restored?.schedulePauseEndsAt, end)
    }

    func testOwnerProvisioningAndDuplicateAttemptAreIdempotent() async throws {
        let (container, household, state, records) = try fixture()
        let transport = InMemoryCloudTransport()
        let controller = CloudSyncController(transport: transport)
        await controller.provisionOwner(household: household, records: records,
            state: state, context: container.mainContext)
        XCTAssertEqual(state.mode, .owner)
        XCTAssertEqual(state.provisioningStage, .roundTripVerified)
        let first = await transport.allRecords(zoneName: state.zoneName!).count
        await controller.provisionOwner(household: household, records: records,
            state: state, context: container.mainContext)
        let second = await transport.allRecords(zoneName: state.zoneName!).count
        XCTAssertEqual(second, first)
    }

    func testEmptyInstallDiscoversAndRecoversExistingCloudHousehold() async throws {
        let sourceID = UUID()
        let personID = UUID()
        let source = Household(id: sourceID, name: "Fictional Recovery Family",
                               timeZoneIdentifier: "America/New_York")
        let person = Person(id: personID, householdID: sourceID, name: "Avery",
                            role: .parent, colorHex: "#00A6A6",
                            companionID: "orbit")
        let transport = InMemoryCloudTransport()
        let zone = SyncIdentity.zoneName(householdID: sourceID)
        try await transport.prepareZone(named: zone, scope: .privateDatabase)
        _ = try await transport.save(
            records: [SyncSnapshot.household(source), SyncSnapshot.person(person)],
            zoneName: zone, scope: .privateDatabase)

        let (container, placeholder, state, _) = try fixture()
        container.mainContext.delete(state)
        container.mainContext.delete(placeholder)
        try container.mainContext.save()
        let controller = CloudSyncController(transport: transport)
        let candidates = await controller.discoverRecoverableHouseholds()
        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.householdName, "Fictional Recovery Family")

        let recovered = await controller.recoverHousehold(
            candidate, context: container.mainContext)
        XCTAssertEqual(recovered?.mode, .owner)
        XCTAssertEqual(recovered?.databaseScope, .privateDatabase)
        XCTAssertEqual(
            String(data: try XCTUnwrap(recovered?.changeToken), encoding: .utf8),
            "2")
        XCTAssertEqual(try container.mainContext.fetch(
            FetchDescriptor<Household>()).first?.id, sourceID)
        XCTAssertEqual(try container.mainContext.fetch(
            FetchDescriptor<Person>()).first?.id, personID)
        XCTAssertFalse(try container.mainContext.fetch(
            FetchDescriptor<LocalDeviceSettings>()).isEmpty)
        XCTAssertEqual(try container.mainContext.fetch(
            FetchDescriptor<HouseholdImportReceipt>()).first?.sourceKind,
                       "icloudRecovery")
    }

    func testRecoveryPreviewReportsCountsAndXPWithoutPrivatePayloads() throws {
        let householdID = UUID()
        let personID = UUID()
        let questID = UUID()
        let records = [
            CloudRecordEnvelope(
                type: .household, entityID: householdID,
                householdID: householdID,
                fields: ["name": "Fictional Safe Family", "schemaVersion": "6",
                         "timeZoneIdentifier": "America/New_York"]),
            CloudRecordEnvelope(
                type: .person, entityID: personID, householdID: householdID,
                fields: ["name": "Avery", "role": "parent",
                         "startingXPAdjustment": "100"]),
            CloudRecordEnvelope(
                type: .quest, entityID: questID, householdID: householdID,
                fields: ["title": "Pack bag",
                         "xp": "20",
                         "participantIDs": personID.uuidString]),
            CloudRecordEnvelope(
                type: .questCompletion, entityID: UUID(),
                householdID: householdID,
                fields: ["questID": questID.uuidString,
                         "personID": personID.uuidString,
                         "awardedXP": "20", "reversedAt": "",
                         "completedAt": "2026-08-14T12:00:00Z"])
        ]
        let candidate = CloudHouseholdCandidate(
            householdID: householdID, householdName: "Fictional Safe Family",
            zoneName: "safe-zone", zoneOwnerName: nil,
            rootRecordName: records[0].recordName, shareRecordName: nil,
            scope: .privateDatabase, records: records)

        let preview = CloudRecoveryAudit.preview(candidate)

        XCTAssertTrue(preview.isSafeToRecover)
        XCTAssertEqual(preview.people, 1)
        XCTAssertEqual(preview.quests, 1)
        XCTAssertEqual(preview.completions, 1)
        XCTAssertEqual(preview.startingXP, 100)
        XCTAssertEqual(preview.awardedXP, 20)
    }

    func testUnsafeRecoveryRollsBackInsteadOfSavingPartialHousehold() async throws {
        let (container, placeholder, state, _) = try fixture()
        container.mainContext.delete(state)
        container.mainContext.delete(placeholder)
        try container.mainContext.save()
        let householdID = UUID()
        let root = CloudRecordEnvelope(
            type: .household, entityID: householdID, householdID: householdID,
            fields: ["name": "Broken Fictional Family", "schemaVersion": "6"])
        let person = CloudRecordEnvelope(
            type: .person, entityID: UUID(), householdID: householdID,
            fields: ["name": "Avery", "role": "parent"])
        let quest = CloudRecordEnvelope(
            type: .quest, entityID: UUID(), householdID: householdID,
            fields: ["title": "Broken assignment",
                     "participantIDs": UUID().uuidString])
        let candidate = CloudHouseholdCandidate(
            householdID: householdID, householdName: "Broken Fictional Family",
            zoneName: "broken-zone", zoneOwnerName: nil,
            rootRecordName: root.recordName, shareRecordName: nil,
            scope: .privateDatabase, records: [root, person, quest])
        let controller = CloudSyncController(transport: InMemoryCloudTransport())

        let recovered = await controller.recoverHousehold(
            candidate, context: container.mainContext)

        XCTAssertNil(recovered)
        XCTAssertTrue(try container.mainContext.fetch(
            FetchDescriptor<Household>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(
            FetchDescriptor<Person>()).isEmpty)
    }

    func testRecoveryRefusesToMergeIntoExistingLocalHousehold() async throws {
        let (container, _, _, _) = try fixture()
        let transport = InMemoryCloudTransport()
        let controller = CloudSyncController(transport: transport)
        let candidate = CloudHouseholdCandidate(
            householdID: UUID(), householdName: "Other Fictional Family",
            zoneName: "kyndyn-household-other", zoneOwnerName: nil,
            rootRecordName: "household-other", shareRecordName: nil,
            scope: .privateDatabase, records: [])

        let recovered = await controller.recoverHousehold(
            candidate, context: container.mainContext)
        XCTAssertNil(recovered)
        XCTAssertEqual(try container.mainContext.fetch(
            FetchDescriptor<Household>()).count, 1)
    }

    func testProvisioningResumesAfterEveryMeaningfulInterruption() async throws {
        for call in 1...6 {
            let (container, household, state, records) = try fixture()
            let transport = InterruptingTransport(failureCall: call)
            let controller = CloudSyncController(transport: transport)
            await controller.provisionOwner(household: household, records: records,
                state: state, context: container.mainContext)
            XCTAssertNotEqual(state.mode, .owner)
            await controller.provisionOwner(household: household, records: records,
                state: state, context: container.mainContext)
            XCTAssertEqual(state.mode, .owner, "Failed to resume call \(call)")
        }
    }

    func testInvitationStatesBeforeOnboardingAndWhileRunning() async {
        let transport = InMemoryCloudTransport()
        let router = InvitationRouter(transport: transport)
        router.receive(ShareInvitation(shareIdentifier: "share", rootRecordName: "root",
                                      schemaVersion: KyndynSchema.version,
                                      alreadyAccepted: false))
        XCTAssertEqual(router.state, .pending)
        await router.accept()
        XCTAssertEqual(router.state, .joined)
        router.receive(ShareInvitation(shareIdentifier: "", rootRecordName: "",
                                      schemaVersion: KyndynSchema.version,
                                      alreadyAccepted: false))
        XCTAssertEqual(router.state, .malformed)
        router.receive(ShareInvitation(shareIdentifier: "share", rootRecordName: "root",
                                      schemaVersion: KyndynSchema.version + 1,
                                      alreadyAccepted: false))
        XCTAssertEqual(router.state, .incompatible)
    }

    func testAccountChangePausesWithoutUploading() async throws {
        let (container, household, state, records) = try fixture()
        let transport = InMemoryCloudTransport(accountFingerprint: "owner-a")
        let controller = CloudSyncController(transport: transport)
        await controller.provisionOwner(household: household, records: records,
            state: state, context: container.mainContext)
        await transport.setAvailability(.available(fingerprint: "owner-b"))
        await controller.synchronize(state: state, context: container.mainContext)
        XCTAssertEqual(state.mode, .accountChanged)
    }

    func testOfflineQueueRetriesButPermanentFailureWaitsForAttention() async throws {
        let (container, household, state, records) = try fixture()
        let context = container.mainContext
        state.mode = .owner
        state.zoneName = SyncIdentity.zoneName(householdID: household.id)
        state.accountFingerprint = "test-account"
        try SyncQueue.enqueue(records[0], operation: .createOrUpdate,
                              context: context)
        let mutation = try XCTUnwrap(
            context.fetch(FetchDescriptor<PendingSyncMutation>()).first)
        let transport = InMemoryCloudTransport()
        let controller = CloudSyncController(transport: transport)
        await transport.failNext(.offline)
        let start = Date(timeIntervalSince1970: 1_000)
        await controller.synchronize(state: state, context: context, now: start)
        XCTAssertEqual(mutation.retryCount, 1)
        XCTAssertGreaterThan(mutation.nextAttemptAt, start)
        XCTAssertEqual(state.mode, .recoverableError)

        mutation.nextAttemptAt = start
        state.mode = .owner
        await transport.failNext(.accessRevoked)
        await controller.synchronize(state: state, context: context, now: start)
        XCTAssertEqual(mutation.retryCount, 1)
        XCTAssertEqual(state.mode, .needsAttention)
        XCTAssertEqual(mutation.lastErrorCategoryRaw,
                       SyncErrorCategory.accessRevoked.rawValue)
    }

    func testRemoteQuestChangesRefreshDeviceLocalReminders() async throws {
        let (container, household, state, _) = try fixture()
        let context = container.mainContext
        let person = Person(householdID: household.id, name: "Avery",
                            role: .child, colorHex: "#123", companionID: "spark")
        let settings = LocalDeviceSettings()
        settings.notificationsEnabled = true
        settings.devicePersonID = person.id
        context.insert(settings)
        let quest = Quest(householdID: household.id, title: "Pack bag", xp: 10,
                          participantIDs: [person.id], scheduleKind: .daily)
        let transport = InMemoryCloudTransport()
        let zone = SyncIdentity.zoneName(householdID: household.id)
        try await transport.prepareZone(named: zone, scope: .privateDatabase)
        _ = try await transport.save(records: [
            SyncSnapshot.person(person)
        ] + SyncSnapshot.quest(quest), zoneName: zone, scope: .privateDatabase)
        state.mode = .owner
        state.zoneName = zone
        state.accountFingerprint = "test-account"
        let recorder = RecordingNotificationScheduler()
        let controller = CloudSyncController(
            transport: transport, notificationScheduler: recorder)
        await controller.synchronize(state: state, context: context)
        let replacementCount = await recorder.replacements
        XCTAssertEqual(replacementCount, 1)
    }

    func testQuestScheduleSnapshotCarriesEveryOtherWeekInterval() async throws {
        let householdID = UUID()
        let quest = Quest(
            householdID: householdID, title: "Monday handoff", xp: 10,
            participantIDs: [UUID()], scheduleKind: .weekly,
            weekdays: [2], repeatIntervalWeeks: 2)
        let schedule = try XCTUnwrap(SyncSnapshot.quest(quest).first {
            $0.type == .questSchedule
        })
        XCTAssertEqual(schedule.fields["weekdays"], "2,interval=2")
    }

    func testStaleChangeTokenFallsBackToFullZoneFetch() async throws {
        let (container, household, state, records) = try fixture()
        let transport = InMemoryCloudTransport()
        let controller = CloudSyncController(transport: transport)
        await controller.provisionOwner(household: household, records: records,
            state: state, context: container.mainContext)
        await controller.synchronize(
            state: state, context: container.mainContext)
        XCTAssertNotNil(state.changeToken)
        await transport.expireNextChangeToken()
        await controller.synchronize(state: state, context: container.mainContext)
        XCTAssertEqual(state.mode, .owner)
        XCTAssertNotNil(state.changeToken)
        XCTAssertNil(state.lastErrorCategoryRaw)
    }

    func testFullReconciliationRecoversStartingXPMissedByChangeToken() async throws {
        let (ownerContainer, household, ownerState, records) = try fixture()
        let ownerPerson = Person(
            householdID: household.id, name: "Avery", role: .child,
            colorHex: "#123456", companionID: "spark")
        ownerContainer.mainContext.insert(ownerPerson)
        try ownerContainer.mainContext.save()
        let transport = InMemoryCloudTransport()
        let ownerController = CloudSyncController(transport: transport)
        await ownerController.provisionOwner(
            household: household,
            records: records + [SyncSnapshot.person(ownerPerson)], state: ownerState,
            context: ownerContainer.mainContext)

        let zone = try XCTUnwrap(ownerState.zoneName)
        ownerPerson.startingXPAdjustment = 619
        try ownerContainer.mainContext.save()
        try SyncQueue.enqueue(
            SyncSnapshot.person(ownerPerson), operation: .createOrUpdate,
            context: ownerContainer.mainContext)
        await ownerController.synchronize(
            state: ownerState, context: ownerContainer.mainContext)

        let participantSchema = Schema([
            Household.self, Person.self, Quest.self, QuestCompletion.self,
            RewardGoal.self, FamilyBroadcast.self, Companion.self,
            Background.self, HouseholdSettings.self, LocalDeviceSettings.self,
            LocalQuestReminder.self, HouseholdCloudState.self,
            SyncRecordMetadata.self, PendingSyncMutation.self,
            SyncConflict.self, PendingShareInvitation.self
        ])
        let participantContainer = try ModelContainer(
            for: participantSchema, configurations: ModelConfiguration(
                schema: participantSchema, isStoredInMemoryOnly: true,
                cloudKitDatabase: .none))
        let participantContext = participantContainer.mainContext
        let stalePerson = Person(
            id: ownerPerson.id, householdID: household.id, name: ownerPerson.name,
            role: ownerPerson.role, colorHex: ownerPerson.colorHex,
            companionID: ownerPerson.companionID)
        participantContext.insert(Household(
            id: household.id, name: household.name,
            timeZoneIdentifier: household.timeZoneIdentifier))
        participantContext.insert(stalePerson)
        participantContext.insert(LocalDeviceSettings())
        let participantState = HouseholdCloudState(householdID: household.id)
        participantState.mode = .participant
        participantState.databaseScope = .sharedDatabase
        participantState.zoneName = zone
        participantState.accountFingerprint = "test-account"
        // Simulate a device whose saved token says it already saw the latest
        // zone change even though its local person payload is stale.
        let latest = try await transport.fetchChanges(
            zoneName: zone, scope: .sharedDatabase,
            zoneOwnerName: nil, after: nil)
        participantState.changeToken = latest.changeToken
        participantContext.insert(participantState)
        try participantContext.save()

        let participantController = CloudSyncController(transport: transport)
        await participantController.synchronize(
            state: participantState, context: participantContext)
        XCTAssertEqual(stalePerson.startingXPAdjustment, 0)

        await participantController.synchronize(
            state: participantState, context: participantContext,
            fullReconciliation: true)
        XCTAssertEqual(stalePerson.startingXPAdjustment, 619)
        XCTAssertEqual(participantController.statusMessage, "Up to date")
    }
}

final class MultiDeviceConvergenceTests: XCTestCase {
    private struct Replica {
        var records: [String: CloudRecordEnvelope] = [:]

        mutating func receive(_ delivery: [CloudRecordEnvelope]) {
            for incoming in delivery {
                records[incoming.recordName] = records[incoming.recordName].map {
                    SyncMergeEngine.merge($0, incoming).record
                } ?? incoming
            }
        }

        var activeXP: Int {
            records.values.filter {
                $0.type == .questCompletion &&
                ($0.fields["reversedAt"] ?? "").isEmpty
            }.reduce(0) { $0 + (Int($1.fields["awardedXP"] ?? "") ?? 0) }
        }
    }

    func testTwoStoresConvergeAfterOfflineAndDuplicateReorderedEvents() {
        let householdID = UUID()
        let eventID = UUID()
        let mutationID = UUID()
        let completion = CloudRecordEnvelope(
            type: .questCompletion, entityID: eventID,
            householdID: householdID,
            fields: ["awardedXP": "10", "reversedAt": ""],
            mutationID: mutationID, serverSequence: 1)
        let personEdit = CloudRecordEnvelope(
            type: .person, entityID: UUID(), householdID: householdID,
            fields: ["colorHex": "#123456"], serverSequence: 2)
        var first = Replica()
        var second = Replica()
        first.receive([completion, personEdit, completion])
        second.receive([personEdit, completion])
        XCTAssertEqual(first.records, second.records)
        XCTAssertEqual(first.activeXP, 10)

        var undo = completion
        undo.fields["reversedAt"] = "2026-07-29T16:00:00Z"
        undo.mutationID = UUID()
        undo.serverSequence = 3
        undo.fieldStamps["reversedAt"] = FieldStamp(
            serverSequence: 3, mutationID: undo.mutationID)
        first.receive([undo])
        second.receive([undo, undo])
        XCTAssertEqual(first.records, second.records)
        XCTAssertEqual(first.activeXP, 0)
    }

    func testOwnerAndParticipantConvergeOnExactOccurrenceUndoAndEdits() {
        let householdID = UUID()
        let personID = UUID()
        let questID = UUID()
        let eventID = UUID()
        let completion = CloudRecordEnvelope(
            type: .questCompletion,
            entityID: eventID,
            householdID: householdID,
            fields: [
                "questID": questID.uuidString,
                "personID": personID.uuidString,
                "occurrenceDay": "2026-07-29",
                "awardedXP": "15",
                "reversedAt": ""
            ],
            serverSequence: 3
        )
        let ownerEdit = CloudRecordEnvelope(
            type: .quest, entityID: questID, householdID: householdID,
            fields: ["title": "Pack tomorrow’s bag"], serverSequence: 4
        )
        let participantEdit = CloudRecordEnvelope(
            type: .person, entityID: personID, householdID: householdID,
            fields: ["colorHex": "#00A6A6"], serverSequence: 5
        )
        var exactUndo = completion
        exactUndo.fields["reversedAt"] = "2026-07-29T18:00:00Z"
        exactUndo.serverSequence = 6
        exactUndo.mutationID = UUID()
        exactUndo.fieldStamps["reversedAt"] = FieldStamp(
            serverSequence: 6, mutationID: exactUndo.mutationID
        )

        var owner = Replica()
        var participant = Replica()
        owner.receive([completion, ownerEdit, participantEdit, exactUndo])
        participant.receive([
            participantEdit, completion, completion, exactUndo, ownerEdit
        ])

        XCTAssertEqual(owner.records, participant.records)
        XCTAssertEqual(owner.activeXP, 0)
        XCTAssertEqual(
            owner.records[completion.recordName]?.fields["occurrenceDay"],
            "2026-07-29"
        )
        XCTAssertEqual(
            owner.records[ownerEdit.recordName]?.fields["title"],
            "Pack tomorrow’s bag"
        )
    }
}
