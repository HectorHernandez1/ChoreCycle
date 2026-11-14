import Foundation
import SwiftData

/// A chore the user wants to do on a repeating schedule.
///
/// `@Model` is a SwiftData macro. It turns this ordinary class into a
/// persisted database entity (similar to a SQLAlchemy or Django model) and
/// makes it observable, so any SwiftUI view that reads a property redraws
/// automatically when that property changes.
///
/// iCloud sync (CloudKit) requires every stored property to have a default
/// value or be optional, and every relationship to be optional. The defaults
/// below are never actually used by the app; `init` always sets real values.
@Model
final class Chore {
    var name: String = ""
    var frequency: Frequency = Frequency.weekly
    var sortOrder: Int = 0
    var createdAt: Date = Date.now

    /// For rolling chores (every 3 months, 6 months, yearly) that have never
    /// been checked off: when they're first due. Lets someone enter "I last
    /// did this in August" without the chore showing up as overdue. Ignored
    /// once the chore has a completion, and always `nil` for weekly and
    /// monthly chores.
    ///
    /// Optional so SwiftData can add the column to existing databases
    /// without a migration step.
    var nextDueDate: Date?

    /// A permanent ID that Siri and Shortcuts use to refer to this chore.
    ///
    /// SwiftData's own `persistentModelID` differs from device to device
    /// under iCloud sync, so saved shortcuts couldn't rely on it. This UUID
    /// syncs like any other field.
    ///
    /// It's optional because chores saved before this field existed don't
    /// have one. A non-optional default would hand every one of them the
    /// *same* UUID during the upgrade, so instead `assignMissingIDs(in:)`
    /// fills them in at launch.
    var choreID: UUID?

    /// Every time this chore was checked off, across all weeks and months.
    ///
    /// `@Relationship` tells SwiftData this is a link to other models rather
    /// than plain data. `inverse:` pairs it with `Completion.chore` so both
    /// sides stay in sync, and `.cascade` deletes a chore's completions when
    /// the chore itself is deleted (otherwise they'd be left orphaned).
    ///
    /// Optional only because CloudKit insists on it. Read it through
    /// `allCompletions` and add to it with `addCompletion(at:)` (both in
    /// `Chore+Period.swift`) rather than unwrapping it everywhere.
    @Relationship(deleteRule: .cascade, inverse: \Completion.chore)
    var completions: [Completion]? = []

    init(name: String,
         frequency: Frequency,
         sortOrder: Int,
         createdAt: Date = .now,
         nextDueDate: Date? = nil,
         choreID: UUID = UUID()) {
        self.name = name
        self.frequency = frequency
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.nextDueDate = nextDueDate
        self.choreID = choreID
    }
}

extension Chore {
    /// Gives a `choreID` to any chore that doesn't have one yet (chores
    /// from before the field existed, or synced from an older version).
    static func assignMissingIDs(in context: ModelContext) {
        let missing = FetchDescriptor<Chore>(predicate: #Predicate { $0.choreID == nil })
        guard let chores = try? context.fetch(missing), !chores.isEmpty else { return }
        for chore in chores {
            chore.choreID = UUID()
        }
        try? context.save()
    }
}

extension Chore {
    /// Applies a drag-to-reorder within one section of the list.
    ///
    /// `sortOrder` is shared by every chore in the app, not just one
    /// section, so rather than renumbering from zero (which could collide
    /// with chores in other tabs) the section's existing `sortOrder` values
    /// are handed back out in the new order.
    static func reorder(_ chores: [Chore], fromOffsets source: IndexSet, toOffset destination: Int) {
        let slots = chores.map(\.sortOrder).sorted()

        // Same rules as SwiftUI's `move(fromOffsets:toOffset:)`: pull out
        // the dragged rows, then drop them where `destination` pointed
        // before they were removed.
        let moved = source.map { chores[$0] }
        var reordered = chores.enumerated()
            .filter { !source.contains($0.offset) }
            .map(\.element)
        let insertAt = destination - source.count(in: 0..<destination)
        reordered.insert(contentsOf: moved, at: insertAt)

        for (chore, slot) in zip(reordered, slots) where chore.sortOrder != slot {
            chore.sortOrder = slot
        }
    }
}
