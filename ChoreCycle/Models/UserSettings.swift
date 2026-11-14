import SwiftUI

/// The accent colors a person can pick for the app.
///
/// The `String` raw values are what get saved, so don't rename them later.
nonisolated enum AccentTheme: String, CaseIterable, Identifiable {
    case teal, blue, indigo, purple, pink, red, orange, yellow, green, mint, brown, graphite

    var id: Self { self }

    var title: String {
        switch self {
        case .teal: "Teal"
        case .blue: "Blue"
        case .indigo: "Indigo"
        case .purple: "Purple"
        case .pink: "Pink"
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .mint: "Mint"
        case .brown: "Brown"
        case .graphite: "Graphite"
        }
    }

    /// The accent fills check circles (under a white check mark), tints the
    /// progress ring and buttons, and colors bold text such as streak counts.
    /// Each of those needs at least 3:1 contrast (WCAG) against white, the
    /// dark backgrounds, and the white check mark. The system teal, yellow,
    /// orange, green, and mint are too light for that (1.5–2.6:1), so those
    /// themes use deeper shades of the same hue. The rest are system colors.
    var color: Color {
        switch self {
        case .teal: Color(red: 0.055, green: 0.486, blue: 0.549)
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: Color(red: 0.702, green: 0.349, blue: 0.0)
        case .yellow: Color(red: 0.639, green: 0.478, blue: 0.0)
        case .green: Color(red: 0.141, green: 0.541, blue: 0.239)
        case .mint: Color(red: 0.047, green: 0.506, blue: 0.482)
        case .brown: .brown
        case .graphite: .gray
        }
    }
}

/// Whether the app follows the system appearance or forces light or dark.
nonisolated enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` means "don't override", which lets the system decide.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The person's profile and preferences, saved on this device.
///
/// `@Observable` makes SwiftUI redraw any view that reads a property when it
/// changes. Each property writes straight through to `UserDefaults`, so the
/// settings survive relaunches without a separate "save" step. Everything
/// goes through this one object, which keeps the door open to syncing it
/// with iCloud or a signed-in account later.
@Observable
final class UserSettings {
    private enum Key {
        static let displayName = "displayName"
        static let accentTheme = "accentTheme"
        static let appearance = "appearance"
        static let celebrationsEnabled = "celebrationsEnabled"
        static let remindersEnabled = "remindersEnabled"
        static let showsSiriTip = "showsSiriTip"
    }

    var displayName: String {
        didSet { defaults.set(displayName, forKey: Key.displayName) }
    }

    var accentTheme: AccentTheme {
        didSet { defaults.set(accentTheme.rawValue, forKey: Key.accentTheme) }
    }

    var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    var celebrationsEnabled: Bool {
        didSet { defaults.set(celebrationsEnabled, forKey: Key.celebrationsEnabled) }
    }

    /// Whether long-cycle chores get a notification on their due date.
    var remindersEnabled: Bool {
        didSet { defaults.set(remindersEnabled, forKey: Key.remindersEnabled) }
    }

    /// Whether the Weekly tab shows the "Try saying…" Siri tip. Closing the
    /// tip turns this off; the Profile tab can turn it back on.
    var showsSiriTip: Bool {
        didSet { defaults.set(showsSiriTip, forKey: Key.showsSiriTip) }
    }

    /// Up to two initials from the display name, e.g. "Hector Hernandez"
    /// becomes "HH". Empty when no name is set.
    var initials: String {
        let words = displayName.split(separator: " ").prefix(2)
        return words.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        displayName = defaults.string(forKey: Key.displayName) ?? ""
        accentTheme = defaults.string(forKey: Key.accentTheme)
            .flatMap(AccentTheme.init(rawValue:)) ?? .teal
        appearance = defaults.string(forKey: Key.appearance)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system
        // `bool(forKey:)` returns false for a missing key, so check first to
        // default new installs to on.
        celebrationsEnabled = defaults.object(forKey: Key.celebrationsEnabled) as? Bool ?? true
        remindersEnabled = defaults.object(forKey: Key.remindersEnabled) as? Bool ?? true
        showsSiriTip = defaults.object(forKey: Key.showsSiriTip) as? Bool ?? true
    }

    /// Settings backed by a throwaway store, so previews never read or
    /// write the app's real preferences.
    static func preview(name: String = "Hector Hernandez", theme: AccentTheme = .teal) -> UserSettings {
        let suiteName = "preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let settings = UserSettings(defaults: defaults)
        settings.displayName = name
        settings.accentTheme = theme
        return settings
    }
}
