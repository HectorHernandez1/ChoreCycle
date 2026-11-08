import Foundation
import SwiftData

/// A chore the user wants to do once per week or once per month.
///
/// `@Model` is a SwiftData macro. It turns this ordinary class into a
/// persisted database entity (similar to a SQLAlchemy or Django model) and
/// makes it observable, so any SwiftUI view that reads a property redraws
/// automatically when that property changes.
@Model
final class Chore {
    var name: String
    var frequency: Frequency
    var sortOrder: Int
    var createdAt: Date

    /// Every time this chore was checked off, across all weeks and months.
    ///
    /// `@Relationship` tells SwiftData this is a link to other models rather
    /// than plain data. `inverse:` pairs it with `Completion.chore` so both
    /// sides stay in sync, and `.cascade` deletes a chore's completions when
    /// the chore itself is deleted (otherwise they'd be left orphaned).
    @Relationship(deleteRule: .cascade, inverse: \Completion.chore)
    var completions: [Completion] = []

    init(name: String, frequency: Frequency, sortOrder: Int, createdAt: Date = .now) {
        self.name = name
        self.frequency = frequency
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
