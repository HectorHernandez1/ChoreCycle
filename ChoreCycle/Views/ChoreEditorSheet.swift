import SwiftUI
import SwiftData

/// A sheet for adding a new chore, or editing an existing one.
struct ChoreEditorSheet: View {
    /// The chore being edited, or `nil` when adding a new one.
    let chore: Chore?

    @Environment(\.modelContext) private var modelContext

    /// `dismiss` is an action SwiftUI provides to close the current sheet.
    @Environment(\.dismiss) private var dismiss

    // Draft values. Edits only touch the real chore when Save is tapped, so
    // Cancel really cancels. These have no initial value here because they
    // are set in `init` below.
    @State private var name: String
    @State private var frequency: Frequency

    init(chore: Chore? = nil) {
        self.chore = chore
        self.name = chore?.name ?? ""
        self.frequency = chore?.frequency ?? .weekly
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Chore name", text: $name)

                Picker("Repeats", selection: $frequency) {
                    ForEach(Frequency.allCases) { frequency in
                        Text(frequency.title).tag(frequency)
                    }
                }
                .pickerStyle(.segmented)
            }
            .navigationTitle(chore == nil ? "New Chore" : "Edit Chore")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private func save() {
        if let chore {
            // A chore moved to the other section goes to the bottom of it.
            if chore.frequency != frequency {
                chore.sortOrder = nextSortOrder()
            }
            chore.name = trimmedName
            chore.frequency = frequency
        } else {
            // Put new chores at the bottom of the list.
            modelContext.insert(Chore(name: trimmedName, frequency: frequency, sortOrder: nextSortOrder()))
        }
        dismiss()
    }

    /// One more than the highest `sortOrder` in use.
    private func nextSortOrder() -> Int {
        let allChores = (try? modelContext.fetch(FetchDescriptor<Chore>())) ?? []
        return (allChores.map(\.sortOrder).max() ?? -1) + 1
    }
}

#Preview(traits: .sampleData) {
    ChoreEditorSheet()
}
