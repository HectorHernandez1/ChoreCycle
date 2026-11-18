import SwiftUI
import SwiftData
import AppIntents

/// A form for adding a new chore, or editing an existing one. Shown as a
/// sheet, or as a side panel (inspector) on wide screens.
struct ChoreEditorSheet: View {
    /// The chore being edited, or `nil` when adding a new one.
    let chore: Chore?

    /// How to close the editor when it isn't a plain sheet (the side panel
    /// is closed by clearing `ChoreEditorPresenter.request`). `nil` means
    /// use `dismiss`.
    var onDone: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(UserSettings.self) private var settings

    /// `dismiss` is an action SwiftUI provides to close the current sheet.
    @Environment(\.dismiss) private var dismiss

    // Draft values. Edits only touch the real chore when Save is tapped, so
    // Cancel really cancels. These have no initial value here because they
    // are set in `init` below.
    @State private var name: String
    @State private var frequency: Frequency
    @State private var nextDueDate: Date
    /// `nil` means "any day".
    @State private var dueWeekday: Int?
    @State private var notes: String

    /// Drives keyboard focus so the name field is ready to type into as
    /// soon as the sheet appears.
    @FocusState private var isNameFocused: Bool

    /// `defaultFrequency` picks the starting frequency for a new chore. It's
    /// ignored when editing, since an existing chore already has one.
    init(chore: Chore? = nil, defaultFrequency: Frequency = .weekly, onDone: (() -> Void)? = nil) {
        self.chore = chore
        self.onDone = onDone
        self.name = chore?.name ?? ""
        self.frequency = chore?.frequency ?? defaultFrequency
        self.nextDueDate = chore?.nextDueDate ?? .now
        self.dueWeekday = chore?.dueWeekday
        self.notes = chore?.notes ?? ""
    }

    /// The weekday to save: only weekly and every-2-weeks chores keep one.
    private var effectiveWeekday: Int? {
        frequency.supportsWeekday ? dueWeekday : nil
    }

    /// "Tuesday" for the footer, or `nil` for "any day".
    private var weekdayName: String? {
        effectiveWeekday.map { Calendar.mondayFirst.weekdaySymbols[$0 - 1] }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNotes: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The "Next due" picker only matters for rolling chores that have never
    /// been checked off. Once there's a completion, the due date comes from
    /// it instead.
    private var showsNextDueDate: Bool {
        !frequency.isCalendarAligned && (chore?.allCompletions.isEmpty ?? true)
    }

    private var frequencyFooter: String {
        let base = switch frequency {
        case .weekly:
            "Resets every Monday."
        case .monthly:
            "Resets on the first of each month."
        case .everyTwoWeeks, .everyThreeMonths, .everySixMonths, .yearly:
            if let lastDone = chore?.lastDone() {
                "Last done \(lastDone.formatted(date: .abbreviated, time: .omitted)). "
                + "Due again \(intervalDescription) after each time you check it off."
            } else {
                "Shows up in the \(frequency == .everyTwoWeeks ? "Weekly" : "Monthly") tab when it's due, "
                + "and again \(intervalDescription) after each time you check it off."
            }
        }
        guard let weekdayName else { return base }
        return base + " Due on \(weekdayName)s, with a reminder that morning."
    }

    /// "2 weeks", "3 months", "6 months", or "a year", for the footer text.
    private var intervalDescription: String {
        if frequency == .everyTwoWeeks {
            return "2 weeks"
        }
        return switch frequency.monthInterval {
        case 12: "a year"
        case let months?: "\(months) months"
        case nil: ""
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // The title ("Name") is what VoiceOver announces; the
                    // prompt is the gray example text shown while empty.
                    TextField("Name", text: $name, prompt: Text("e.g. Vacuum the living room"))
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            if !trimmedName.isEmpty { save() }
                        }
                } header: {
                    Text("Name")
                }

                Section {
                    Picker("Repeats", selection: $frequency) {
                        ForEach(Frequency.allCases) { frequency in
                            Text(frequency.title).tag(frequency)
                        }
                    }
                    .pickerStyle(.menu)

                    if frequency.supportsWeekday {
                        Picker("Day", selection: $dueWeekday) {
                            Text("Any Day").tag(Int?.none)
                            ForEach(Calendar.mondayFirst.orderedWeekdays, id: \.self) { weekday in
                                Text(Calendar.mondayFirst.weekdaySymbols[weekday - 1])
                                    .tag(Int?.some(weekday))
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    if showsNextDueDate {
                        DatePicker("Next due", selection: $nextDueDate, displayedComponents: .date)
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    Text(frequencyFooter)
                }
                .animation(.snappy, value: showsNextDueDate)
                .animation(.snappy, value: frequency.supportsWeekday)

                Section {
                    // `axis: .vertical` lets the field grow onto more lines
                    // as you type, like a small text area.
                    TextField("Notes", text: $notes, prompt: Text("e.g. Filter size 16×25×1"), axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("Notes")
                }
            }
            .navigationTitle(chore == nil ? "New Chore" : "Edit Chore")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        close()
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            // Only auto-focus for new chores; when editing, the name is
            // already filled in and a jumping keyboard is disruptive.
            if chore == nil {
                isNameFocused = true
            }
        }
    }

    private func close() {
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }

    private func save() {
        // In the side panel the list stays usable, so the chore may have
        // been deleted (here or on another device) while it was open.
        if let chore, chore.isDeleted || chore.modelContext == nil {
            close()
            return
        }

        // Weekly and monthly chores never have a due date. Rolling chores
        // only need one until their first completion.
        let dueDate: Date? = showsNextDueDate ? Calendar.mondayFirst.startOfDay(for: nextDueDate) : nil
        // Read before editing: if the chore *used* to have a reminder, the
        // old one needs clearing even if it no longer has one.
        let hadReminder = chore?.hasReminder ?? false

        let saved: Chore
        if let chore {
            // A chore moved to another section goes to the bottom of it.
            if chore.frequency != frequency {
                chore.sortOrder = nextSortOrder()
            }
            chore.name = trimmedName
            chore.frequency = frequency
            chore.nextDueDate = dueDate
            chore.dueWeekday = effectiveWeekday
            chore.notes = trimmedNotes
            saved = chore
        } else {
            // Put new chores at the bottom of the list.
            saved = Chore(
                name: trimmedName,
                frequency: frequency,
                sortOrder: nextSortOrder(),
                nextDueDate: dueDate,
                dueWeekday: effectiveWeekday,
                notes: trimmedNotes
            )
            modelContext.insert(saved)
        }

        // Saving a chore with a due date is the natural moment to ask for
        // notification permission, since it's the first time a reminder
        // would be useful. `sync` asks only if the person hasn't been asked.
        if saved.hasReminder || hadReminder {
            let context = modelContext
            let enabled = settings.remindersEnabled
            Task {
                await ChoreReminders.sync(in: context, enabled: enabled)
            }
        }
        // Teach Siri the new or changed name for "Mark … done".
        ChoreCycleShortcuts.updateAppShortcutParameters()
        close()
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

#Preview("Six months", traits: .sampleData) {
    ChoreEditorSheet(defaultFrequency: .everySixMonths)
}
