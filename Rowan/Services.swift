import Foundation

protocol HouseholdSyncing: Sendable {
    func synchronize() async throws
}
struct LocalOnlyHouseholdSync: HouseholdSyncing {
    func synchronize() async throws {}
}

protocol NotificationScheduling: Sendable {
    func refreshReminders() async
}
struct DisabledNotificationScheduler: NotificationScheduling {
    func refreshReminders() async {}
}

protocol EntitlementProviding: Sendable {
    var hasFamilyEntitlement: Bool { get async }
}
struct DevelopmentEntitlements: EntitlementProviding {
    var hasFamilyEntitlement: Bool { get async { true } }
}

struct ImportReport: Equatable {
    var accepted = 0
    var normalized = 0
    var skippedDuplicates = 0
    var invalid = 0
}
protocol HouseholdImporting: Sendable {
    func dryRun(data: Data) async -> ImportReport
}
struct DisabledImporter: HouseholdImporting {
    func dryRun(data: Data) async -> ImportReport { ImportReport(invalid: 1) }
}

