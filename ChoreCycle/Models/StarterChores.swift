import Foundation
import SwiftData

/// Adds a starter set of chores the very first time the app launches.
enum StarterChores {
    /// `UserDefaults` is a small key-value store for app settings, similar to
    /// a persistent dictionary. We use it to remember that seeding already
    /// happened, so deleting every chore later won't bring the starters back.
    private static let didSeedKey = "didSeedStarterChores"

    static let weekly = [
        "Take out trash and recycling",
        "Laundry",
        "Vacuum",
        "Clean kitchen",
        "Clean bathroom",
    ]

    static let monthly = [
        "Change air filter",
        "Deep clean fridge",
        "Pay bills / review budget",
    ]

    /// Seeds the starter chores once, and only if the database is empty.
    static func seedIfNeeded(into context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: didSeedKey) else { return }
        guard let existingCount = try? context.fetchCount(FetchDescriptor<Chore>()) else { return }

        if existingCount == 0 {
            insert(into: context)
            try? context.save()
        }
        defaults.set(true, forKey: didSeedKey)
    }

    /// Inserts the starter chores unconditionally. Also used by previews.
    static func insert(into context: ModelContext) {
        let all = weekly.map { ($0, Frequency.weekly) } + monthly.map { ($0, Frequency.monthly) }
        for (index, (name, frequency)) in all.enumerated() {
            context.insert(Chore(name: name, frequency: frequency, sortOrder: index))
        }
    }
}
