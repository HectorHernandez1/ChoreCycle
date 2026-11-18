import SwiftUI
import SwiftData
import AppIntents

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
    /// The app-wide editor from `MainTabView`, which shows it as a side
    /// panel on wide screens. `nil` when this list is shown on its own (as
    /// in its previews), in which case the list uses its own sheets below.
    @Environment(ChoreEditorPresenter.self) private var editor: ChoreEditorPresenter?
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

    /// Rolling chores that live on this tab: every 2 weeks on the Weekly
    /// tab; every 3 months, 6 months, and yearly on the Monthly tab.
    private var longCycleChores: [Chore] {
        chores.filter {
            !$0.frequency.isCalendarAligned && $0.frequency.calendarComponent == frequency.calendarComponent
        }
    }

    /// Rolling chores that belong in this week's or month's checklist,
    /// soonest first.
    private var dueThisPeriod: [Chore] {
        longCycleChores
            .filter { $0.isDue(inPeriodContaining: now) }
            .sorted { ($0.dueDate(asOf: now) ?? now) < ($1.dueDate(asOf: now) ?? now) }
    }

    /// Rolling chores not due until a later week or month, soonest first.
    private var upcoming: [Chore] {
        longCycleChores
            .filter { !$0.isDue(inPeriodContaining: now) }
            .sorted { ($0.dueDate(asOf: now) ?? now) < ($1.dueDate(asOf: now) ?? now) }
    }

    var body: some View {
        NavigationStack {
            let regular = regularChores
            let due = dueThisPeriod
            let later = upcoming
            // Chores due this period count toward the ring; upcoming and
            // skipped ones don't.
            let counted = (regular + due).filter { !$0.isSkipped(asOf: now) }
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

                if showsSiriTip {
                    Section {
                        siriTip
                    }
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
                        Text(frequency == .weekly ? "Due This Week" : "Due This Month")
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
                        startAdding()
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
            let skipAction = skipAction(for: chore)
            ChoreRowView(
                chore: chore,
                isDone: chore.isDone(asOf: now),
                isSkipped: chore.isSkipped(asOf: now),
                detail: detail(for: chore),
                isOverdue: chore.isOverdue(asOf: now),
                onToggle: { checkCenter in toggle(chore, at: checkCenter) },
                onEdit: { startEditing(chore) },
                skipAction: skipAction
            )
            // Swipe right to skip. Custom swipe actions replace the ones
            // `.onDelete` would add, so Delete is spelled out on the other
            // side (`.onDelete` below still powers Edit mode).
            .swipeActions(edge: .leading) {
                if let skipAction {
                    Button(skipAction.title, systemImage: "forward.end", action: skipAction.perform)
                        .tint(.indigo)
                }
            }
            .swipeActions(edge: .trailing) {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    delete([chore])
                }
            }
        }
        // `.onDelete` adds the delete buttons in Edit mode.
        .onDelete { offsets in
            delete(offsets.map { sectionChores[$0] })
        }
        // `.onMove` lets rows be dragged (press and hold, then drag, or use
        // the handles in Edit mode). Passing `nil` turns it off.
        .onMove(perform: canReorder ? { source, destination in
            Chore.reorder(sectionChores, fromOffsets: source, toOffset: destination)
        } : nil)
    }

    /// The Siri tip appears once, on the Weekly tab, and only when there are
    /// chores for "What's left" to talk about.
    private var showsSiriTip: Bool {
        #if os(iOS)
        frequency == .weekly && settings.showsSiriTip && !chores.isEmpty
        #else
        false
        #endif
    }

    /// "Try saying 'What's left in ChoreCycle'", with a close button that
    /// turns the tip off for good (Profile can bring it back).
    @ViewBuilder
    private var siriTip: some View {
        #if os(iOS)
        @Bindable var settings = settings
        SiriTipView(intent: ChoresLeftIntent(), isVisible: $settings.showsSiriTip)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        #endif
    }

    /// New chores default to the frequency of this list.
    private func startAdding() {
        if let editor {
            editor.add(frequency)
        } else {
            isAddingChore = true
        }
    }

    private func startEditing(_ chore: Chore) {
        if let editor {
            editor.edit(chore)
        } else {
            choreBeingEdited = chore
        }
    }

    /// Deletes chores (and their history), keeping a copy so the Undo
    /// banner can put them back.
    private func delete(_ removed: [Chore]) {
        guard !removed.isEmpty else { return }
        // The side panel leaves the list usable, so the chore being edited
        // could be the one going away.
        editor?.close(ifEditingAnyOf: removed)
        let undo = PendingUndo(chores: removed.map { DeletedChore($0) })
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
                    .foregroundStyle(.secondary)
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

    /// "Skip This Week" (or "Skip This Month" / "Skip This Time" for chores
    /// that roll over) when the chore is still open, "Don't Skip" once it's
    /// skipped, and nothing once it's done.
    private func skipAction(for chore: Chore) -> (title: String, perform: () -> Void)? {
        if chore.isSkipped(asOf: now) {
            return ("Don't Skip", { toggleSkip(chore) })
        }
        guard !chore.isDone(asOf: now) else { return nil }
        let title = switch chore.frequency {
        case .weekly: "Skip This Week"
        case .monthly: "Skip This Month"
        case .everyTwoWeeks, .everyThreeMonths, .everySixMonths, .yearly: "Skip This Time"
        }
        return (title, { toggleSkip(chore) })
    }

    private func toggleSkip(_ chore: Chore) {
        now = .now
        withAnimation(.snappy) {
            if chore.isSkipped(asOf: now) {
                chore.toggleCompletion(on: now, in: modelContext) // clears the skip
            } else {
                chore.skip(on: now, in: modelContext)
            }
        }
        // A skip moves a long-cycle chore's due date and settles a pinned
        // weekly chore for the week, so its reminder needs to move.
        if chore.hasReminder {
            refreshReminders()
        }
    }

    /// The subtitle under a chore's name: the due date for rolling chores
    /// and weekly chores pinned to a day, or "Skipped this week". Other
    /// chores have none.
    private func detail(for chore: Chore) -> String? {
        if chore.isSkipped(asOf: now) {
            let periodName = chore.frequency.calendarComponent == .weekOfYear ? "week" : "month"
            return "Skipped this \(periodName)"
        }
        guard let dueDate = chore.dueDate(asOf: now) else { return nil }
        let calendar = Calendar.mondayFirst

        // Weekly chores pinned to a day: "Due Tuesday", "Due today".
        if chore.frequency.isCalendarAligned {
            let weekday = dueDate.formatted(.dateTime.weekday(.wide))
            if chore.isDone(asOf: now) {
                return "Every \(weekday)"
            }
            if chore.isOverdue(asOf: now) {
                return "Overdue · was due \(weekday)"
            }
            return calendar.isDate(dueDate, inSameDayAs: now) ? "Due today" : "Due \(weekday)"
        }

        if chore.isDone(asOf: now), let lastDone = chore.lastDone(asOf: now),
           chore.isDue(inPeriodContaining: now) {
            return "Done \(lastDone.formatted(.dateTime.month(.abbreviated).day()))"
        }
        if chore.isOverdue(asOf: now) {
            return "Overdue · was due \(dueDate.formatted(.dateTime.month(.abbreviated).day()))"
        }
        // Every-2-weeks chores are close enough that the weekday helps.
        var format: Date.FormatStyle = .dateTime.month(.abbreviated).day()
        if chore.frequency == .everyTwoWeeks {
            format = format.weekday(.abbreviated)
        }
        if !calendar.isDate(dueDate, equalTo: now, toGranularity: .year) {
            format = format.year()
        }
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
                startAdding()
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
        // Tapping a skipped chore un-skips it rather than checking it off,
        // so either way there's nothing to celebrate.
        let wasDone = chore.isHandled(asOf: now)
        withAnimation(.snappy) {
            chore.toggleCompletion(on: now, in: modelContext)
        }
        // Checking a chore with a due date pushes its reminder out;
        // unchecking pulls it back. Either way the reminder needs to move.
        if chore.hasReminder {
            refreshReminders()
        }

        // Unchecking a chore is not a celebration.
        guard !wasDone else { return }

        // Tell the system this happened, so Siri and Spotlight can start
        // suggesting "Mark Vacuum done" around the times it usually happens.
        if let entity = ChoreEntity(chore) {
            Task {
                _ = try? await CompleteChoreIntent(chore: entity).donate()
            }
        }

        // The relationship was updated synchronously above, so this already
        // reflects the chore that was just checked off. Only chores in this
        // period's checklist count, matching the progress ring.
        let counted = (regularChores + dueThisPeriod).filter { !$0.isSkipped(asOf: now) }
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
