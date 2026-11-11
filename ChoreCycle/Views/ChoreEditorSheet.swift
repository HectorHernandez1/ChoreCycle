import SwiftUI
import SwiftData

/// A sheet for adding a new chore, or editing an existing one.
struct ChoreEditorSheet: View {
    /// The chore being edited, or `nil` when adding a new one.
    let chore: Chore?

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

    /// Drives keyboard focus so the name field is ready to type into as
    /// soon as the sheet appears.
    @FocusState private var isNameFocused: Bool

    /// `defaultFrequency` picks the starting frequency for a new chore. It's
    /// ignored when editing, since an existing chore already has one.
    init(chore: Chore? = nil, defaultFrequency: Frequency = .weekly) {
        self.chore = chore
        self.name = chore?.name ?? ""
        self.frequency = chore?.frequency ?? defaultFrequency
        self.nextDueDate = chore?.nextDueDate ?? .now
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The "Next due" picker only matters for rolling chores that have never
    /// been checked off. Once there's a completion, the due date comes from
    /// it instead.
    private var showsNextDueDate: Bool {
        !frequency.isCalendarAligned && (chore?.completions.isEmpty ?? true)
    }

    private var frequencyFooter: String {
        switch frequency {
        case .weekly:
            "Resets every Monday."
        case .monthly:
            "Resets on the first of each month."
        case .everyThreeMonths, .everySixMonths, .yearly:
            if let lastDone = chore?.lastCompletion() {
                "Last done \(lastDone.formatted(date: .abbreviated, time: .omitted)). "
                + "Due again \(intervalDescription) after each time you check it off."
            } else {
                "Shows up in the Monthly tab when it's due, and again "
                + "\(intervalDescription) after each time you check it off."
            }
        }
    }

    /// "3 months", "6 months", or "a year", for the footer text.
    private var intervalDescription: String {
        switch frequency.monthInterval {
        case 12: "a year"
        case let months?: "\(months) months"
        case nil: ""
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Vacuum the living room", text: $name)
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

                    if showsNextDueDate {
                        DatePicker("Next due", selection: $nextDueDate, displayedComponents: .date)
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    Text(frequencyFooter)
                }
                .animation(.snappy, value: showsNextDueDate)
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

    private func save() {
        // Weekly and monthly chores never have a due date. Rolling chores
        // only need one until their first completion.
        let dueDate: Date? = showsNextDueDate ? Calendar.mondayFirst.startOfDay(for: nextDueDate) : nil

        if let chore {
            // A chore moved to another section goes to the bottom of it.
            if chore.frequency != frequency {
                chore.sortOrder = nextSortOrder()
            }
            chore.name = trimmedName
            chore.frequency = frequency
            chore.nextDueDate = dueDate
        } else {
            // Put new chores at the bottom of the list.
            modelContext.insert(Chore(
                name: trimmedName,
                frequency: frequency,
                sortOrder: nextSortOrder(),
                nextDueDate: dueDate
            ))
        }

        // Saving a long-cycle chore is the natural moment to ask for
        // notification permission, since it's the first time a reminder
        // would be useful. `sync` asks only if the person hasn't been asked.
        if !frequency.isCalendarAligned || chore?.frequency.isCalendarAligned == false {
            let context = modelContext
            let enabled = settings.remindersEnabled
            Task {
                await ChoreReminders.sync(in: context, enabled: enabled)
            }
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

#Preview("Six months", traits: .sampleData) {
    ChoreEditorSheet(defaultFrequency: .everySixMonths)
}
