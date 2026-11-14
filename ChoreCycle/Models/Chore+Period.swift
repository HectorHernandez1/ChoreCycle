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

    /// The day in the same week as `date` (by this calendar's week, so
    /// Monday to Sunday for `mondayFirst`) that falls on `weekday`
    /// (1 = Sunday … 7 = Saturday), at the start of that day.
    nonisolated func date(_ date: Date, movedToWeekday weekday: Int) -> Date? {
        guard let week = dateInterval(of: .weekOfYear, for: date) else { return nil }
        // Days into the week: e.g. Tuesday is 1 day after a Monday start.
        let offset = (weekday - firstWeekday + 7) % 7
        return self.date(byAdding: .day, value: offset, to: week.start)
    }

    /// Weekday numbers in display order for this calendar (Monday first
    /// for `mondayFirst`), for pickers.
    nonisolated var orderedWeekdays: [Int] {
        (0..<7).map { (firstWeekday - 1 + $0) % 7 + 1 }
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

    /// When the chore is next due, or `nil` if it doesn't have a due date.
    ///
    /// - Rolling chores (every 2 weeks, 3 months, 6 months, yearly): the
    ///   last completion plus the interval, or `nextDueDate` if it has never
    ///   been done (falling back to "due now"). With a `dueWeekday`, the
    ///   result moves to that day of the same week, so doing a Tuesday chore
    ///   a day late doesn't make it drift to Wednesdays.
    /// - Weekly chores with a `dueWeekday`: that day in the current week.
    /// - Other weekly and monthly chores: `nil`.
    func dueDate(asOf date: Date = .now, calendar: Calendar = .mondayFirst) -> Date? {
        guard let interval = frequency.rollingInterval else {
            guard frequency == .weekly, let dueWeekday else { return nil }
            return calendar.date(date, movedToWeekday: dueWeekday)
        }
        guard let last = lastCompletion(asOf: date) else {
            return nextDueDate ?? createdAt
        }
        let due = calendar.date(byAdding: interval, to: last) ?? last
        if frequency.supportsWeekday, let dueWeekday {
            return calendar.date(due, movedToWeekday: dueWeekday)
        }
        return due
    }

    /// Whether this chore gets a due-date notification: every rolling chore,
    /// and weekly chores pinned to a day.
    var hasReminder: Bool {
        !frequency.isCalendarAligned || (frequency == .weekly && dueWeekday != nil)
    }

    /// When the next reminder for this chore should go off (at `hour` on its
    /// due day), or `nil` if none should be scheduled.
    ///
    /// Rolling chores get one reminder on their due date, skipped once that
    /// morning has passed (the chore is showing as overdue in the app by
    /// then). Weekly chores pinned to a day remind on that day; if it's
    /// already done this week or the moment has passed, the reminder goes
    /// to next week's day instead, so one is always waiting.
    func nextReminderDate(after now: Date = .now,
                          hour: Int,
                          calendar: Calendar = .mondayFirst) -> Date? {
        guard hasReminder, let due = dueDate(asOf: now, calendar: calendar) else { return nil }

        func atHour(_ day: Date) -> Date? {
            calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
        }
        guard let fire = atHour(due) else { return nil }

        if frequency.isCalendarAligned {
            if !isDone(asOf: now, calendar: calendar), fire > now {
                return fire
            }
            return calendar.date(byAdding: .weekOfYear, value: 1, to: due).flatMap(atHour)
        }
        return fire > now ? fire : nil
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

    /// Whether the chore is overdue: its due date is before today and it
    /// hasn't been checked off since. A chore due today is not overdue.
    ///
    /// Rolling chores get a new due date as soon as they're checked off, so
    /// only weekly chores need the explicit "done this week" check.
    func isOverdue(asOf date: Date = .now, calendar: Calendar = .mondayFirst) -> Bool {
        guard let due = dueDate(asOf: date, calendar: calendar) else { return false }
        if frequency.isCalendarAligned && isDone(asOf: date, calendar: calendar) {
            return false
        }
        return due < calendar.startOfDay(for: date)
    }

    /// Whether a rolling chore belongs in the checklist for the period
    /// containing `date` (the week for every 2 weeks, the month for the
    /// rest): either it's due (or overdue) by the end of that period, or it
    /// was checked off during it and should stay visible as done until the
    /// period ends.
    func isDue(inPeriodContaining date: Date = .now, calendar: Calendar = .mondayFirst) -> Bool {
        guard !frequency.isCalendarAligned,
              let due = dueDate(asOf: date, calendar: calendar) else { return false }
        if isDone(asOf: date, calendar: calendar) {
            return true
        }
        return due < frequency.period(containing: date, calendar: calendar).end
    }

    /// The chores that make up a checklist (the ones its progress ring
    /// counts): the tab's own chores (weekly or monthly) plus any rolling
    /// chores that live on that tab and are due this period.
    static func checklist(for frequency: Frequency,
                          from chores: [Chore],
                          asOf date: Date = .now,
                          calendar: Calendar = .mondayFirst) -> [Chore] {
        let regular = chores.filter { $0.frequency == frequency }
        let dueThisPeriod = chores.filter {
            !$0.frequency.isCalendarAligned
                && $0.frequency.calendarComponent == frequency.calendarComponent
                && $0.isDue(inPeriodContaining: date, calendar: calendar)
        }
        return regular + dueThisPeriod
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
