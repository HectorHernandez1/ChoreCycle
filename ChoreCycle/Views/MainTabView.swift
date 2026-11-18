import SwiftUI
import SwiftData
import AppIntents

/// The app's tabs. Weekly and Monthly are separate on narrow screens and
/// merge into Checklists on wide ones.
enum AppTab: Hashable {
    case weekly, monthly, checklists, history, profile
}

/// The app's root screen: a tab bar with weekly chores, monthly chores,
/// history, and the person's profile.
///
/// On a wide screen (the unfolded iPhone, iPad, a big Mac window) the
/// Weekly and Monthly tabs become a single Checklists tab that shows both
/// lists side by side. "Wide" means a regular horizontal size class, so the
/// layout follows the space the app actually has, not the kind of device,
/// and switches live when the phone is folded or unfolded.
struct MainTabView: View {
    @Environment(UserSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// The tab the person last picked, in narrow-screen terms (Weekly or
    /// Monthly, never Checklists), so folding returns to the right one.
    @State private var selection: AppTab = .weekly

    private var isWide: Bool {
        horizontalSizeClass == .regular
    }

    /// Translates `selection` to the tabs that exist at the current width:
    /// Weekly or Monthly show as Checklists when wide, and picking
    /// Checklists remembers Weekly for when the screen narrows again.
    private var visibleSelection: Binding<AppTab> {
        Binding {
            let isChecklist = selection == .weekly || selection == .monthly
            return isWide && isChecklist ? .checklists : selection
        } set: { newValue in
            if newValue == .checklists {
                if selection != .weekly && selection != .monthly {
                    selection = .weekly
                }
            } else {
                selection = newValue
            }
        }
    }

    var body: some View {
        TabView(selection: visibleSelection) {
            if isWide {
                Tab("Checklists", systemImage: "checklist", value: AppTab.checklists) {
                    ChecklistsDashboard()
                }
            } else {
                Tab("Weekly", systemImage: "calendar.day.timeline.left", value: AppTab.weekly) {
                    ChoreListView(frequency: .weekly)
                }
                Tab("Monthly", systemImage: "calendar", value: AppTab.monthly) {
                    ChoreListView(frequency: .monthly)
                }
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                HistoryView()
            }
            Tab("Profile", systemImage: "person.crop.circle", value: AppTab.profile) {
                ProfileView()
            }
        }
        // A tab bar on narrow screens; on wide ones (iPad, the unfolded
        // iPhone, a Mac window) the tabs can become a sidebar. SwiftUI
        // switches between the two as the window changes size.
        .tabViewStyle(.sidebarAdaptable)
        // The chosen accent drives check circles, the progress ring, and
        // buttons everywhere below this point.
        .tint(settings.accentTheme.color)
        .preferredColorScheme(settings.appearance.colorScheme)
        // Re-schedule due-date reminders whenever the app comes to the
        // front, so they stay right even if a due date passed while the app
        // was closed or the person changed notification permission.
        //
        // Same moment for refreshing the chore names Siri listens for in
        // phrases like "Mark Vacuum done", since chores may have been added
        // or renamed (here or on another device).
        .task {
            await ChoreReminders.sync(in: modelContext, enabled: settings.remindersEnabled)
            ChoreCycleShortcuts.updateAppShortcutParameters()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await ChoreReminders.sync(in: modelContext, enabled: settings.remindersEnabled)
                ChoreCycleShortcuts.updateAppShortcutParameters()
            }
        }
    }
}

#Preview(traits: .sampleData) {
    MainTabView()
}
