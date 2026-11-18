import SwiftUI
import SwiftData
import Observation

/// What the chore editor is showing: a new chore (starting on a given
/// frequency) or an existing one.
enum ChoreEditorRequest: Identifiable {
    case new(Frequency)
    case edit(Chore)

    var id: AnyHashable {
        switch self {
        case .new(let frequency): AnyHashable("new-\(frequency.rawValue)")
        case .edit(let chore): AnyHashable(chore.persistentModelID)
        }
    }
}

/// Opens the chore editor for the whole app, so it can sit beside both
/// lists on a wide screen instead of inside one of them.
///
/// `MainTabView` owns one of these, presents its `request` as an inspector
/// panel (a sheet on narrow screens), and shares it through the
/// environment. Because it lives above the tab layout, an open editor
/// stays open when the phone is folded or unfolded.
@Observable
final class ChoreEditorPresenter {
    var request: ChoreEditorRequest?

    func edit(_ chore: Chore) {
        request = .edit(chore)
    }

    func add(_ frequency: Frequency) {
        request = .new(frequency)
    }

    /// Closes the editor if it's showing one of `chores`, so it never
    /// edits a chore that was just deleted.
    func close(ifEditingAnyOf chores: [Chore]) {
        guard case .edit(let current)? = request,
              chores.contains(where: { $0.persistentModelID == current.persistentModelID })
        else { return }
        request = nil
    }
}
