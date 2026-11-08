import SwiftUI
import SwiftData

/// `@main` marks the app's entry point, like `if __name__ == "__main__"`.
@main struct MyApp: App {
    /// The SwiftData database, which stores both model types on disk.
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Chore.self, Completion.self)
        } catch {
            // Without a database the app can't do anything useful.
            fatalError("Could not create the SwiftData container: \(error)")
        }
        StarterChores.seedIfNeeded(into: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ChoreListView()
        }
        // Makes the database available to every view below it through
        // `@Query` and `@Environment(\.modelContext)`.
        .modelContainer(container)
    }
}
