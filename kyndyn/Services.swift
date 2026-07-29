import CryptoKit
import Foundation
import LocalAuthentication
import Security
import UserNotifications

protocol HouseholdSyncing: Sendable {
    func synchronize() async throws
}
struct LocalOnlyHouseholdSync: HouseholdSyncing {
    func synchronize() async throws {}
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

// MARK: - Parent authentication

enum ParentAuthenticationResult: Equatable {
    case authenticated
    case userCanceled
    case unavailable
    case failed(String)
}

protocol DeviceAuthenticating: Sendable {
    func authenticate(reason: String) async -> ParentAuthenticationResult
}

struct LocalDeviceAuthenticator: DeviceAuthenticating {
    func authenticate(reason: String) async -> ParentAuthenticationResult {
        let context = LAContext()
        context.localizedCancelTitle = "Use kyndyn PIN"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
                ? .authenticated : .failed("Authentication wasn’t completed.")
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel, .userFallback:
                return .userCanceled
            case .biometryNotAvailable, .passcodeNotSet, .biometryNotEnrolled:
                return .unavailable
            default:
                return .failed("Authentication wasn’t completed. You can try again or use the kyndyn PIN.")
            }
        } catch {
            return .failed("Authentication wasn’t completed. You can try again or use the kyndyn PIN.")
        }
    }
}

protocol ParentPINStoring: Sendable {
    func hasPIN() -> Bool
    func verify(_ pin: String) -> Bool
    func set(_ pin: String) throws
    func remove() throws
}

enum PINValidation {
    static func message(for pin: String) -> String? {
        guard pin.allSatisfy(\.isNumber) else { return "Use numbers only." }
        guard (6...12).contains(pin.count) else { return "Use a PIN between 6 and 12 digits." }
        let unique = Set(pin)
        guard unique.count > 1 else { return "Choose a PIN with more than one repeated digit." }
        guard pin != String(pin.reversed()) || pin.count > 6 else { return "Choose a less predictable PIN." }
        return nil
    }
}

struct KeychainParentPINStore: ParentPINStoring {
    private let service = "com.kyndynfamily.kyndyn.parent-auth"
    private let account = "parent-pin-v1"
    private let rounds = 120_000

    func hasPIN() -> Bool { load() != nil }

    func verify(_ pin: String) -> Bool {
        guard let payload = load(),
              payload.count == 48 else { return false }
        let salt = payload.prefix(16)
        let expected = payload.suffix(32)
        let candidate = hash(pin: pin, salt: Data(salt))
        return constantTimeEqual(Data(expected), candidate)
    }

    func set(_ pin: String) throws {
        guard PINValidation.message(for: pin) == nil else { throw PINStoreError.invalidPIN }
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!)
        }
        guard status == errSecSuccess else { throw PINStoreError.keychain(status) }
        let payload = salt + hash(pin: pin, salt: salt)
        try save(payload)
    }

    func remove() throws {
        let status = SecItemDelete(query() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PINStoreError.keychain(status)
        }
    }

    private func hash(pin: String, salt: Data) -> Data {
        var digest = Data(SHA256.hash(data: salt + Data(pin.utf8)))
        for _ in 1..<rounds {
            digest = Data(SHA256.hash(data: digest + salt + Data(pin.utf8)))
        }
        return digest
    }

    private func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private func load() -> Data? {
        var request = query()
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private func save(_ data: Data) throws {
        SecItemDelete(query() as CFDictionary)
        var request = query()
        request[kSecValueData as String] = data
        request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(request as CFDictionary, nil)
        guard status == errSecSuccess else { throw PINStoreError.keychain(status) }
    }
}

enum PINStoreError: LocalizedError {
    case invalidPIN
    case keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .invalidPIN: return "That PIN doesn’t meet kyndyn’s security requirements."
        case .keychain: return "kyndyn couldn’t securely save the PIN on this device."
        }
    }
}

@MainActor
final class ParentAccessController: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published var message: String?
    private let authenticator: DeviceAuthenticating
    private let pinStore: ParentPINStoring
    private var backgroundedAt: Date?
    let relockInterval: TimeInterval

    init(authenticator: DeviceAuthenticating = LocalDeviceAuthenticator(),
         pinStore: ParentPINStoring = KeychainParentPINStore(),
         relockInterval: TimeInterval = 120) {
        self.authenticator = authenticator
        self.pinStore = pinStore
        self.relockInterval = relockInterval
    }

    var hasPIN: Bool { pinStore.hasPIN() }

    func authenticate() async {
        handleAuthenticationResult(
            await authenticator.authenticate(reason: "Open kyndyn’s Parent area")
        )
    }

    func handleAuthenticationResult(_ result: ParentAuthenticationResult) {
        switch result {
        case .authenticated:
            isUnlocked = true; message = nil
        case .userCanceled:
            message = hasPIN ? "Authentication was canceled. Use your kyndyn PIN or try again." : "Authentication was canceled. You can try again."
        case .unavailable:
            message = hasPIN ? "Device authentication isn’t available. Use your kyndyn PIN." : "Set a device passcode or configure a kyndyn PIN from an authenticated device session."
        case .failed(let text):
            message = text
        }
    }

    func unlock(pin: String) -> Bool {
        let valid = pinStore.verify(pin)
        isUnlocked = valid
        message = valid ? nil : "That kyndyn PIN didn’t match."
        return valid
    }

    func configurePIN(_ pin: String) throws {
        try pinStore.set(pin)
    }

    func disablePIN() throws {
        try pinStore.remove()
    }

    func lock() { isUnlocked = false }
    func unlockForUITesting() {
        guard ProcessInfo.processInfo.arguments.contains("-ui-testing-parent-unlocked") else { return }
        isUnlocked = true
    }
    func didEnterBackground(at date: Date = .now) { backgroundedAt = date }
    func didBecomeActive(at date: Date = .now) {
        if let backgroundedAt, date.timeIntervalSince(backgroundedAt) >= relockInterval { lock() }
        backgroundedAt = nil
    }
}

// MARK: - Local notifications

enum NotificationPermissionState: String, Equatable {
    case notDetermined, denied, provisional, authorized, unavailable
}

struct ReminderCandidate: Equatable {
    let identifier: String
    let fireDate: Date
    let title: String
    let body: String
    let questID: UUID?
}

protocol NotificationScheduling: Sendable {
    func permissionState() async -> NotificationPermissionState
    func requestPermission() async -> NotificationPermissionState
    func replaceKyndynReminders(with candidates: [ReminderCandidate]) async throws
}

struct UserNotificationScheduler: NotificationScheduling, @unchecked Sendable {
    private let center = UNUserNotificationCenter.current()

    func permissionState() async -> NotificationPermissionState {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .provisional, .ephemeral: return .provisional
        case .authorized: return .authorized
        @unknown default: return .unavailable
        }
    }

    func requestPermission() async -> NotificationPermissionState {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
            return await permissionState()
        } catch {
            return .unavailable
        }
    }

    func replaceKyndynReminders(with candidates: [ReminderCandidate]) async throws {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("kyndyn.") })
        for candidate in Dictionary(grouping: candidates, by: \.identifier).compactMap(\.value.first) {
            let content = UNMutableNotificationContent()
            content.title = candidate.title
            content.body = candidate.body
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: candidate.fireDate)
            try await center.add(UNNotificationRequest(
                identifier: candidate.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            ))
        }
    }
}

enum ReminderRules {
    static func candidates(quests: [Quest], people: [Person], settings: LocalDeviceSettings,
                           household: Household, now: Date) -> [ReminderCandidate] {
        guard settings.notificationsEnabled, let profileID = settings.devicePersonID else { return [] }
        let calendar = ProgressionEngine.calendar(timeZoneIdentifier: household.timeZoneIdentifier)
        let activePersonIDs = Set(people.filter { $0.deletedAt == nil }.map(\.id))
        guard activePersonIDs.contains(profileID) else { return [] }
        let start = calendar.startOfDay(for: now)
        var candidates: [ReminderCandidate] = quests.filter {
            $0.deletedAt == nil && $0.participantIDs.contains(profileID) &&
            ProgressionEngine.isScheduled($0, on: now, timeZoneIdentifier: household.timeZoneIdentifier)
        }.compactMap { quest -> ReminderCandidate? in
            let preferred = quest.dueAt ?? calendar.date(bySettingHour: settings.defaultReminderHour,
                                                         minute: settings.defaultReminderMinute,
                                                         second: 0, of: start)
            guard let preferred else { return nil }
            let adjusted = adjustForQuietHours(preferred, settings: settings, calendar: calendar)
            guard adjusted > now else { return nil }
            let day = ProgressionEngine.dayKey(adjusted, timeZoneIdentifier: household.timeZoneIdentifier)
            return ReminderCandidate(
                identifier: "kyndyn.quest.\(quest.id.uuidString).\(profileID.uuidString).\(day)",
                fireDate: adjusted,
                title: "A kyndyn quest is ready",
                body: settings.showQuestDetailsOnLockScreen ? quest.title : "Open kyndyn to see what’s next.",
                questID: quest.id
            )
        }
        if settings.parentSummaryEligible,
           people.first(where: { $0.id == profileID && $0.deletedAt == nil })?.role == .parent,
           let summaryTime = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: start) {
            let adjusted = adjustForQuietHours(summaryTime, settings: settings, calendar: calendar)
            if adjusted > now {
                let day = ProgressionEngine.dayKey(adjusted, timeZoneIdentifier: household.timeZoneIdentifier)
                candidates.append(ReminderCandidate(
                    identifier: "kyndyn.parent-summary.\(profileID.uuidString).\(day)",
                    fireDate: adjusted,
                    title: "kyndyn family check-in",
                    body: "Open kyndyn for a private look at today’s family progress.",
                    questID: nil
                ))
            }
        }
        return candidates.sorted { $0.fireDate < $1.fireDate }
    }

    static func adjustForQuietHours(_ date: Date, settings: LocalDeviceSettings, calendar: Calendar) -> Date {
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let start = settings.quietStartHour * 60 + settings.quietStartMinute
        let end = settings.quietEndHour * 60 + settings.quietEndMinute
        let inQuiet = start <= end ? (minute >= start && minute < end) : (minute >= start || minute < end)
        guard inQuiet else { return date }
        var target = date
        if start > end && minute >= start { target = calendar.date(byAdding: .day, value: 1, to: date) ?? date }
        return calendar.date(bySettingHour: settings.quietEndHour, minute: settings.quietEndMinute, second: 0, of: target) ?? target
    }
}
