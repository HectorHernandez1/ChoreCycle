import Testing
import Foundation
import SwiftData
@testable import ChoreCycle

/// Pure date helpers and frequency metadata for the every-2-weeks and
/// pinned-weekday schedules.
struct WeekdayMathTests {
    @Test func movingToAWeekdayStaysInTheSameMondayFirstWeek() {
        // Sunday Nov 8 is the last day of the week of Monday Nov 2.
        #expect(testCalendar.date(sundayNoon, movedToWeekday: 3) == day(2026, 11, 3, hour: 0), "Tuesday")
        #expect(testCalendar.date(sundayNoon, movedToWeekday: 2) == day(2026, 11, 2, hour: 0), "Monday")
        #expect(testCalendar.date(sundayNoon, movedToWeekday: 1) == day(2026, 11, 8, hour: 0), "Sunday")
    }

    @Test func weekdaysAreListedMondayFirst() {
        #expect(testCalendar.orderedWeekdays == [2, 3, 4, 5, 6, 7, 1])
    }

    @Test func everyTwoWeeksMetadata() {
        let frequency = Frequency.everyTwoWeeks
        #expect(frequency.rawValue == "everyTwoWeeks", "Persisted; never rename")
        #expect(!frequency.isCalendarAligned)
        #expect(frequency.monthInterval == nil)
        #expect(frequency.rollingInterval == DateComponents(day: 14))
        #expect(frequency.calendarComponent == .weekOfYear, "Lives on the Weekly tab")
        #expect(frequency.supportsWeekday)
        #expect(Frequency.weekly.supportsWeekday)
        #expect(!Frequency.monthly.supportsWeekday)
        #expect(Frequency.everySixMonths.rollingInterval == DateComponents(month: 6))
    }
}

extension DatabaseTests {
    /// Every-2-weeks chores and chores pinned to a weekday. "Now" is
    /// Sunday Nov 8, 2026 unless a test says otherwise.
    @MainActor
    struct ScheduleTests {
        private func makeChore(_ frequency: Frequency,
                               weekday: Int? = nil,
                               doneOn dates: [Date] = [],
                               nextDueDate: Date? = nil,
                               in context: ModelContext) -> Chore {
            let chore = Chore(name: "Trash", frequency: frequency, sortOrder: 0,
                              createdAt: day(2026, 1, 1), nextDueDate: nextDueDate, dueWeekday: weekday)
            context.insert(chore)
            for date in dates {
                chore.addCompletion(at: date)
            }
            return chore
        }

        // MARK: Every 2 weeks

        @Test func everyTwoWeeksIsDueFourteenDaysLater() throws {
            let context = try makeContext()
            let chore = makeChore(.everyTwoWeeks, doneOn: [day(2026, 11, 2)], in: context)
            #expect(chore.dueDate(asOf: sundayNoon) == day(2026, 11, 16))
        }

        @Test func aPinnedWeekdayStopsTheScheduleDrifting() throws {
            let context = try makeContext()
            // Tuesday chore done a day late, on Wednesday Nov 4: still due
            // on Tuesday Nov 17, not Wednesday Nov 18.
            let chore = makeChore(.everyTwoWeeks, weekday: 3, doneOn: [day(2026, 11, 4)], in: context)
            #expect(chore.dueDate(asOf: sundayNoon) == day(2026, 11, 17, hour: 0))
        }

        @Test func everyTwoWeeksAppearsOnTheWeeklyTabEveryOtherWeek() throws {
            let context = try makeContext()
            let chore = makeChore(.everyTwoWeeks, doneOn: [day(2026, 11, 2)], in: context)

            #expect(chore.isDue(inPeriodContaining: sundayNoon), "Done this week, so still listed")
            #expect(!chore.isDue(inPeriodContaining: day(2026, 11, 10)), "Off week: upcoming")
            #expect(chore.isDue(inPeriodContaining: day(2026, 11, 16)), "Due again")
            #expect(!chore.isDone(asOf: day(2026, 11, 16)))
        }

        @Test func weeklyChecklistIncludesEveryTwoWeeksButNotMonthlyTabChores() throws {
            let context = try makeContext()
            let vacuum = makeChore(.weekly, in: context)
            let sheets = makeChore(.everyTwoWeeks, nextDueDate: day(2026, 11, 5), in: context)
            let filter = makeChore(.everySixMonths, nextDueDate: day(2026, 11, 5), in: context)

            let weekly = Chore.checklist(for: .weekly, from: [vacuum, sheets, filter], asOf: sundayNoon)
            #expect(weekly.map(\.frequency) == [.weekly, .everyTwoWeeks])

            let monthly = Chore.checklist(for: .monthly, from: [vacuum, sheets, filter], asOf: sundayNoon)
            #expect(monthly.map(\.frequency) == [.everySixMonths])
        }

        // MARK: Weekly chores pinned to a day

        @Test func weeklyChoreWithAWeekdayIsDueThatDay() throws {
            let context = try makeContext()
            let tuesday = makeChore(.weekly, weekday: 3, in: context)
            #expect(tuesday.dueDate(asOf: sundayNoon) == day(2026, 11, 3, hour: 0))
            #expect(tuesday.isOverdue(asOf: sundayNoon), "Tuesday has passed and it isn't done")

            let sunday = makeChore(.weekly, weekday: 1, in: context)
            #expect(!sunday.isOverdue(asOf: sundayNoon), "Due today isn't overdue")
        }

        @Test func doingAPinnedWeeklyChoreClearsOverdue() throws {
            let context = try makeContext()
            let chore = makeChore(.weekly, weekday: 3, doneOn: [day(2026, 11, 5)], in: context)
            #expect(!chore.isOverdue(asOf: sundayNoon))
        }

        @Test func weeklyChoreWithoutAWeekdayHasNoDueDate() throws {
            let context = try makeContext()
            let chore = makeChore(.weekly, in: context)
            #expect(chore.dueDate(asOf: sundayNoon) == nil)
            #expect(!chore.hasReminder)
        }

        // MARK: Reminders

        @Test func pinnedWeeklyReminderFiresThatMorning() throws {
            let context = try makeContext()
            let chore = makeChore(.weekly, weekday: 3, in: context)
            let mondayMorning = day(2026, 11, 2, hour: 8)
            #expect(chore.nextReminderDate(after: mondayMorning, hour: 9) == day(2026, 11, 3, hour: 9))
        }

        @Test func pinnedWeeklyReminderMovesToNextWeekOnceDoneOrPassed() throws {
            let context = try makeContext()
            let done = makeChore(.weekly, weekday: 3, doneOn: [day(2026, 11, 2)], in: context)
            #expect(done.nextReminderDate(after: day(2026, 11, 2, hour: 12), hour: 9) == day(2026, 11, 10, hour: 9))

            let missed = makeChore(.weekly, weekday: 3, in: context)
            #expect(missed.nextReminderDate(after: day(2026, 11, 4), hour: 9) == day(2026, 11, 10, hour: 9))
        }

        @Test func rollingReminderFiresOnTheDueDateOnly() throws {
            let context = try makeContext()
            let upcoming = makeChore(.everySixMonths, nextDueDate: day(2026, 11, 20, hour: 0), in: context)
            #expect(upcoming.nextReminderDate(after: sundayNoon, hour: 9) == day(2026, 11, 20, hour: 9))

            let overdue = makeChore(.everySixMonths, nextDueDate: day(2026, 11, 1, hour: 0), in: context)
            #expect(overdue.nextReminderDate(after: sundayNoon, hour: 9) == nil)
        }

        @Test func monthlyChoresNeverGetReminders() throws {
            let context = try makeContext()
            let chore = makeChore(.monthly, in: context)
            #expect(!chore.hasReminder)
            #expect(chore.nextReminderDate(after: sundayNoon, hour: 9) == nil)
        }
    }
}
