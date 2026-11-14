import Foundation
import SwiftData

/// A copy of a chore taken just before it's deleted, so "Undo" can bring it
/// back along with its whole check-off history.
///
/// Deleting a SwiftData object really removes it (and, through the cascade
/// rule, its completions), so there's nothing left to "un-delete". Instead
/// this keeps plain values and rebuilds a fresh `Chore` from them.
struct DeletedChore {
    let name: String
    let frequency: Frequency
    let sortOrder: Int
    let createdAt: Date
    let nextDueDate: Date?
    let completionDates: [Date]

    init(_ chore: Chore) {
        name = chore.name
        frequency = chore.frequency
        sortOrder = chore.sortOrder
        createdAt = chore.createdAt
        nextDueDate = chore.nextDueDate
        completionDates = chore.allCompletions.map(\.completedAt)
    }

    /// Inserts a new chore with the saved values and completions.
    @discardableResult
    func restore(into context: ModelContext) -> Chore {
        let chore = Chore(name: name,
                          frequency: frequency,
                          sortOrder: sortOrder,
                          createdAt: createdAt,
                          nextDueDate: nextDueDate)
        context.insert(chore)
        for date in completionDates {
            chore.addCompletion(at: date)
        }
        return chore
    }
}
