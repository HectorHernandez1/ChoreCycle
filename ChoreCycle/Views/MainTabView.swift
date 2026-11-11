import SwiftUI
import SwiftData

/// The app's root screen: a tab bar with weekly chores, monthly chores,
/// history, and the person's profile.
struct MainTabView: View {
    @Environment(UserSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            Tab("Weekly", systemImage: "calendar.day.timeline.left") {
                ChoreListView(frequency: .weekly)
            }
            Tab("Monthly", systemImage: "calendar") {
                ChoreListView(frequency: .monthly)
            }
            Tab("History", systemImage: "clock.arrow.circlepath") {
                HistoryView()
            }
            Tab("Profile", systemImage: "person.crop.circle") {
                ProfileView()
            }
        }
        // The chosen accent drives check circles, the progress ring, and
        // buttons everywhere below this point.
        .tint(settings.accentTheme.color)
        .preferredColorScheme(settings.appearance.colorScheme)
        // Re-schedule due-date reminders whenever the app comes to the
        // front, so they stay right even if a due date passed while the app
        // was closed or the person changed notification permission.
        .task {
            await ChoreReminders.sync(in: modelContext, enabled: settings.remindersEnabled)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await ChoreReminders.sync(in: modelContext, enabled: settings.remindersEnabled)
            }
        }
    }
}

#Preview(traits: .sampleData) {
    MainTabView()
}
