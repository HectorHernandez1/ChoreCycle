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
         nextDueDate: Date? = nil) {
        self.name = name
        self.frequency = frequency
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.nextDueDate = nextDueDate
    }
}
