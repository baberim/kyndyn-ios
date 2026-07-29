import CloudKit
import Foundation

enum KyndynCloudEnvironment: String, Equatable, Sendable {
    case development
    case production
}

struct KyndynCloudConfiguration: Equatable, Sendable {
    static let containerInfoKey = "KyndynCloudKitContainerIdentifier"
    static let enabledInfoKey = "KyndynCloudSyncConfigured"
    static let environmentInfoKey = "KyndynCloudKitEnvironment"

    let containerIdentifier: String?
    let environment: KyndynCloudEnvironment
    let isEnabled: Bool

    init(
        info: [String: Any] = Bundle.main.infoDictionary ?? [:],
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        let identifier = (info[Self.containerInfoKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        containerIdentifier = identifier.flatMap { $0.isEmpty ? nil : $0 }
        environment = KyndynCloudEnvironment(
            rawValue: (info[Self.environmentInfoKey] as? String)?
                .lowercased() ?? ""
        ) ?? .development
        if arguments.contains("-ui-testing-cloud-unconfigured") {
            isEnabled = false
        } else if let enabled = info[Self.enabledInfoKey] as? Bool {
            isEnabled = enabled
        } else {
            isEnabled = (info[Self.enabledInfoKey] as? String)?
                .lowercased() == "yes"
        }
    }

    var readiness: KyndynCloudReadiness {
        guard isEnabled else { return .disabled }
        guard let containerIdentifier else { return .missingContainerIdentifier }
        guard containerIdentifier.hasPrefix("iCloud."),
              containerIdentifier.count > "iCloud.".count else {
            return .invalidContainerIdentifier
        }
        return .ready(containerIdentifier: containerIdentifier,
                      environment: environment)
    }
}

enum KyndynCloudReadiness: Equatable, Sendable {
    case disabled
    case missingContainerIdentifier
    case invalidContainerIdentifier
    case ready(containerIdentifier: String, environment: KyndynCloudEnvironment)

    var developmentMessage: String {
        switch self {
        case .disabled:
            return "Family sync is not configured in this build. Select an authorized Apple Developer Team and development CloudKit container in Xcode."
        case .missingContainerIdentifier:
            return "Family sync is enabled, but its iCloud container identifier is missing."
        case .invalidContainerIdentifier:
            return "The configured iCloud container identifier is invalid. It must begin with “iCloud.”"
        case let .ready(_, environment):
            return "Family sync is configured for Apple’s \(environment.rawValue) CloudKit environment."
        }
    }
}

enum KyndynCloudContainerFactory {
    static func make(
        configuration: KyndynCloudConfiguration = KyndynCloudConfiguration()
    ) -> Result<CKContainer, KyndynCloudReadinessError> {
        switch configuration.readiness {
        case let .ready(identifier, _):
            return .success(CKContainer(identifier: identifier))
        case let readiness:
            return .failure(KyndynCloudReadinessError(readiness: readiness))
        }
    }
}

struct KyndynCloudReadinessError: LocalizedError {
    let readiness: KyndynCloudReadiness
    var errorDescription: String? { readiness.developmentMessage }
}
