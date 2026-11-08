import Foundation

/// How often a chore repeats.
///
/// SwiftData can store any `Codable` enum directly on a model. The `String`
/// raw values are what get saved to disk, so don't rename them later.
///
/// `nonisolated` opts this simple value type out of the project's default
/// `@MainActor` isolation so it can be used from any thread (SwiftData
/// encodes and decodes it in the background).
nonisolated enum Frequency: String, Codable, CaseIterable, Identifiable {
    case weekly
    case monthly

    /// `Identifiable` lets SwiftUI's `ForEach` loop over the cases directly.
    var id: Self { self }

    /// Human-readable name shown in the picker.
    var title: String {
        switch self {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }

    /// The calendar unit that defines one period for this frequency.
    var calendarComponent: Calendar.Component {
        switch self {
        case .weekly: .weekOfYear
        case .monthly: .month
        }
    }
}
