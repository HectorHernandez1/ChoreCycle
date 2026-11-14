import SwiftUI
import SwiftData

/// A checklist screen for a single frequency: either this week's chores or
/// this month's chores. `MainTabView` shows one of these per tab.
///
/// The Monthly tab also hosts long-cycle chores (every 3 months, 6 months,
/// yearly). Those appear in a "Due this month" section in the month they're
/// due and in a collapsed "Upcoming" section otherwise. Neither section
/// exists until the person creates at least one long-cycle chore.
struct ChoreListView: View {
    /// Which chores this screen shows (weekly or monthly).
    let frequency: Frequency

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

    /// People who turn on Reduce Motion get the haptic but no confetti.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Accent color and the confetti on/off switch live here.
    @Environment(UserSettings.self) private var settings

    /// Name of the coordinate space rows use to report where their check
    /// circle is, so confetti bursts from the right place.
    static let confettiSpace = "choreList"

    /// `@State` is view-owned memory that survives redraws. Changing it
    /// makes SwiftUI redraw the view. `now` is the reference date for
    /// deciding which week or month is "current".
    @State private var now = Date.now
    @State private var isAddingChore = false
    @State private var choreBeingEdited: Chore?
    @State private var isUpcomingExpanded = false

    /// The chores removed by the most recent delete, kept while the Undo
    /// banner is showing. A new delete replaces it, making the older one
    /// permanent.
    @State private var pendingUndo: PendingUndo?

    /// VoiceOver users get as long as they need to reach the Undo button.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    /// How long the Undo banner stays up on its own.
    private static let undoTimeout: Duration = .seconds(6)

    /// Confetti currently falling. Bursts remove themselves when finished.
    @State private var bursts: [ConfettiBurst] = []

    /// Bumped on every celebration to fire a haptic; `lastCelebrationWasBig`
    /// decides which one.
    @State private var celebrationCount = 0
    @State private var lastCelebrationWasBig = false

    /// The navigation bar title for this screen.
    private var title: String {
        switch frequency {
        case .weekly: "This Week"
        default: "This Month"
        }
    }

    /// The regular chores for this tab: weekly on the Weekly tab, monthly on
    /// the Monthly tab.
    private var regularChores: [Chore] {
        chores.filter { $0.frequency == frequency }
    }

    /// Long-cycle chores, which only ever appear on the Monthly tab.
    private var longCycleChores: [Chore] {
        guard frequency == .monthly else { return [] }
        return chores.filter { !$0.frequency.isCalendarAligned }
    }

    /// Long-cycle chores that belong in this month's checklist, soonest first.
    private var dueThisMonth: [Chore] {
        longCycleChores
            .filter { $0.isDue(inMonthContaining: now) }
            .sorted { ($0.dueDate(asOf: now) ?? now) < ($1.dueDate(asOf: now) ?? now) }
    }

    /// Long-cycle chores not due until a later month, soonest first.
    private var upcoming: [Chore] {
        longCycleChores
            .filter { !$0.isDue(inMonthContaining: now) }
            .sorted { ($0.dueDate(asOf: now) ?? now) < ($1.dueDate(asOf: now) ?? now) }
    }

    var body: some View {
        NavigationStack {
            let regular = regularChores
            let due = dueThisMonth
            let later = upcoming
            // Chores due this month count toward the ring; upcoming ones don't.
            let counted = regular + due
            let doneCount = counted.filter { $0.isDone(asOf: now) }.count
            let isEmpty = regular.isEmpty && longCycleChores.isEmpty

            List {
                Section {
                    ProgressHeaderView(
                        frequency: frequency,
                        doneCount: doneCount,
                        totalCount: counted.count,
                        now: now
                    )
                }

                if !regular.isEmpty {
                    Section {
                        choreRows(regular, canReorder: true)
                    } header: {
                        Text("Chores")
                    }
                }

                if !due.isEmpty {
                    Section {
                        choreRows(due)
                    } header: {
                        Text("Due This Month")
                    }
                }

                if !later.isEmpty {
                    Section {
                        if isUpcomingExpanded {
                            choreRows(later)
                        }
                    } header: {
                        upcomingHeader(count: later.count)
                    }
                }
            }
            .overlay {
                if isEmpty {
                    emptyState
                }
            }
            // Rows measure their check circle in this space, and the
            // confetti overlay below shares the same frame, so the two line up.
            .coordinateSpace(.named(Self.confettiSpace))
            .overlay {
                // The list runs under the navigation and tab bars, and the
                // rows report positions relative to its full frame. Ignoring
                // the safe area makes the canvas match that frame exactly so
                // pops land on the check circle and the shower starts
                // above the visible screen.
                ConfettiOverlay(bursts: bursts, accent: settings.accentTheme.color)
                    .ignoresSafeArea()
            }
            // `safeAreaInset` floats the banner above the tab bar and lets
            // the list scroll its last rows clear of it.
            .safeAreaInset(edge: .bottom) {
                if let pendingUndo {
                    UndoBanner(message: pendingUndo.message,
                               onUndo: undoDelete,
                               onDismiss: { withAnimation(.snappy) { self.pendingUndo = nil } })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // Restarts whenever a new delete happens; `id` changing cancels
            // the previous countdown.
            .task(id: pendingUndo?.id) {
                guard pendingUndo != nil, !voiceOverEnabled else { return }
                do {
                    try await Task.sleep(for: Self.undoTimeout)
                } catch {
                    return // Cancelled by a newer delete or an undo.
                }
                withAnimation(.snappy) { pendingUndo = nil }
            }
            .sensoryFeedback(trigger: celebrationCount) { _, _ in
                lastCelebrationWasBig ? .success : .impact(weight: .light)
            }
            .animation(.snappy, value: chores.count)
            .animation(.snappy, value: due.map(\.persistentModelID))
            .animation(.snappy, value: isUpcomingExpanded)
            .navigationTitle(title)
            .toolbar {
                // Edit mode shows drag handles, which is easier than press-
                // and-drag for some people and works well with VoiceOver.
                // (Edit mode doesn't exist on the Mac, where rows drag directly.)
                #if !os(macOS)
                if regular.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                }
                #endif
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Chore", systemImage: "plus") {
                        isAddingChore = true
                    }
                }
            }
            // Sheets are presented when their binding becomes true / non-nil
            // and dismissed when it goes back to false / nil.
            .sheet(isPresented: $isAddingChore) {
                // New chores default to the frequency of the current tab.
                ChoreEditorSheet(defaultFrequency: frequency)
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

    /// The rows for one section, with swipe-to-delete and, where the order
    /// is the person's to choose, drag-to-reorder.
    ///
    /// Long-cycle sections are always sorted by due date, so they pass
    /// `canReorder: false`.
    @ViewBuilder
    private func choreRows(_ sectionChores: [Chore], canReorder: Bool = false) -> some View {
        ForEach(sectionChores) { chore in
            ChoreRowView(
                chore: chore,
                isDone: chore.isDone(asOf: now),
                detail: detail(for: chore),
                isOverdue: chore.isOverdue(asOf: now),
                onToggle: { checkCenter in toggle(chore, at: checkCenter) },
                onEdit: { choreBeingEdited = chore }
            )
        }
        // `.onDelete` adds the standard swipe-left-to-delete gesture.
        .onDelete { offsets in
            delete(offsets.map { sectionChores[$0] })
        }
        // `.onMove` lets rows be dragged (press and hold, then drag, or use
        // the handles in Edit mode). Passing `nil` turns it off.
        .onMove(perform: canReorder ? { source, destination in
            Chore.reorder(sectionChores, fromOffsets: source, toOffset: destination)
        } : nil)
    }

    /// Deletes chores (and their history), keeping a copy so the Undo
    /// banner can put them back.
    private func delete(_ removed: [Chore]) {
        guard !removed.isEmpty else { return }
        let undo = PendingUndo(chores: removed.map(DeletedChore.init))
        withAnimation(.snappy) {
            pendingUndo = undo
        }
        for chore in removed {
            modelContext.delete(chore)
        }
        refreshReminders()
        // The banner appearing isn't announced on its own.
        AccessibilityNotification.Announcement("\(undo.message). Undo available.").post()
    }

    private func undoDelete() {
        guard let pendingUndo else { return }
        withAnimation(.snappy) {
            for deleted in pendingUndo.chores {
                deleted.restore(into: modelContext)
            }
            self.pendingUndo = nil
        }
        refreshReminders()
    }

    /// Re-schedules due-date reminders after anything that could move one.
    private func refreshReminders() {
        Task {
            await ChoreReminders.sync(in: modelContext, enabled: settings.remindersEnabled)
        }
    }

    /// A tappable section header that expands or collapses the upcoming list.
    private func upcomingHeader(count: Int) -> some View {
        Button {
            isUpcomingExpanded.toggle()
        } label: {
            HStack {
                Text("Upcoming")
                Text("\(count)")
                    .foregroundStyle(.tertiary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(isUpcomingExpanded ? 90 : 0))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Upcoming, \(count) chores")
        .accessibilityHint(isUpcomingExpanded ? "Collapses the list" : "Expands the list")
        .accessibilityAddTraits(.isHeader)
    }

    /// The subtitle under a long-cycle chore's name. Regular weekly and
    /// monthly chores have none.
    private func detail(for chore: Chore) -> String? {
        guard !chore.frequency.isCalendarAligned,
              let dueDate = chore.dueDate(asOf: now) else { return nil }

        if chore.isDone(asOf: now), let lastDone = chore.lastCompletion(asOf: now),
           chore.isDue(inMonthContaining: now) {
            return "Done \(lastDone.formatted(.dateTime.month(.abbreviated).day()))"
        }
        if chore.isOverdue(asOf: now) {
            return "Overdue · was due \(dueDate.formatted(.dateTime.month(.abbreviated).day()))"
        }
        let sameYear = Calendar.mondayFirst.isDate(dueDate, equalTo: now, toGranularity: .year)
        let format: Date.FormatStyle = sameYear
            ? .dateTime.month(.abbreviated).day()
            : .dateTime.month(.abbreviated).day().year()
        return "Due \(dueDate.formatted(format))"
    }

    /// Shown in place of the list when this tab has no chores yet.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No \(frequency.title) Chores", systemImage: "checklist")
        } description: {
            Text("Chores you add here reset at the start of every \(frequency == .weekly ? "week" : "month").")
        } actions: {
            Button("Add Chore", systemImage: "plus") {
                isAddingChore = true
            }
            .buttonStyle(.borderedProminent)
        }
        // Push the message below the progress card at the top of the list.
        .padding(.top, 80)
    }

    private func toggle(_ chore: Chore, at checkCenter: CGPoint) {
        // Use the real current time, in case "now" went stale while the app
        // sat open across midnight.
        now = .now
        let wasDone = chore.isDone(asOf: now)
        withAnimation(.snappy) {
            chore.toggleCompletion(on: now, in: modelContext)
        }
        // Checking a long-cycle chore pushes its due date out; unchecking
        // pulls it back. Either way the reminder needs to move.
        if !chore.frequency.isCalendarAligned {
            refreshReminders()
        }

        // Unchecking a chore is not a celebration.
        guard !wasDone else { return }

        // The relationship was updated synchronously above, so this already
        // reflects the chore that was just checked off. Only chores in this
        // period's checklist count, matching the progress ring.
        let counted = regularChores + dueThisMonth
        let isEverythingDone = counted.allSatisfy { $0.isDone(asOf: now) }
        celebrate(at: checkCenter, isEverythingDone: isEverythingDone)
    }

    /// A small pop for one chore; a pop plus a full-screen shower and a
    /// success haptic when the whole week or month is finished.
    private func celebrate(at checkCenter: CGPoint, isEverythingDone: Bool) {
        lastCelebrationWasBig = isEverythingDone
        celebrationCount += 1

        guard settings.celebrationsEnabled, !reduceMotion else { return }

        var newBursts = [ConfettiBurst(kind: .pop(at: checkCenter))]
        if isEverythingDone {
            newBursts.append(ConfettiBurst(kind: .shower))
        }
        bursts.append(contentsOf: newBursts)

        // Drop each burst once it has finished so the overlay can go idle.
        for burst in newBursts {
            Task {
                try? await Task.sleep(for: .seconds(burst.duration))
                bursts.removeAll { $0.id == burst.id }
            }
        }
    }
}

/// What the Undo banner can bring back.
private struct PendingUndo: Identifiable {
    let id = UUID()
    let chores: [DeletedChore]

    var message: String {
        if chores.count == 1, let chore = chores.first {
            return "Deleted “\(chore.name)”"
        }
        return "Deleted \(chores.count) chores"
    }
}

#Preview("Weekly", traits: .sampleData) {
    ChoreListView(frequency: .weekly)
}

#Preview("Monthly", traits: .sampleData) {
    ChoreListView(frequency: .monthly)
}
