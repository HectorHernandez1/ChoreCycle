import AppIntents
import SwiftData

// App Intents describe actions and data to the rest of the system: Siri,
// the Shortcuts app, Spotlight, and the Action button. Everything here runs
// inside the app's own process (no extension), so it reads and writes the
// same SwiftData database as the UI.
//
// The project makes code `@MainActor` by default. The system creates and
// inspects these types from other threads, so they're marked `nonisolated`
// and only hop to the main actor inside `perform()` / the query methods,
// where they touch the database through `container.mainContext`.

// MARK: - Chore entity

/// How Siri and Shortcuts see a chore: a lightweight, sendable copy of the
/// few values they need, identified by the chore's permanent `choreID`.
nonisolated struct ChoreEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Chore"
    static let defaultQuery = ChoreQuery()

    /// Saved shortcuts store this, so it must never change for a chore.
    let id: UUID

    @Property(title: "Name")
    var name: String

    @Property(title: "Repeats")
    var repeats: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(repeats)")
    }

    init(id: UUID, name: String, repeats: String) {
        self.id = id
        self.name = name
        self.repeats = repeats
    }

    /// `nil` for a chore that hasn't been given a `choreID` yet.
    @MainActor
    init?(_ chore: Chore) {
        guard let id = chore.choreID else { return nil }
        self.init(id: id, name: chore.name, repeats: chore.frequency.title)
    }
}

/// Finds chores for Siri and Shortcuts: by ID (to replay a saved shortcut),
/// by name (when someone types or says one), and as a suggestion list.
nonisolated struct ChoreQuery: EntityStringQuery {
    @Dependency private var container: ModelContainer

    @MainActor
    func entities(for identifiers: [ChoreEntity.ID]) async throws -> [ChoreEntity] {
        try Self.entities(for: identifiers, in: container.mainContext)
    }

    @MainActor
    func entities(matching string: String) async throws -> [ChoreEntity] {
        try Self.entities(matching: string, in: container.mainContext)
    }

    @MainActor
    func suggestedEntities() async throws -> [ChoreEntity] {
        try Self.allChores(in: container.mainContext).compactMap(ChoreEntity.init)
    }

    // The work lives in static functions that take a context, because the
    // system only fills in `@Dependency` when *it* runs the query. Tests
    // call these directly with the test database.

    @MainActor
    static func entities(for identifiers: [ChoreEntity.ID], in context: ModelContext) throws -> [ChoreEntity] {
        let wanted = Set(identifiers)
        return try allChores(in: context)
            .filter { $0.choreID.map(wanted.contains) ?? false }
            .compactMap(ChoreEntity.init)
    }

    @MainActor
    static func entities(matching string: String, in context: ModelContext) throws -> [ChoreEntity] {
        try allChores(in: context)
            .filter { $0.name.localizedStandardContains(string) }
            .compactMap(ChoreEntity.init)
    }

    /// Chores in the same order as the app's lists. There are only ever a
    /// handful, so one fetch and an in-memory filter is plenty.
    @MainActor
    static func allChores(in context: ModelContext) throws -> [Chore] {
        try context.fetch(FetchDescriptor<Chore>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))
    }
}

// MARK: - Errors

nonisolated enum ChoreIntentError: Error, CustomLocalizedStringResourceConvertible {
    case choreNotFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .choreNotFound: "That chore doesn't exist anymore."
        }
    }
}

// MARK: - Mark a chore done

/// "Mark Vacuum done in ChoreCycle."
///
/// Unlike tapping the check circle, this never *un*checks a chore. Siri
/// may also run an intent more than once, so doing it twice has to be
/// harmless.
nonisolated struct CompleteChoreIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Chore Done"
    static let description = IntentDescription(
        "Checks a chore off for the current week or month.",
        categoryName: "Chores"
    )

    @Parameter(title: "Chore")
    var chore: ChoreEntity

    @Dependency private var container: ModelContainer

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$chore) done")
    }

    init() {}

    init(chore: ChoreEntity) {
        self.chore = chore
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = container.mainContext
        let outcome = try Self.markDone(chore.id, in: context)
        let periodName = outcome.chore.frequency == .weekly ? "this week" : "this month"
        let name = outcome.chore.name

        guard outcome.didCheckOff else {
            return .result(dialog: "\(name) is already done \(periodName).")
        }
        // Checking off a long-cycle chore moves its due-date reminder.
        if !outcome.chore.frequency.isCalendarAligned {
            await ChoreReminders.sync(in: context, enabled: UserSettings().remindersEnabled)
        }
        return .result(dialog: "Nice work! \(name) is done \(periodName).")
    }

    /// Checks the chore off unless it's already done this period. Returns
    /// the chore and whether anything changed.
    @MainActor
    static func markDone(_ id: UUID, in context: ModelContext, on date: Date = .now) throws
        -> (chore: Chore, didCheckOff: Bool) {
        let matches = try context.fetch(FetchDescriptor<Chore>(predicate: #Predicate { $0.choreID == id }))
        guard let chore = matches.first else {
            throw ChoreIntentError.choreNotFound
        }
        guard !chore.isDone(asOf: date) else {
            return (chore, false)
        }
        chore.addCompletion(at: date)
        try context.save()
        return (chore, true)
    }
}

// MARK: - What's left

/// Which checklist "What's left" reads from.
///
/// Raw values are saved inside people's shortcuts: never rename them, only
/// add new cases.
nonisolated enum ChecklistKind: String, AppEnum {
    case thisWeek
    case thisMonth

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Checklist"
    static let caseDisplayRepresentations: [ChecklistKind: DisplayRepresentation] = [
        .thisWeek: "This Week",
        .thisMonth: "This Month",
    ]

    var frequency: Frequency {
        switch self {
        case .thisWeek: .weekly
        case .thisMonth: .monthly
        }
    }
}

/// "What's left in ChoreCycle?" Reads out the unchecked chores and hands
/// them to the next step of a shortcut.
nonisolated struct ChoresLeftIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Chores Left"
    static let description = IntentDescription(
        "Lists the chores you haven't checked off yet this week or this month.",
        categoryName: "Chores"
    )

    @Parameter(title: "Checklist", default: .thisWeek)
    var checklist: ChecklistKind

    @Dependency private var container: ModelContainer

    static var parameterSummary: some ParameterSummary {
        Summary("Get chores left for \(\.$checklist)")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[ChoreEntity]> & ProvidesDialog {
        let chores = try ChoreQuery.allChores(in: container.mainContext)
        let left = Chore.checklist(for: checklist.frequency, from: chores).filter { !$0.isDone() }
        let periodName = checklist == .thisWeek ? "this week" : "this month"
        let entities = left.compactMap(ChoreEntity.init)

        guard !left.isEmpty else {
            return .result(value: entities, dialog: "You're all done \(periodName)!")
        }
        let names = left.map(\.name).formatted(.list(type: .and))
        let count = left.count == 1 ? "One chore" : "\(left.count) chores"
        return .result(value: entities, dialog: "\(count) left \(periodName): \(names).")
    }
}

// MARK: - Siri phrases

/// Ready-made shortcuts that work with Siri and show up in Spotlight and
/// the Shortcuts app without any setup. Every phrase must include the
/// app's name.
///
/// Phrases are what people say out loud: renaming or removing one breaks
/// their habit, so prefer adding new ones.
nonisolated struct ChoreCycleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CompleteChoreIntent(),
            phrases: [
                "Mark \(\.$chore) done in \(.applicationName)",
                "Check off \(\.$chore) in \(.applicationName)",
                "I did \(\.$chore) in \(.applicationName)",
            ],
            shortTitle: "Mark Chore Done",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: ChoresLeftIntent(),
            phrases: [
                "What's left in \(.applicationName)",
                "What chores are left in \(.applicationName)",
                "What's left this week in \(.applicationName)",
            ],
            shortTitle: "Chores Left",
            systemImageName: "checklist"
        )
    }
}
