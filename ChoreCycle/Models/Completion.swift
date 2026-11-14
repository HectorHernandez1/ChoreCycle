import Foundation
import SwiftData

/// A record that a chore was checked off at a specific moment.
///
/// Chores are never "unchecked" when a new week or month starts. Instead, a
/// chore counts as done only if it has a `Completion` inside the current
/// period (see `Chore+Period.swift`). Old completions simply stop counting.
@Model
final class Completion {
    /// The default is only there to satisfy iCloud sync; see `Chore`.
    var completedAt: Date = Date.now

    /// `true` when the person chose "Skip" instead of doing the chore. A
    /// skip takes the chore off this period's list without counting as
    /// done, and doesn't count against a streak. For long-cycle chores it
    /// also moves the next due date forward, as if it had been done.
    var isSkip: Bool = false

    /// The chore this completion belongs to. It's optional because SwiftData
    /// relationships must be able to be empty while objects are being created
    /// or deleted. The other side of this link is `Chore.completions`.
    var chore: Chore?

    init(completedAt: Date = .now, isSkip: Bool = false) {
        self.completedAt = completedAt
        self.isSkip = isSkip
    }
}
