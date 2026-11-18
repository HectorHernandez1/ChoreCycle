import SwiftUI

/// The wide-screen Checklists tab: this week's and this month's lists side
/// by side, each with its own progress ring, toolbar, and confetti.
///
/// Each column is a full `ChoreListView`, so everything works the same as
/// on the separate tabs; there's just room to see both at once.
struct ChecklistsDashboard: View {
    var body: some View {
        HStack(spacing: 0) {
            ChoreListView(frequency: .weekly)
            Divider()
                .ignoresSafeArea()
            ChoreListView(frequency: .monthly)
        }
    }
}

#Preview(traits: .sampleData) {
    ChecklistsDashboard()
}
