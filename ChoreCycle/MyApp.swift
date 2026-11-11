import SwiftUI
import SwiftData

/// `@main` marks the app's entry point, like `if __name__ == "__main__"`.
@main struct MyApp: App {
    /// The SwiftData database, which stores both model types on disk.
    let container: ModelContainer

    /// The person's profile and preferences, backed by `UserDefaults`.
    @State private var settings = UserSettings()

    /// Set only while unit tests are running; see `init`.
    static var testContainer: ModelContainer?

    init() {
        do {
            if ProcessInfo.processInfo.isRunningTests {
                // Unit tests run inside this app. SwiftData misbehaves when
                // two containers for the same models exist in one process,
                // so instead of opening the real database the app creates a
                // throwaway in-memory one and shares it with the tests.
                container = try ModelContainer(
                    for: Chore.self, Completion.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
                MyApp.testContainer = container
            } else {
                container = try ModelContainer(for: Chore.self, Completion.self)
                StarterChores.seedIfNeeded(into: container.mainContext)
            }
        } catch {
            // Without a database the app can't do anything useful.
            fatalError("Could not create the SwiftData container: \(error)")
        }
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
