import Foundation
import Observation
import Security
import UIKit
import UserNotifications

enum HostedNotificationRole: String, Codable, Sendable {
    case owner
    case participant
}

struct HostedNotificationIdentity: Codable, Equatable, Sendable {
    let role: HostedNotificationRole
    let householdID: UUID
    let deviceID: UUID
    let adminCapability: String?
    let enrollmentCapability: String?
    let deviceCapability: String?
}

protocol HostedNotificationCredentialStoring: Sendable {
    func load() -> HostedNotificationIdentity?
    func save(_ identity: HostedNotificationIdentity) throws
    func remove() throws
}

struct KeychainHostedNotificationStore: HostedNotificationCredentialStoring {
    private let service = "com.kyndynfamily.kyndyn.hosted-notifications"
    private let account = "device-identity-v1"

    func load() -> HostedNotificationIdentity? {
        var request = query()
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(HostedNotificationIdentity.self, from: data)
    }

    func save(_ identity: HostedNotificationIdentity) throws {
        let data = try JSONEncoder().encode(identity)
        SecItemDelete(query() as CFDictionary)
        var request = query()
        request[kSecValueData as String] = data
        request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(request as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw HostedNotificationError.secureStorage
        }
    }

    func remove() throws {
        let status = SecItemDelete(query() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw HostedNotificationError.secureStorage
        }
    }

    private func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

enum HostedNotificationError: LocalizedError {
    case permissionDenied
    case waitingForApple
    case ownerRequired
    case secureStorage
    case invalidResponse
    case service(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Notifications are off for kyndyn in iOS Settings."
        case .waitingForApple:
            return "Waiting for Apple to prepare this device. Try again in a moment."
        case .ownerRequired:
            return "This action is available on the notification owner’s device."
        case .secureStorage:
            return "kyndyn couldn’t securely store notification access on this device."
        case .invalidResponse:
            return "The notification service returned an unexpected response."
        case let .service(message): return message
        }
    }
}

struct HostedNotificationServiceClient: Sendable {
    private let baseURL = URL(string: "https://kyndyn-notifications.baberickm.workers.dev")!
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func provisionOwner(
        identity: HostedNotificationIdentity,
        deviceToken: String
    ) async throws {
        guard let admin = identity.adminCapability,
              let enrollment = identity.enrollmentCapability else {
            throw HostedNotificationError.ownerRequired
        }
        _ = try await request(
            path: "/v1/households/provision",
            body: body([
                "householdID": identity.householdID.uuidString,
                "adminCapability": admin,
                "enrollmentCapability": enrollment
            ])) as ProvisionResponse
        try await register(identity: identity, token: deviceToken, capability: enrollment)
    }

    func register(
        identity: HostedNotificationIdentity,
        token: String,
        capability: String
    ) async throws {
        _ = try await request(
            path: "/v1/devices/register", bearer: capability,
            body: body([
                "householdID": identity.householdID.uuidString,
                "deviceID": identity.deviceID.uuidString,
                "environment": Self.environment,
                "deviceToken": token,
                "appBuild": Self.build,
                "showBroadcastDetails": Self.showBroadcastDetails
            ])) as DeviceResponse
    }

    func pair(code: String, deviceID: UUID, token: String) async throws
        -> HostedNotificationIdentity {
        let response: PairResponse = try await request(
            path: "/v1/devices/pair",
            body: body([
                "pairingCode": code,
                "deviceID": deviceID.uuidString,
                "environment": Self.environment,
                "deviceToken": token,
                "appBuild": Self.build,
                "showBroadcastDetails": Self.showBroadcastDetails
            ]))
        guard let householdID = UUID(uuidString: response.householdID) else {
            throw HostedNotificationError.invalidResponse
        }
        return HostedNotificationIdentity(
            role: .participant, householdID: householdID, deviceID: deviceID,
            adminCapability: nil, enrollmentCapability: nil,
            deviceCapability: response.deviceCapability)
    }

    func createPairingCode(identity: HostedNotificationIdentity) async throws
        -> PairingCodeResponse {
        guard let admin = identity.adminCapability else {
            throw HostedNotificationError.ownerRequired
        }
        return try await request(
            path: "/v1/pairing-codes", bearer: admin,
            body: body(["householdID": identity.householdID.uuidString]))
    }

    func broadcast(
        identity: HostedNotificationIdentity,
        notificationID: UUID,
        title: String,
        message: String
    ) async throws -> BroadcastResponse {
        guard let admin = identity.adminCapability else {
            throw HostedNotificationError.ownerRequired
        }
        return try await request(
            path: "/v1/broadcasts", bearer: admin,
            body: body([
                "householdID": identity.householdID.uuidString,
                "senderDeviceID": identity.deviceID.uuidString,
                "notificationID": notificationID.uuidString,
                "title": title,
                "body": message
            ]))
    }

    func revoke(identity: HostedNotificationIdentity) async throws {
        let capability = identity.adminCapability ?? identity.deviceCapability
        guard let capability else { throw HostedNotificationError.ownerRequired }
        _ = try await request(
            path: "/v1/devices/revoke", bearer: capability,
            body: body([
                "householdID": identity.householdID.uuidString,
                "deviceID": identity.deviceID.uuidString
            ])) as DeviceResponse
    }

    private func common() -> [String: Any] {
        ["timestamp": ISO8601DateFormatter().string(from: .now),
         "nonce": Self.randomCapability()]
    }

    private func body(_ values: [String: Any]) -> [String: Any] {
        common().merging(values) { _, new in new }
    }

    private func request<Response: Decodable>(
        path: String, bearer: String? = nil, body: [String: Any]
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HostedNotificationError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let failure = try? JSONDecoder().decode(ServiceFailure.self, from: data)
            throw HostedNotificationError.service(
                failure?.message ?? "Family notifications couldn’t be updated. Try again.")
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw HostedNotificationError.invalidResponse
        }
        return decoded
    }

    static func randomCapability() -> String {
        var data = Data(count: 32)
        _ = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static var build: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    private static var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    private static var showBroadcastDetails: Bool {
        UserDefaults.standard.bool(forKey: "hosted-show-broadcast-details")
    }
}

private struct ProvisionResponse: Decodable { let householdID: String }
private struct DeviceResponse: Decodable { let deviceID: String }
private struct PairResponse: Decodable {
    let householdID: String
    let deviceCapability: String
}
struct PairingCodeResponse: Decodable, Sendable {
    let pairingCode: String
    let expiresAt: String
}
struct BroadcastResponse: Decodable, Sendable {
    let accepted: Int
    let retryable: Int
    let failed: Int
    let skipped: Int
}
private struct ServiceFailure: Decodable { let message: String }

@MainActor @Observable final class HostedNotificationCoordinator {
    static let shared = HostedNotificationCoordinator()

    private let store: HostedNotificationCredentialStoring
    private let client: HostedNotificationServiceClient
    private(set) var identity: HostedNotificationIdentity?
    private(set) var status = "Not connected"
    private(set) var lastError: String?
    private var deviceToken: String?

    init(
        store: HostedNotificationCredentialStoring = KeychainHostedNotificationStore(),
        client: HostedNotificationServiceClient = HostedNotificationServiceClient()
    ) {
        self.store = store
        self.client = client
        identity = store.load()
        if identity != nil { status = "Waiting for Apple" }
    }

    var isOwner: Bool { identity?.role == .owner }
    var isConnected: Bool { identity != nil }

    func receive(deviceToken data: Data) {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        Task { await refreshRegistration() }
    }

    func registrationFailed() {
        status = "Waiting for Apple"
        lastError = "Apple hasn’t prepared this device for remote notifications yet."
    }

    func setShowBroadcastDetails(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "hosted-show-broadcast-details")
        Task { await refreshRegistration() }
    }

    func enableOwner() async throws {
        try await requestPermission()
        let deviceToken = try await waitForDeviceToken()
        let identity: HostedNotificationIdentity
        if let existing = self.identity, existing.role == .owner {
            identity = existing
        } else {
            identity = HostedNotificationIdentity(
                role: .owner, householdID: UUID(), deviceID: UUID(),
                adminCapability: HostedNotificationServiceClient.randomCapability(),
                enrollmentCapability: HostedNotificationServiceClient.randomCapability(),
                deviceCapability: nil)
            // Persist first so an interrupted provisioning attempt resumes with the
            // same household and capabilities instead of creating duplicates.
            try store.save(identity)
            self.identity = identity
        }
        status = "Connecting"
        try await client.provisionOwner(identity: identity, deviceToken: deviceToken)
        status = "Connected as owner"
        lastError = nil
    }

    func pair(code: String) async throws {
        try await requestPermission()
        let deviceToken = try await waitForDeviceToken()
        status = "Joining"
        let identity = try await client.pair(
            code: code, deviceID: UUID(), token: deviceToken)
        try store.save(identity)
        self.identity = identity
        status = "Connected to family"
        lastError = nil
    }

    func createPairingCode() async throws -> PairingCodeResponse {
        guard let identity else { throw HostedNotificationError.ownerRequired }
        return try await client.createPairingCode(identity: identity)
    }

    func sendBroadcast(id: UUID, title: String, message: String) async throws
        -> BroadcastResponse? {
        guard let identity, identity.role == .owner else { return nil }
        var lastResponse: BroadcastResponse?
        for attempt in 0..<3 {
            do {
                let response = try await client.broadcast(
                    identity: identity, notificationID: id,
                    title: title, message: message)
                lastResponse = response
                if response.retryable == 0 { return response }
            } catch {
                if attempt == 2 { throw error }
            }
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(1 << attempt))
        }
        return lastResponse
    }

    func recordFailure(_ error: Error) {
        status = "Needs attention"
        lastError = error.localizedDescription
    }

    func disconnect() async throws {
        if let identity { try await client.revoke(identity: identity) }
        try store.remove()
        identity = nil
        status = "Not connected"
        lastError = nil
    }

    func refreshRegistration() async {
        guard let identity, let deviceToken else { return }
        let capability = identity.enrollmentCapability ?? identity.deviceCapability
        guard let capability else { return }
        do {
            try await client.register(
                identity: identity, token: deviceToken, capability: capability)
            status = identity.role == .owner ? "Connected as owner" : "Connected to family"
            lastError = nil
        } catch {
            status = "Needs attention"
            lastError = error.localizedDescription
        }
    }

    private func requestPermission() async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .denied {
            throw HostedNotificationError.permissionDenied
        }
        if settings.authorizationStatus == .notDetermined {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                throw HostedNotificationError.permissionDenied
            }
        }
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func waitForDeviceToken() async throws -> String {
        if let deviceToken { return deviceToken }
        for _ in 0..<40 {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(250))
            if let deviceToken { return deviceToken }
        }
        throw HostedNotificationError.waitingForApple
    }
}
