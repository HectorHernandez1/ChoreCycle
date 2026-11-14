import SwiftUI
import SwiftData

/// The Profile tab: the person's name plus the look-and-feel settings.
/// Everything here is saved automatically through `UserSettings`.
struct ProfileView: View {
    @Environment(UserSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    /// True when the person has turned notifications off for the app in
    /// the system Settings, so the toggle here can't do anything.
    @State private var isNotificationAccessDenied = false

    var body: some View {
        // `@Bindable` lets us hand `$settings.someProperty` bindings to
        // controls even though `settings` came from the environment.
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        AvatarView(initials: settings.initials)

                        VStack(alignment: .leading, spacing: 2) {
                            TextField("Your name", text: $settings.displayName)
                                .font(.title3.weight(.semibold))
                                .textContentType(.name)
                                .autocorrectionDisabled()
                            Text("Shown on this device only")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    AccentColorGrid(selection: $settings.accentTheme)
                } header: {
                    Text("Accent Color")
                } footer: {
                    Text("Used for check marks, the progress ring, buttons, and confetti.")
                }

                Section {
                    Picker("Appearance", selection: $settings.appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    Text("Appearance")
                }

                Section {
                    Toggle("Confetti", isOn: $settings.celebrationsEnabled)
                } header: {
                    Text("Celebrations")
                } footer: {
                    Text("A small burst when you finish a chore, and a big one when the whole week or month is done.")
                }

                Section {
                    Toggle("Due Date Reminders", isOn: $settings.remindersEnabled)
                } header: {
                    Text("Reminders")
                } footer: {
                    if isNotificationAccessDenied && settings.remindersEnabled {
                        Text("Notifications are turned off for ChoreCycle in Settings. Turn them on there to get reminders.")
                            .foregroundStyle(Color.warning)
                    } else {
                        Text("A notification at 9 AM on the day an every-2-weeks, 3-month, 6-month, or yearly chore is due, and on the chosen day for weekly chores set to a specific day.")
                    }
                }
            }
            .navigationTitle("Profile")
            .task {
                isNotificationAccessDenied = await ChoreReminders.isDenied()
            }
            // Permission may have changed in Settings while we were away.
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task { isNotificationAccessDenied = await ChoreReminders.isDenied() }
            }
            .onChange(of: settings.remindersEnabled) { _, enabled in
                Task {
                    // Turning it on asks for permission if needed; turning it
                    // off clears every pending reminder.
                    await ChoreReminders.sync(in: modelContext, enabled: enabled)
                    isNotificationAccessDenied = await ChoreReminders.isDenied()
                }
            }
        }
    }
}

/// A round badge with the person's initials, or a generic person symbol
/// when no name has been entered yet.
private struct AvatarView: View {
    let initials: String

    /// Grows with text size so the initials never outgrow the circle.
    @ScaledMetric(relativeTo: .title3) private var size: CGFloat = 56

    var body: some View {
        // White on a solid accent circle: every accent color is chosen to
        // give at least 3:1 under white (see `AccentTheme.color`). A pale
        // tint behind accent-colored text fell short for several themes.
        ZStack {
            Circle()
                .fill(.tint)
            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            } else {
                Text(initials)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
        }
        .frame(width: size, height: size)
        .animation(.snappy, value: initials)
        .accessibilityHidden(true)
    }
}

/// A grid of color swatches; the selected one shows a check mark and ring.
private struct AccentColorGrid: View {
    @Binding var selection: AccentTheme

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 14)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(AccentTheme.allCases) { theme in
                let isSelected = theme == selection
                Button {
                    withAnimation(.snappy) {
                        selection = theme
                    }
                } label: {
                    Circle()
                        .fill(theme.color)
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "checkmark")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .opacity(isSelected ? 1 : 0)
                                .scaleEffect(isSelected ? 1 : 0.4)
                        }
                        .overlay {
                            // Selection ring sits just outside the swatch.
                            Circle()
                                .strokeBorder(theme.color, lineWidth: 2.5)
                                .padding(-5)
                                .opacity(isSelected ? 1 : 0)
                        }
                        .padding(5)
                        // The button's own label and selected trait describe
                        // this swatch; hide the decorative check mark so
                        // VoiceOver doesn't announce it separately.
                        .accessibilityHidden(true)
                }
                // `.plain` keeps each swatch tappable on its own inside a
                // Form row instead of the whole row acting as one button.
                .buttonStyle(.plain)
                .accessibilityLabel(theme.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview(traits: .sampleData) {
    ProfileView()
}
