import BackgroundTasks
import CloudKit
import AppIntents
import SwiftUI
import SwiftData
import UIKit
import UserNotifications

private final class SendableBackgroundRefreshTask: @unchecked Sendable {
    let value: BGAppRefreshTask

    init(_ value: BGAppRefreshTask) {
        self.value = value
    }
}

@MainActor
@Observable final class CloudShareInbox {
    static let shared = CloudShareInbox()
    private(set) var pending: ShareInvitation?

    func receive(_ metadata: CKShare.Metadata) {
        pending = ShareInvitation(
            shareIdentifier: metadata.share.recordID.recordName,
            rootRecordName: metadata.hierarchicalRootRecordID?.recordName ?? "",
            zoneName: metadata.hierarchicalRootRecordID?.zoneID.zoneName ?? "",
            zoneOwnerName: metadata.hierarchicalRootRecordID?.zoneID.ownerName,
            schemaVersion: KyndynSchema.version,
            alreadyAccepted: metadata.participantStatus == .accepted
        )
    }

    func clear() { pending = nil }
}

final class CloudShareAppDelegate: NSObject, UIApplicationDelegate,
    UNUserNotificationCenterDelegate {
    static let refreshIdentifier = "com.kyndynfamily.kyndyn.sync-refresh"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
            [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshIdentifier,
            using: nil,
            launchHandler: Self.handleBackgroundRefresh
        )
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated private static func handleBackgroundRefresh(_ task: BGTask) {
        guard let refreshTask = task as? BGAppRefreshTask else {
            task.setTaskCompleted(success: false)
            return
        }
        let sendableTask = SendableBackgroundRefreshTask(refreshTask)
        Task { @MainActor in
            AutomaticSyncBackgroundBridge.shared.handle(sendableTask.value)
        }
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = CloudShareSceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        CloudShareReceiver.receive(metadata)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler:
            @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            let completed = await AutomaticSyncBackgroundBridge.shared.perform(
                .remoteNotification)
            completionHandler(completed ? .newData : .noData)
        }
    }
}

final class CloudShareSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let metadata = connectionOptions.cloudKitShareMetadata else {
            return
        }
        CloudShareReceiver.receive(metadata)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        CloudShareReceiver.receive(metadata)
    }
}

@MainActor
private enum CloudShareReceiver {
    static func receive(_ metadata: CKShare.Metadata) {
        Task {
            await CloudKitShareMetadataVault.shared.store(metadata)
            CloudShareInbox.shared.receive(metadata)
            AutomaticSyncSignalCenter.shared.send(.shareAccepted)
        }
    }
}

@MainActor
final class AutomaticSyncBackgroundBridge {
    static let shared = AutomaticSyncBackgroundBridge()
    weak var coordinator: AutomaticSyncCoordinator?

    func handle(_ task: BGAppRefreshTask) {
        guard let coordinator else {
            task.setTaskCompleted(success: false)
            return
        }
        task.expirationHandler = {
            Task { @MainActor in
                coordinator.cancelForBackgroundExpiration()
            }
        }
        coordinator.request(.backgroundRefresh)
        Task {
            await coordinator.waitUntilIdle()
            task.setTaskCompleted(success: !Task.isCancelled)
        }
    }

    func perform(_ trigger: AutomaticSyncTrigger) async -> Bool {
        guard let coordinator else { return false }
        let previousRuns = coordinator.completedRunCount
        coordinator.request(trigger)
        await coordinator.waitUntilIdle()
        return coordinator.completedRunCount > previousRuns
    }

    func schedule() {
        let request = BGAppRefreshTaskRequest(
            identifier: CloudShareAppDelegate.refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

@MainActor
final class ForegroundSyncPulse {
    private let interval: Duration
    private var task: Task<Void, Never>?

    init(interval: Duration = .seconds(15)) {
        self.interval = interval
    }

    func start(coordinator: AutomaticSyncCoordinator) {
        stop()
        task = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                coordinator.request(.foregroundCatchUp)
                await coordinator.waitUntilIdle()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

@main struct KyndynApp: App {
    @UIApplicationDelegateAdaptor(CloudShareAppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var cloudSync = CloudSyncController(
        transport: CloudTransportFactory.make())
    @State private var invitationRouter = InvitationRouter(
        transport: CloudTransportFactory.make())
    @State private var automaticSync = AutomaticSyncCoordinator()
    @StateObject private var parentAccess = ParentAccessController()
    @Environment(\.scenePhase) private var scenePhase
    @State private var container: ModelContainer?
    @State private var storeError: String?
    @State private var isPreparingStore = false
    private let connectivity = ConnectivityRestorationMonitor()
    private let foregroundSyncPulse = ForegroundSyncPulse()

    init() {
        UITableView.appearance().backgroundColor = .clear
        UICollectionView.appearance().backgroundColor = .clear
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            KyndynAppShortcuts.updateAppShortcutParameters()
        }
    }

    nonisolated private static func makeContainer(
        arguments: [String]
    ) throws -> ModelContainer {
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
        let testing = arguments.contains("-ui-testing-reset")
        let configuration: ModelConfiguration
        if arguments.contains("-ui-testing-persistence") {
            let directory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "kyndynPersistenceUITest",
                           directoryHint: .isDirectory)
            if arguments.contains("-ui-testing-persistence-reset") {
                try? FileManager.default.removeItem(at: directory)
            }
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            configuration = ModelConfiguration(
                schema: schema,
                url: directory.appending(path: "kyndyn.store"),
                cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: testing,
                cloudKitDatabase: .none
            )
        }
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                KyndynScreenBackground()
                if let container {
                    RootView()
                        .environment(model)
                        .environment(cloudSync)
                        .environment(automaticSync)
                        .environment(invitationRouter)
                        .environmentObject(parentAccess)
                        .modelContainer(container)
                } else if let storeError {
                    StoreRecoveryView(detail: storeError)
                } else {
                    KyndynStartupView()
                }
            }
            .task {
                guard container == nil, storeError == nil,
                      !isPreparingStore else { return }
                isPreparingStore = true
                // Let the launch artwork transition to an animating SwiftUI
                // loading surface before opening or migrating the local store.
                await Task.yield()
                do {
                    let arguments = ProcessInfo.processInfo.arguments
                    container = try await Task.detached(priority: .userInitiated) {
                        try Self.makeContainer(arguments: arguments)
                    }.value
                } catch {
                    storeError = error.localizedDescription
                }
                isPreparingStore = false
                guard let container else { return }
                if ProcessInfo.processInfo.environment[
                    "XCTestConfigurationFilePath"] == nil {
                    KyndynIntentStore.shared.configure(
                        container: container, appModel: model)
                }
                // Leave the branded preparation overlay before optional network
                // work. Local SwiftData remains the immediate presentation source.
                model.finishedPreparing()
                automaticSync.configure(
                    controller: cloudSync,
                    context: container.mainContext)
                AutomaticSyncBackgroundBridge.shared.coordinator = automaticSync
                connectivity.start()
                foregroundSyncPulse.start(coordinator: automaticSync)
                parentAccess.unlockForUITesting()
                automaticSync.request(.launch)
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    parentAccess.didEnterBackground()
                    foregroundSyncPulse.stop()
                    AutomaticSyncBackgroundBridge.shared.schedule()
                case .active:
                    parentAccess.didBecomeActive()
                    automaticSync.request(.becameActive)
                    foregroundSyncPulse.start(
                        coordinator: automaticSync)
                default: break
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .kyndynAutomaticSyncRequested)
            ) { notification in
                guard let raw = notification.userInfo?["trigger"] as? String,
                      let trigger = AutomaticSyncTrigger(rawValue: raw) else {
                    return
                }
                automaticSync.request(trigger)
            }
        }
    }
}

struct KyndynLaunchBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color.purple.opacity(0.20), Color.cyan.opacity(0.10), Color(.systemBackground)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct KyndynStartupView: View {
    var body: some View {
        VStack(spacing: 22) {
            Image("KyndynSplash")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 280)
                .accessibilityHidden(true)
            ProgressView()
                .controlSize(.large)
                .tint(KyndynTheme.purple)
            Text("Opening your family…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.965, green: 0.965, blue: 0.980))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Opening kyndyn and preparing your family")
        .accessibilityIdentifier("startup-loading")
    }
}

struct StoreRecoveryView: View {
    let detail: String?
    var body: some View {
        VStack(spacing: 18) {
            Image("KyndynMark")
                .resizable()
                .scaledToFit()
                .frame(width: 62, height: 62)
                .accessibilityHidden(true)
            Text("kyndyn needs a moment")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("Your family data wasn’t changed. Close and reopen kyndyn. If this continues, keep this app installed and contact support before removing any data.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let detail {
                DisclosureGroup("Technical details") {
                    Text(detail).font(.caption).textSelection(.enabled)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: 560)
        .accessibilityElement(children: .contain)
    }
}
