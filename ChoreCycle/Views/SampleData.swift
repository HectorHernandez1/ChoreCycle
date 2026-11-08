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
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        StarterChores.insert(into: container.mainContext)

        // Check off a couple of chores so previews show both row states.
        let chores = try container.mainContext.fetch(FetchDescriptor<Chore>(sortBy: [SortDescriptor(\.sortOrder)]))
        for chore in chores.prefix(2) {
            chore.toggleCompletion(in: container.mainContext)
        }
        return container
    }

    func body(content: Content, context: ModelContainer) -> some View {
        content.modelContainer(context)
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var sampleData: Self { .modifier(SampleData()) }
}
