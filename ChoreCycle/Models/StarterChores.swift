import Foundation
import SwiftData

/// The few key-value calls seeding needs. Both `UserDefaults` and
/// `NSUbiquitousKeyValueStore` already provide them, which lets tests swap
/// in a throwaway `UserDefaults` instead of touching the real iCloud store.
protocol FlagStore {
    func bool(forKey key: String) -> Bool
    func set(_ value: Bool, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension UserDefaults: FlagStore {}
extension NSUbiquitousKeyValueStore: FlagStore {}

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
    ///
    /// With iCloud sync, a second device starts out with an empty local
    /// database even though the person's chores are on their way down from
    /// iCloud. To avoid seeding a duplicate set there, the "already seeded"
    /// flag is also stored in `NSUbiquitousKeyValueStore`, iCloud's synced
    /// counterpart to `UserDefaults`.
    static func seedIfNeeded(into context: ModelContext,
                             defaults: UserDefaults = .standard,
                             cloud: any FlagStore = NSUbiquitousKeyValueStore.default) {
        // Pull in the latest synced values before reading the flag.
        cloud.synchronize()

        if defaults.bool(forKey: didSeedKey) || cloud.bool(forKey: didSeedKey) {
            // Copy the flag to whichever store is missing it, so devices
            // that seeded before sync existed tell the others too.
            markSeeded(defaults: defaults, cloud: cloud)
            return
        }
        guard let existingCount = try? context.fetchCount(FetchDescriptor<Chore>()) else { return }

        if existingCount == 0 {
            insert(into: context)
            try? context.save()
        }
        markSeeded(defaults: defaults, cloud: cloud)
    }

    private static func markSeeded(defaults: UserDefaults, cloud: any FlagStore) {
        defaults.set(true, forKey: didSeedKey)
        cloud.set(true, forKey: didSeedKey)
    }

    /// Inserts the starter chores unconditionally. Also used by previews.
    static func insert(into context: ModelContext) {
        let all = weekly.map { ($0, Frequency.weekly) } + monthly.map { ($0, Frequency.monthly) }
        for (index, (name, frequency)) in all.enumerated() {
            context.insert(Chore(name: name, frequency: frequency, sortOrder: index))
        }
    }
}
