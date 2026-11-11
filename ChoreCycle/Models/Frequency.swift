import Foundation

/// How often a chore repeats.
///
/// SwiftData can store any `Codable` enum directly on a model. The `String`
/// raw values are what get saved to disk, so don't rename them later.
///
/// There are two kinds of frequency:
/// - **Calendar-aligned** (`weekly`, `monthly`): the chore is "done" if it was
///   checked anywhere inside the current calendar week or month, and it
///   resets when the next one starts.
/// - **Rolling** (every 3 months, 6 months, yearly): the chore is due a fixed
///   number of months after the last time it was checked off, whatever the
///   calendar says. Doing the furnace filter on June 28 shouldn't make it
///   due again on July 1.
///
/// `nonisolated` opts this simple value type out of the project's default
/// `@MainActor` isolation so it can be used from any thread (SwiftData
/// encodes and decodes it in the background).
nonisolated enum Frequency: String, Codable, CaseIterable, Identifiable {
    case weekly
    case monthly
    case everyThreeMonths
    case everySixMonths
    case yearly

    /// `Identifiable` lets SwiftUI's `ForEach` loop over the cases directly.
    var id: Self { self }

    /// Human-readable name shown in the picker.
    var title: String {
        switch self {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .everyThreeMonths: "Every 3 Months"
        case .everySixMonths: "Every 6 Months"
        case .yearly: "Yearly"
        }
    }

    /// Whether "done" is judged against the calendar week or month (`true`),
    /// or against the time since the last completion (`false`).
    var isCalendarAligned: Bool {
        switch self {
        case .weekly, .monthly: true
        case .everyThreeMonths, .everySixMonths, .yearly: false
        }
    }

    /// For rolling frequencies, how many months pass between one completion
    /// and the next due date. `nil` for calendar-aligned frequencies.
    var monthInterval: Int? {
        switch self {
        case .weekly, .monthly: nil
        case .everyThreeMonths: 3
        case .everySixMonths: 6
        case .yearly: 12
        }
    }

    /// The calendar unit that defines one checklist period. Rolling chores
    /// surface in the Monthly tab in the month they're due, so their
    /// checklist period is a month too.
    var calendarComponent: Calendar.Component {
        switch self {
        case .weekly: .weekOfYear
        case .monthly, .everyThreeMonths, .everySixMonths, .yearly: .month
        }
    }
}
