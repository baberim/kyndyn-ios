import BackgroundTasks
import CloudKit
import SwiftUI
import SwiftData
import UIKit

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

final class CloudShareAppDelegate: NSObject, UIApplicationDelegate {
    static let refreshIdentifier = "com.kyndynfamily.kyndyn.sync-refresh"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
            [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshIdentifier, using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            AutomaticSyncBackgroundBridge.shared.handle(refreshTask)
        }
        return true
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
    private let container: ModelContainer?
    private let storeError: String?
    private let connectivity = ConnectivityRestorationMonitor()

    init() {
        let schema = Schema([
            Household.self, Person.self, Quest.self, QuestCompletion.self,
            RewardGoal.self, FamilyBroadcast.self, Companion.self,
            Background.self, HouseholdSettings.self, LocalDeviceSettings.self,
            HouseholdCloudState.self, SyncRecordMetadata.self,
            PendingSyncMutation.self, SyncConflict.self,
            PendingShareInvitation.self
        ])
        let arguments = ProcessInfo.processInfo.arguments
        let testing = arguments.contains("-ui-testing-reset")
        do {
            let configuration: ModelConfiguration
            if arguments.contains("-ui-testing-persistence") {
                let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "kyndynPersistenceUITest", directoryHint: .isDirectory)
                if arguments.contains("-ui-testing-persistence-reset") {
                    try? FileManager.default.removeItem(at: directory)
                }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
            container = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
            storeError = nil
        } catch {
            container = nil
            storeError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                KyndynLaunchBackground()
                if let container {
                    RootView()
                        .environment(model)
                        .environment(cloudSync)
                        .environment(automaticSync)
                        .environment(invitationRouter)
                        .environmentObject(parentAccess)
                        .modelContainer(container)
                        .task {
                            automaticSync.configure(
                                controller: cloudSync,
                                context: container.mainContext)
                            AutomaticSyncBackgroundBridge.shared.coordinator =
                                automaticSync
                            connectivity.start()
                            parentAccess.unlockForUITesting()
                            await Task.yield()
                            model.finishedPreparing()
                            automaticSync.request(.launch)
                        }
                } else {
                    StoreRecoveryView(detail: storeError)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    parentAccess.didEnterBackground()
                    AutomaticSyncBackgroundBridge.shared.schedule()
                case .active:
                    parentAccess.didBecomeActive()
                    automaticSync.request(.becameActive)
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

struct StoreRecoveryView: View {
    let detail: String?
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 54))
                .foregroundStyle(.purple)
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
