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
            schemaVersion: KyndynSchema.version,
            alreadyAccepted: false
        )
    }

    func clear() { pending = nil }
}

final class CloudShareAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task {
            await CloudKitShareMetadataVault.shared.store(metadata)
            await MainActor.run { CloudShareInbox.shared.receive(metadata) }
        }
    }
}

@main struct KyndynApp: App {
    @UIApplicationDelegateAdaptor(CloudShareAppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var cloudSync = CloudSyncController(
        transport: CloudTransportFactory.make())
    @State private var invitationRouter = InvitationRouter(
        transport: CloudTransportFactory.make())
    @StateObject private var parentAccess = ParentAccessController()
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer?
    private let storeError: String?

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
                configuration = ModelConfiguration(schema: schema, url: directory.appending(path: "kyndyn.store"))
            } else {
                configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: testing)
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
                        .environment(invitationRouter)
                        .environmentObject(parentAccess)
                        .modelContainer(container)
                        .task {
                            parentAccess.unlockForUITesting()
                            await Task.yield()
                            model.finishedPreparing()
                        }
                } else {
                    StoreRecoveryView(detail: storeError)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background: parentAccess.didEnterBackground()
                case .active: parentAccess.didBecomeActive()
                default: break
                }
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
