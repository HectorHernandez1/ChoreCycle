import Foundation
import SwiftData

extension Calendar {
    /// The user's current calendar, but with weeks always starting on Monday.
    /// (`firstWeekday` is 1-based: 1 = Sunday, 2 = Monday.)
    ///
    /// `nonisolated` because this project makes code `@MainActor` (UI-thread
    /// only) by default, and pure date math is safe to run anywhere.
    nonisolated static var mondayFirst: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }
}

extension Frequency {
    /// The week or month that contains `date`, e.g. Monday 00:00 up to (but
    /// not including) the next Monday 00:00.
    func period(containing date: Date, calendar: Calendar = .mondayFirst) -> DateInterval {
        calendar.dateInterval(of: calendarComponent, for: date)
            ?? DateInterval(start: date, duration: 0)
    }
}

extension DateInterval {
    /// `DateInterval.contains(_:)` includes the end date, which is also the
    /// first instant of the *next* period. This version excludes it, so a
    /// completion at exactly midnight Monday belongs to the new week only.
    nonisolated func containsExcludingEnd(_ date: Date) -> Bool {
        start <= date && date < end
    }
}

extension Chore {
    /// Completions that fall inside the current week or month (depending on
    /// this chore's frequency) as of `date`.
    func completions(inPeriodContaining date: Date = .now,
                     calendar: Calendar = .mondayFirst) -> [Completion] {
        let period = frequency.period(containing: date, calendar: calendar)
        return completions.filter { period.containsExcludingEnd($0.completedAt) }
    }

    /// Whether the chore has been checked off in the current period.
    func isDone(asOf date: Date = .now, calendar: Calendar = .mondayFirst) -> Bool {
        !completions(inPeriodContaining: date, calendar: calendar).isEmpty
    }

    /// Checks the chore off (adds a `Completion` dated `date`) or, if it's
    /// already done this period, unchecks it by deleting this period's
    /// completions. Completions from earlier periods are left untouched.
    func toggleCompletion(on date: Date = .now,
                          in context: ModelContext,
                          calendar: Calendar = .mondayFirst) {
        let current = completions(inPeriodContaining: date, calendar: calendar)

        if current.isEmpty {
            // Appending to the relationship also inserts the new Completion
            // into the database and sets its `chore` property for us.
            completions.append(Completion(completedAt: date))
        } else {
            let period = frequency.period(containing: date, calendar: calendar)
            // Remove from the array first so views update immediately, then
            // delete the objects from the database.
            completions.removeAll { period.containsExcludingEnd($0.completedAt) }
            for completion in current {
                context.delete(completion)
            }
        }
    }
}
