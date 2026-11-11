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
    /// The checklist period that contains `date`: Monday 00:00 up to (but
    /// not including) the next Monday 00:00 for weekly chores, and the
    /// calendar month for everything else.
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
    /// Every completion of this chore, treating "no list yet" as empty.
    var allCompletions: [Completion] {
        completions ?? []
    }

    /// Records that the chore was done at `date`. Adding to the relationship
    /// also inserts the new `Completion` into the database and sets its
    /// `chore` property for us.
    func addCompletion(at date: Date) {
        completions = allCompletions + [Completion(completedAt: date)]
    }

    /// Completions that fall inside the current checklist period (week or
    /// month, depending on this chore's frequency) as of `date`.
    func completions(inPeriodContaining date: Date = .now,
                     calendar: Calendar = .mondayFirst) -> [Completion] {
        let period = frequency.period(containing: date, calendar: calendar)
        return allCompletions.filter { period.containsExcludingEnd($0.completedAt) }
    }

    /// The most recent time this chore was checked off on or before `date`.
    func lastCompletion(asOf date: Date = .now) -> Date? {
        allCompletions.map(\.completedAt).filter { $0 <= date }.max()
    }

    /// When a rolling chore (every 3 months, 6 months, yearly) is next due:
    /// the last completion plus the interval, or `nextDueDate` if it has
    /// never been done (falling back to "due now"). Always `nil` for weekly
    /// and monthly chores, which don't have a single due date.
    func dueDate(asOf date: Date = .now, calendar: Calendar = .mondayFirst) -> Date? {
        guard let months = frequency.monthInterval else { return nil }
        if let last = lastCompletion(asOf: date) {
            return calendar.date(byAdding: .month, value: months, to: last) ?? last
        }
        return nextDueDate ?? createdAt
    }

    /// Whether the chore has been checked off in the current checklist
    /// period: this week for weekly chores, this month for everything else.
    ///
    /// For rolling chores this deliberately ignores the due date. A chore
    /// due on the 25th should sit unchecked in this month's list until it's
    /// actually done, even though it isn't late yet.
    func isDone(asOf date: Date = .now, calendar: Calendar = .mondayFirst) -> Bool {
        !completions(inPeriodContaining: date, calendar: calendar).isEmpty
    }

    /// Whether a rolling chore is overdue: its due date is before today and
    /// it hasn't been checked off since. A chore due today is not overdue.
    func isOverdue(asOf date: Date = .now, calendar: Calendar = .mondayFirst) -> Bool {
        guard !frequency.isCalendarAligned,
              let due = dueDate(asOf: date, calendar: calendar) else { return false }
        return due < calendar.startOfDay(for: date)
    }

    /// Whether a rolling chore belongs in the Monthly checklist for the month
    /// containing `date`: either it's due (or overdue) by the end of that
    /// month, or it was checked off during that month and should stay
    /// visible as done until the month ends.
    func isDue(inMonthContaining date: Date = .now, calendar: Calendar = .mondayFirst) -> Bool {
        guard !frequency.isCalendarAligned,
              let due = dueDate(asOf: date, calendar: calendar) else { return false }
        if isDone(asOf: date, calendar: calendar) {
            return true
        }
        let month = calendar.dateInterval(of: .month, for: date)
            ?? DateInterval(start: date, duration: 0)
        return due < month.end
    }

    /// Checks the chore off (adds a `Completion` dated `date`) or, if it's
    /// already been checked this period, unchecks it by deleting this
    /// period's completions. Completions from earlier periods are left
    /// untouched, so unchecking a rolling chore restores its previous cycle.
    func toggleCompletion(on date: Date = .now,
                          in context: ModelContext,
                          calendar: Calendar = .mondayFirst) {
        let current = completions(inPeriodContaining: date, calendar: calendar)

        if current.isEmpty {
            addCompletion(at: date)
        } else {
            let period = frequency.period(containing: date, calendar: calendar)
            // Remove from the array first so views update immediately, then
            // delete the objects from the database.
            completions = allCompletions.filter { !period.containsExcludingEnd($0.completedAt) }
            for completion in current {
                context.delete(completion)
            }
        }
    }
}
