import Foundation
import SwiftData

/// A record that a chore was checked off at a specific moment.
///
/// Chores are never "unchecked" when a new week or month starts. Instead, a
/// chore counts as done only if it has a `Completion` inside the current
/// period (see `Chore+Period.swift`). Old completions simply stop counting.
@Model
final class Completion {
    var completedAt: Date

    /// The chore this completion belongs to. It's optional because SwiftData
    /// relationships must be able to be empty while objects are being created
    /// or deleted. The other side of this link is `Chore.completions`.
    var chore: Chore?

    init(completedAt: Date = .now) {
        self.completedAt = completedAt
    }
}
