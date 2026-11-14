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
/// - **Rolling** (every 2 weeks, 3 months, 6 months, yearly): the chore is
///   due a fixed interval after the last time it was checked off, whatever
///   the calendar says. Doing the furnace filter on June 28 shouldn't make
///   it due again on July 1. Every-2-weeks chores appear on the Weekly tab;
///   the rest on the Monthly tab.
///
/// `nonisolated` opts this simple value type out of the project's default
/// `@MainActor` isolation so it can be used from any thread (SwiftData
/// encodes and decodes it in the background).
nonisolated enum Frequency: String, Codable, CaseIterable, Identifiable {
    // Declaration order is the order in the editor's picker. Only the raw
    // values are saved, so cases can be inserted anywhere.
    case weekly
    case everyTwoWeeks
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
        case .everyTwoWeeks: "Every 2 Weeks"
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
        case .everyTwoWeeks, .everyThreeMonths, .everySixMonths, .yearly: false
        }
    }

    /// For rolling frequencies, how many months pass between one completion
    /// and the next due date. `nil` for calendar-aligned frequencies and
    /// for every 2 weeks, which counts in days instead (`rollingInterval`).
    var monthInterval: Int? {
        switch self {
        case .weekly, .everyTwoWeeks, .monthly: nil
        case .everyThreeMonths: 3
        case .everySixMonths: 6
        case .yearly: 12
        }
    }

    /// For rolling frequencies, the time from one completion to the next
    /// due date. `nil` for calendar-aligned frequencies.
    var rollingInterval: DateComponents? {
        if self == .everyTwoWeeks {
            return DateComponents(day: 14)
        }
        return monthInterval.map { DateComponents(month: $0) }
    }

    /// The calendar unit that defines one checklist period, which also
    /// decides the tab: every-2-weeks chores surface in the Weekly tab in
    /// the week they're due, and the longer rolling chores in the Monthly
    /// tab in the month they're due.
    var calendarComponent: Calendar.Component {
        switch self {
        case .weekly, .everyTwoWeeks: .weekOfYear
        case .monthly, .everyThreeMonths, .everySixMonths, .yearly: .month
        }
    }

    /// Whether a chore with this frequency can be pinned to a day of the
    /// week ("trash goes out Tuesday").
    var supportsWeekday: Bool {
        self == .weekly || self == .everyTwoWeeks
    }
}
