import SwiftUI
import SwiftData

/// The main screen: a checklist with "This Week" and "This Month" sections.
struct ChoreListView: View {
    /// `@Query` is a live database fetch. SwiftData fills this array and
    /// re-runs `body` whenever chores are added, edited, or deleted, so
    /// there's no manual "reload" step.
    @Query(sort: [SortDescriptor(\Chore.sortOrder), SortDescriptor(\Chore.createdAt)])
    private var chores: [Chore]

    /// `@Environment` reads values SwiftUI passes down the view tree. The
    /// `modelContext` is the SwiftData "session" (like a database session in
    /// SQLAlchemy) used to insert and delete objects. It comes from the
    /// `.modelContainer(...)` modifier in `MyApp.swift`.
    @Environment(\.modelContext) private var modelContext

    /// Whether the app is in the foreground, background, etc.
    @Environment(\.scenePhase) private var scenePhase

    /// `@State` is view-owned memory that survives redraws. Changing it
    /// makes SwiftUI redraw the view. `now` is the reference date for
    /// deciding which week or month is "current".
    @State private var now = Date.now
    @State private var isAddingChore = false
    @State private var choreBeingEdited: Chore?

    var body: some View {
        NavigationStack {
            List {
                choreSection(title: "This Week", frequency: .weekly)
                choreSection(title: "This Month", frequency: .monthly)
            }
            .navigationTitle("ChoreCycle")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Chore", systemImage: "plus") {
                        isAddingChore = true
                    }
                }
            }
            // Sheets are presented when their binding becomes true / non-nil
            // and dismissed when it goes back to false / nil.
            .sheet(isPresented: $isAddingChore) {
                ChoreEditorSheet()
            }
            .sheet(item: $choreBeingEdited) { chore in
                ChoreEditorSheet(chore: chore)
            }
        }
        // Refresh "now" when returning to the app, so a week or month that
        // rolled over while the app was in the background shows as reset.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                now = .now
            }
        }
    }

    /// One section of the list, filtered to a single frequency.
    private func choreSection(title: String, frequency: Frequency) -> some View {
        let sectionChores = chores.filter { $0.frequency == frequency }
        let doneCount = sectionChores.filter { $0.isDone(asOf: now) }.count

        return Section {
            ForEach(sectionChores) { chore in
                ChoreRowView(
                    chore: chore,
                    isDone: chore.isDone(asOf: now),
                    onToggle: { toggle(chore) },
                    onEdit: { choreBeingEdited = chore }
                )
            }
            // `.onDelete` adds the standard swipe-left-to-delete gesture.
            .onDelete { offsets in
                for index in offsets {
                    modelContext.delete(sectionChores[index])
                }
            }
        } header: {
            Text("\(title) (\(doneCount) of \(sectionChores.count) done)")
        }
    }

    private func toggle(_ chore: Chore) {
        // Use the real current time, in case "now" went stale while the app
        // sat open across midnight.
        now = .now
        chore.toggleCompletion(on: now, in: modelContext)
    }
}

#Preview(traits: .sampleData) {
    ChoreListView()
}
