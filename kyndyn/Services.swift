import CloudKit
import CoreLocation
import CryptoKit
import EventKit
import Foundation
import LocalAuthentication
import OSLog
import Security
import StoreKit
import SwiftUI
import UIKit
import UserNotifications
import WeatherKit

// MARK: - Device calendar and weather

enum DevicePermissionState: Equatable, Sendable {
    case notRequested, allowed, denied, restricted
}

struct DeviceCalendar: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let colorHex: String
}

struct DeviceCalendarEvent: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarID: String
    let calendarTitle: String
    let calendarColorHex: String
}

protocol CalendarProviding: Sendable {
    func permissionState() -> DevicePermissionState
    func requestAccess() async -> Bool
    func calendars() -> [DeviceCalendar]
    func events(from: Date, through: Date, calendarIDs: Set<String>) -> [DeviceCalendarEvent]
}

final class EventKitCalendarProvider: CalendarProviding, @unchecked Sendable {
    private let store = EKEventStore()

    func permissionState() -> DevicePermissionState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .allowed
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined, .writeOnly: .notRequested
        @unknown default: .restricted
        }
    }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) == true
    }

    func calendars() -> [DeviceCalendar] {
        store.calendars(for: .event).map {
            DeviceCalendar(id: $0.calendarIdentifier, title: $0.title,
                           colorHex: UIColor(cgColor: $0.cgColor).hexString)
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func events(from: Date, through: Date,
                calendarIDs: Set<String>) -> [DeviceCalendarEvent] {
        let selected = store.calendars(for: .event).filter {
            calendarIDs.contains($0.calendarIdentifier)
        }
        guard !selected.isEmpty else { return [] }
        return store.events(matching: store.predicateForEvents(
            withStart: from, end: through, calendars: selected)).map {
                DeviceCalendarEvent(
                    id: $0.eventIdentifier ?? UUID().uuidString,
                    title: $0.title ?? "Calendar event",
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    isAllDay: $0.isAllDay,
                    calendarID: $0.calendar.calendarIdentifier,
                    calendarTitle: $0.calendar.title,
                    calendarColorHex: UIColor(cgColor: $0.calendar.cgColor).hexString)
            }.sorted { $0.startDate < $1.startDate }
    }
}

struct DeviceWeatherSnapshot: Equatable, Sendable {
    let locationName: String?
    let temperature: Double
    let high: Double
    let low: Double
    let condition: String
    let symbolName: String
    let fetchedAt: Date
    let hourlyForecast: [DeviceWeatherHour]
    let dailyForecast: [DeviceWeatherDay]
}

struct DeviceWeatherHour: Identifiable, Equatable, Sendable {
    var id: Date { date }
    let date: Date
    let temperature: Double
    let precipitationChance: Double
    let symbolName: String
}

struct DeviceWeatherDay: Identifiable, Equatable, Sendable {
    var id: Date { date }
    let date: Date
    let high: Double
    let low: Double
    let condition: String
    let symbolName: String
}

enum WeatherCachePolicy {
    static let lifetime: TimeInterval = 30 * 60
    static func isFresh(_ fetchedAt: Date?, now: Date = .now) -> Bool {
        guard let fetchedAt else { return false }
        let age = now.timeIntervalSince(fetchedAt)
        return age >= 0 && age < lifetime
    }
}

protocol WeatherProviding: Sendable {
    func weather(latitude: Double, longitude: Double) async throws -> DeviceWeatherSnapshot
}

struct AppleWeatherProvider: WeatherProviding {
    func weather(latitude: Double, longitude: Double) async throws -> DeviceWeatherSnapshot {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let (current, hourly, daily) = try await WeatherService.shared.weather(
            for: location, including: .current, .hourly, .daily)
        let today = daily.forecast.first
        return DeviceWeatherSnapshot(
            locationName: placemark?.locality
                ?? placemark?.subAdministrativeArea
                ?? placemark?.administrativeArea,
            temperature: current.temperature.converted(to: .fahrenheit).value,
            high: today?.highTemperature.converted(to: .fahrenheit).value
                ?? current.temperature.converted(to: .fahrenheit).value,
            low: today?.lowTemperature.converted(to: .fahrenheit).value
                ?? current.temperature.converted(to: .fahrenheit).value,
            condition: current.condition.description,
            symbolName: current.symbolName,
            fetchedAt: .now,
            hourlyForecast: hourly.forecast
                .filter { $0.date >= Date.now.addingTimeInterval(-300) }
                .prefix(24).map {
                    DeviceWeatherHour(
                        date: $0.date,
                        temperature: $0.temperature
                            .converted(to: .fahrenheit).value,
                        precipitationChance: $0.precipitationChance,
                        symbolName: $0.symbolName)
                },
            dailyForecast: daily.forecast.prefix(10).map {
                DeviceWeatherDay(
                    date: $0.date,
                    high: $0.highTemperature.converted(to: .fahrenheit).value,
                    low: $0.lowTemperature.converted(to: .fahrenheit).value,
                    condition: $0.condition.description,
                    symbolName: $0.symbolName)
            })
    }
}

enum DeviceLocationError: Error { case unavailable, denied }

@MainActor
final class OneShotLocationProvider: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    func currentLocation() async throws -> CLLocation {
        guard continuation == nil else { throw DeviceLocationError.unavailable }
        manager.delegate = self
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .denied, .restricted: throw DeviceLocationError.denied
        @unknown default: throw DeviceLocationError.unavailable
        }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .denied, .restricted:
            continuation?.resume(throwing: DeviceLocationError.denied)
            continuation = nil
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        continuation?.resume(returning: location)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager,
                         didFailWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

private extension UIColor {
    var hexString: String {
        guard let components = cgColor.components else { return "#888888" }
        let red = components[0]
        let green = components.count > 2 ? components[1] : red
        let blue = components.count > 2 ? components[2] : red
        return String(format: "#%02X%02X%02X", Int(red * 255),
                      Int(green * 255), Int(blue * 255))
    }
}

protocol HouseholdSyncing: Sendable {
    func synchronize() async throws
}
struct LocalOnlyHouseholdSync: HouseholdSyncing {
    func synchronize() async throws {}
}

enum PremiumAccessState: String, Codable, Equatable, Sendable {
    case free
    case active
    case gracePeriod
    case expired
    case revoked

    var grantsPremiumAccess: Bool {
        self == .active || self == .gracePeriod
    }
}

enum PremiumEntitlementSource: String, Codable, Equatable, Sendable {
    case none
    case appStorePurchase
    case appleFamilySharing
    case complimentary
    case grandfathered
}

struct PremiumEntitlement: Codable, Equatable, Sendable {
    var state: PremiumAccessState
    var source: PremiumEntitlementSource
    var expirationDate: Date?

    static let free = PremiumEntitlement(
        state: .free, source: .none, expirationDate: nil)

    var hasPremiumAccess: Bool { state.grantsPremiumAccess }

    /// Expiration never makes existing family information unreadable. It only
    /// prevents starting a new premium-only action.
    var preservesExistingHouseholdData: Bool { true }

    func allows(_ feature: PremiumFeature) -> Bool {
        hasPremiumAccess
    }

    func allowsCollectionSelection(
        requiresPremium: Bool,
        isCurrentlySelected: Bool
    ) -> Bool {
        !requiresPremium || hasPremiumAccess || isCurrentlySelected
    }
}

enum PremiumFeature: String, CaseIterable, Codable, Sendable {
    case appleWatch
    case advancedPlanning
    case richerInsights
    case expandedCustomization
    case enhancedDayContext
    case widgetsAndLiveActivities
    case advancedSiriAutomations
}

protocol EntitlementProviding: Sendable {
    func currentEntitlement() async -> PremiumEntitlement
}

struct FreeEntitlements: EntitlementProviding {
    func currentEntitlement() async -> PremiumEntitlement { .free }
}

enum KyndynStoreProducts {
    static let monthly = "com.kyndynfamily.kyndyn.premium.monthly"
    static let annual = "com.kyndynfamily.kyndyn.premium.annual"
    static let all = [annual, monthly]
}

enum StorePurchaseError: LocalizedError {
    case verificationFailed
    case productUnavailable

    var errorDescription: String? {
        switch self {
        case .verificationFailed:
            "Apple couldn’t verify this purchase. Nothing was charged by kyndyn."
        case .productUnavailable:
            "Premium plans aren’t available right now. Please try again later."
        }
    }
}

@MainActor
@Observable final class StoreKitEntitlementController: EntitlementProviding {
    private(set) var products: [Product] = []
    private(set) var entitlement: PremiumEntitlement
    private(set) var isLoading = false
    private(set) var isPurchasing = false
    var errorMessage: String?

    private let defaults: UserDefaults
    private let testingPremium: Bool
    private let cacheKey = "kyndyn.premium.entitlement.v1"
    private var updatesTask: Task<Void, Never>?
    private var hasStarted = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let arguments = ProcessInfo.processInfo.arguments
        testingPremium = arguments.contains("-ui-testing-reset")
            && arguments.contains("-ui-testing-premium-active")
        if testingPremium {
            entitlement = PremiumEntitlement(
                state: .active,
                source: .appStorePurchase,
                expirationDate: Date(timeIntervalSinceNow: 86_400))
            return
        }
        if let data = defaults.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(
               PremiumEntitlement.self, from: data),
           cached.expirationDate.map({ $0 > .now }) ?? false {
            entitlement = cached
        } else {
            entitlement = .free
        }
    }

    func start() async {
        guard !testingPremium else { return }
        guard !hasStarted else { return }
        hasStarted = true
        updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard !Task.isCancelled else { return }
                do {
                    let transaction = try Self.verified(result)
                    await transaction.finish()
                    await self?.refreshEntitlement()
                } catch {
                    await MainActor.run {
                        self?.errorMessage = error.localizedDescription
                    }
                }
            }
        }
        await loadProducts()
        await refreshEntitlement()
    }

    func currentEntitlement() async -> PremiumEntitlement {
        entitlement
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: KyndynStoreProducts.all)
            products = loaded.sorted {
                if $0.id == KyndynStoreProducts.annual { return true }
                if $1.id == KyndynStoreProducts.annual { return false }
                return $0.price < $1.price
            }
            errorMessage = nil
        } catch {
            errorMessage = "Premium plans couldn’t be loaded. Your family data is unaffected."
        }
    }

    func purchase(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                let transaction = try Self.verified(verification)
                await transaction.finish()
                await refreshEntitlement()
            case .pending:
                errorMessage = "This purchase is waiting for Apple’s approval."
            case .userCancelled:
                break
            @unknown default:
                errorMessage = "The purchase didn’t finish. Please try again."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            if !entitlement.hasPremiumAccess {
                errorMessage = "No active Kyndyn Premium purchase was found for this Apple Account."
            }
        } catch {
            errorMessage = "Purchases couldn’t be restored. Please try again when you’re online."
        }
    }

    func refreshEntitlement() async {
        var newest: StoreKit.Transaction?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard let transaction = try? Self.verified(result),
                  KyndynStoreProducts.all.contains(transaction.productID)
            else { continue }
            if newest == nil || transaction.purchaseDate > newest!.purchaseDate {
                newest = transaction
            }
        }

        guard let transaction = newest else {
            setEntitlement(.free)
            return
        }
        if transaction.revocationDate != nil {
            setEntitlement(PremiumEntitlement(
                state: .revoked,
                source: source(for: transaction),
                expirationDate: transaction.expirationDate))
            return
        }
        let state: PremiumAccessState
        if let expiration = transaction.expirationDate, expiration <= .now {
            state = .expired
        } else {
            state = await subscriptionState(for: transaction.productID)
        }
        setEntitlement(PremiumEntitlement(
            state: state,
            source: source(for: transaction),
            expirationDate: transaction.expirationDate))
    }

    private func subscriptionState(for productID: String) async
        -> PremiumAccessState {
        guard let product = products.first(where: { $0.id == productID }),
              let subscription = product.subscription,
              let status = try? await subscription.status.first else {
            return .active
        }
        switch status.state {
        case .subscribed: return .active
        case .inGracePeriod: return .gracePeriod
        case .expired: return .expired
        case .revoked: return .revoked
        case .inBillingRetryPeriod: return .gracePeriod
        default: return .free
        }
    }

    private func source(for transaction: StoreKit.Transaction)
        -> PremiumEntitlementSource {
        transaction.ownershipType == .familyShared
            ? .appleFamilySharing : .appStorePurchase
    }

    private func setEntitlement(_ value: PremiumEntitlement) {
        entitlement = value
        if value.hasPremiumAccess,
           let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: cacheKey)
        } else {
            defaults.removeObject(forKey: cacheKey)
        }
    }

    nonisolated private static func verified<T>(
        _ result: VerificationResult<T>
    ) throws -> T {
        switch result {
        case .verified(let value): return value
        case .unverified: throw StorePurchaseError.verificationFailed
        }
    }
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

// MARK: - System CloudKit sharing

@MainActor
final class CloudSharingSheetModel: ObservableObject {
    @Published var isPresented = false
    @Published private(set) var errorMessage: String?
    fileprivate private(set) var controller: UICloudSharingController?
    private static let logger = Logger(
        subsystem: "com.kyndynfamily.kyndyn", category: "CloudSharing")

    func prepare(zoneName: String, shareRecordName: String) async {
        errorMessage = nil
        guard !zoneName.isEmpty, !shareRecordName.isEmpty else {
            errorMessage = "The family invitation is still being prepared. Refresh family sync and try again."
            return
        }
        guard case .success(let container) = KyndynCloudContainerFactory.make()
        else {
            errorMessage = "Family invitations aren’t available in this build."
            return
        }
        do {
            let recordID = CKRecord.ID(
                recordName: shareRecordName,
                zoneID: CKRecordZone.ID(zoneName: zoneName))
            guard let share = try await container.privateCloudDatabase
                .record(for: recordID) as? CKShare else {
                errorMessage = "The family invitation couldn’t be opened. Refresh family sync and try again."
                return
            }
            let controller = UICloudSharingController(
                share: share, container: container)
            controller.availablePermissions = [.allowPrivate, .allowReadWrite]
            self.controller = controller
            isPresented = true
        } catch let error as CKError {
            Self.logger.error(
                "prepare-share-sheet: CKError code \(error.errorCode, privacy: .public)")
            errorMessage = "Apple’s family sharing screen couldn’t be opened. Check your connection and try again."
        } catch {
            Self.logger.error(
                "prepare-share-sheet: non-CloudKit failure \(String(describing: type(of: error)), privacy: .public)")
            errorMessage = "The family invitation couldn’t be opened. Try again."
        }
    }

    func clearError() { errorMessage = nil }
}

struct SystemCloudSharingSheet: UIViewControllerRepresentable {
    @ObservedObject var model: CloudSharingSheetModel

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        guard let controller = model.controller else {
            return UIViewController()
        }
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController,
                                context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private static let logger = Logger(
            subsystem: "com.kyndynfamily.kyndyn", category: "CloudSharing")

        func itemTitle(for csc: UICloudSharingController) -> String? {
            "kyndyn family"
        }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            let code = (error as? CKError)?.errorCode ?? -1
            Self.logger.error(
                "share-sheet-save: CKError code \(code, privacy: .public)")
        }
    }
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
    let timeZoneIdentifier: String
}

protocol NotificationScheduling: Sendable {
    func permissionState() async -> NotificationPermissionState
    func requestPermission() async -> NotificationPermissionState
    func replaceKyndynReminders(with candidates: [ReminderCandidate]) async throws
    func notifyBroadcast(
        id: UUID, title: String, message: String, showDetails: Bool
    ) async throws
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
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: candidate.timeZoneIdentifier)
                ?? .current
            let components = calendar.dateComponents(
                [.timeZone, .year, .month, .day, .hour, .minute],
                from: candidate.fireDate)
            try await center.add(UNNotificationRequest(
                identifier: candidate.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            ))
        }
    }

    func notifyBroadcast(
        id: UUID, title: String, message: String, showDetails: Bool
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = showDetails ? title : "New Kyndyn announcement"
        content.body = showDetails
            ? message : "Open Kyndyn to read the family update."
        content.sound = .default
        content.userInfo = ["kyndynBroadcastID": id.uuidString]
        try await center.add(UNNotificationRequest(
            identifier: "kyndyn.broadcast.\(id.uuidString.lowercased())",
            content: content, trigger: nil))
    }
}

enum ReminderRules {
    static func candidates(quests: [Quest], people: [Person], settings: LocalDeviceSettings,
                           household: Household,
                           completions: [QuestCompletion] = [],
                           reminderPreferences: [LocalQuestReminder] = [],
                           now: Date) -> [ReminderCandidate] {
        guard settings.notificationsEnabled, let profileID = settings.devicePersonID else { return [] }
        guard !ProgressionEngine.isSchedulePaused(on: now, household: household) else {
            return []
        }
        let calendar = ProgressionEngine.calendar(timeZoneIdentifier: household.timeZoneIdentifier)
        let activePersonIDs = Set(people.filter { $0.deletedAt == nil }.map(\.id))
        guard activePersonIDs.contains(profileID) else { return [] }
        let start = calendar.startOfDay(for: now)
        var candidates: [ReminderCandidate] = quests.filter {
            $0.deletedAt == nil && $0.participantIDs.contains(profileID) &&
            ProgressionEngine.isScheduled($0, on: now, household: household)
        }.compactMap { quest -> ReminderCandidate? in
            let preference = reminderPreferences.first { $0.questID == quest.id }
            if let preference, !preference.isEnabled { return nil }
            guard let occurrence = ProgressionEngine.occurrenceKey(
                for: quest, on: now,
                timeZoneIdentifier: household.timeZoneIdentifier),
                  !completions.contains(where: {
                      $0.questID == quest.id && $0.personID == profileID &&
                      $0.occurrenceDay == occurrence && $0.reversedAt == nil
                  }) else { return nil }
            let hour = preference?.hour ?? settings.defaultReminderHour
            let minute = preference?.minute ?? settings.defaultReminderMinute
            let preferred = quest.dueAt ?? calendar.date(bySettingHour: hour,
                                                         minute: minute,
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
                questID: quest.id,
                timeZoneIdentifier: household.timeZoneIdentifier
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
                    title: "Evening family check-in",
                    body: "See what got done today and what’s still waiting.",
                    questID: nil,
                    timeZoneIdentifier: household.timeZoneIdentifier
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
