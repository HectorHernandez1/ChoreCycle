import SwiftUI
import SwiftData
import AppIntents
import UserNotifications

/// `@main` marks the app's entry point, like `if __name__ == "__main__"`.
@main struct MyApp: App {
    /// The SwiftData database, which stores both model types on disk.
    let container: ModelContainer

    /// The person's profile and preferences, backed by `UserDefaults`.
    @State private var settings = UserSettings()

    /// Handles the "Mark Done" button on reminders.
    private let notificationHandler: ReminderNotificationHandler

    /// Set only while unit tests are running; see `init`.
    static var testContainer: ModelContainer?

    init() {
        do {
            if ProcessInfo.processInfo.isRunningTests {
                // Unit tests run inside this app. SwiftData misbehaves when
                // two containers for the same models exist in one process,
                // so instead of opening the real database the app creates a
                // throwaway in-memory one and shares it with the tests.
                // `cloudKitDatabase: .none` keeps tests away from iCloud.
                container = try ModelContainer(
                    for: Chore.self, Completion.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
                )
                MyApp.testContainer = container
            } else {
                // Syncs chores and completions through the person's private
                // iCloud database, so every device signed in to the same
                // Apple Account sees the same checklist. If they're signed
                // out of iCloud, SwiftData quietly keeps everything local
                // and starts syncing once they sign in.
                let configuration = ModelConfiguration(
                    cloudKitDatabase: .private("iCloud.com.hectorhernandezpersonalteam.ChoreCycle")
                )
                container = try ModelContainer(
                    for: Chore.self, Completion.self,
                    configurations: configuration
                )
                StarterChores.seedIfNeeded(into: container.mainContext)
                Chore.assignMissingIDs(in: container.mainContext)
            }
        } catch {
            // Without a database the app can't do anything useful.
            fatalError("Could not create the SwiftData container: \(error)")
        }

        // Siri and Shortcuts can launch the app in the background just to
        // run an intent, so the database they use (`@Dependency` in
        // `ChoreIntents.swift`) has to be registered before anything else.
        let container = container
        AppDependencyManager.shared.add(dependency: container)

        // Likewise, tapping "Mark Done" on a reminder launches the app in
        // the background, so the handler must be in place at launch.
        // `UNUserNotificationCenter.delegate` is a weak reference; the app
        // keeps the handler alive.
        notificationHandler = ReminderNotificationHandler(container: container)
        UNUserNotificationCenter.current().delegate = notificationHandler
        ChoreReminders.registerCategories()
    }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.isRunningTests {
                // Keep the real UI out of the way while tests run. Otherwise
                // its queries and reminder sync read the same in-memory
                // store the tests are mutating, and touching a chore a test
                // just deleted traps.
                Text("Running tests…")
                    .foregroundStyle(.secondary)
            } else {
                MainTabView()
            }
        }
        // Makes the database available to every view below it through
        // `@Query` and `@Environment(\.modelContext)`.
        .modelContainer(container)
        // Likewise for settings, read with `@Environment(UserSettings.self)`.
        .environment(settings)
    }
}

extension ProcessInfo {
    /// Whether this process was launched as the host for a unit test bundle.
    nonisolated var isRunningTests: Bool {
        environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }
}
