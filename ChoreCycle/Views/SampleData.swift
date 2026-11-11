import SwiftUI
import SwiftData

/// Supplies Xcode previews with a throwaway, in-memory database filled with
/// the starter chores, so previews never touch the app's real data.
///
/// A `PreviewModifier` builds the container once and shares it across every
/// preview that uses `#Preview(traits: .sampleData)`.
struct SampleData: PreviewModifier {
    static func makeSharedContext() async throws -> ModelContainer {
        let container = try ModelContainer(
            for: Chore.self, Completion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        StarterChores.insert(into: container.mainContext)

        // Check off a couple of chores so previews show both row states.
        let chores = try container.mainContext.fetch(FetchDescriptor<Chore>(sortBy: [SortDescriptor(\.sortOrder)]))
        for chore in chores.prefix(2) {
            chore.toggleCompletion(in: container.mainContext)
        }

        // A few long-cycle chores so the Monthly preview shows "Due this
        // month" (one due now, one overdue) and a collapsed "Upcoming" list.
        let calendar = Calendar.mondayFirst
        let context = container.mainContext
        let nextOrder = chores.count

        context.insert(Chore(name: "Check smoke detectors", frequency: .everySixMonths,
                             sortOrder: nextOrder, nextDueDate: .now))
        context.insert(Chore(name: "Clean gutters", frequency: .yearly, sortOrder: nextOrder + 1,
                             nextDueDate: calendar.date(byAdding: .month, value: -2, to: .now)))

        let filter = Chore(name: "Replace furnace filter", frequency: .everySixMonths, sortOrder: nextOrder + 2)
        context.insert(filter)
        if let fiveMonthsAgo = calendar.date(byAdding: .month, value: -5, to: .now) {
            filter.addCompletion(at: fiveMonthsAgo)
        }

        context.insert(Chore(name: "Flip mattress", frequency: .everyThreeMonths, sortOrder: nextOrder + 3,
                             nextDueDate: calendar.date(byAdding: .month, value: 2, to: .now)))
        return container
    }

    func body(content: Content, context: ModelContainer) -> some View {
        content
            .modelContainer(context)
            .environment(UserSettings.preview())
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var sampleData: Self { .modifier(SampleData()) }
}
