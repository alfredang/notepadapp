import SwiftUI
import SwiftData
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    /// Route scenes through `SceneDelegate` so the app can receive accepted
    /// iCloud share links (`userDidAcceptCloudKitShareWith`). SwiftUI still owns
    /// the window — the delegate only adds the CloudKit-share hook.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

/// App entry point. Installs the SwiftData container and presents the root navigation.
@main
struct NotePadApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Shared model container for the whole app. Created once at launch.
    let container: ModelContainer

    init() {
        do {
            let schema = Schema([Notebook.self, Page.self, AudioNote.self, AppSettings.self])
            // Back the store with the user's private CloudKit database so every
            // notebook and page auto-saves and syncs across their devices.
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                cloudKitDatabase: .private("iCloud.com.tertiaryinfotech.notepadapp")
            )
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
