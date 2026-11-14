import Testing
import Foundation
import SwiftData
@testable import ChoreCycle

extension DatabaseTests {
    /// Long-cycle chores (every 3 months, 6 months, yearly) are due a fixed
    /// number of months after the last completion, and surface in the
    /// Monthly tab in the month they're due. Reference "now" is Sunday
    /// Nov 8, 2026.
    @MainActor
    struct RollingChoreTests {
        private let now = sundayNoon

        /// Inserts a rolling chore, optionally with a past completion.
        private func makeChore(_ frequency: Frequency = .everySixMonths,
                               completedOn: Date? = nil,
                               nextDueDate: Date? = nil,
                               createdAt: Date = day(2026, 1, 1),
                               in context: ModelContext) -> Chore {
            let chore = Chore(name: "Furnace filter", frequency: frequency, sortOrder: 0,
                              createdAt: createdAt, nextDueDate: nextDueDate)
            context.insert(chore)
            if let completedOn {
                chore.addCompletion(at: completedOn)
            }
            return chore
        }

        // MARK: Due dates

        @Test func dueDateIsLastCompletionPlusInterval() throws {
            let context = try makeContext()
            let chore = makeChore(.everySixMonths, completedOn: day(2026, 6, 8), in: context)
            #expect(chore.dueDate(asOf: now) == day(2026, 12, 8))

            let quarterly = makeChore(.everyThreeMonths, completedOn: day(2026, 6, 8), in: context)
            #expect(quarterly.dueDate(asOf: now) == day(2026, 9, 8))

            let yearly = makeChore(.yearly, completedOn: day(2026, 6, 8), in: context)
            #expect(yearly.dueDate(asOf: now) == day(2027, 6, 8))
        }

        @Test func neverCompletedChoreUsesNextDueDate() throws {
            let context = try makeContext()
            let chore = makeChore(nextDueDate: day(2027, 1, 15), in: context)
            #expect(chore.dueDate(asOf: now) == day(2027, 1, 15))
        }

        @Test func neverCompletedChoreWithoutNextDueDateIsDueWhenCreated() throws {
            let context = try makeContext()
            let created = day(2026, 10, 1)
            let chore = makeChore(createdAt: created, in: context)
            #expect(chore.dueDate(asOf: now) == created)
            #expect(chore.isOverdue(asOf: now))
        }

        @Test func mostRecentCompletionWins() throws {
            let context = try makeContext()
            let chore = makeChore(completedOn: day(2025, 1, 1), in: context)
            chore.addCompletion(at: day(2026, 6, 8))
            #expect(chore.dueDate(asOf: now) == day(2026, 12, 8))
        }

        @Test func futureCompletionsAreIgnored() throws {
            // Guards against a clock that was set forward and then corrected.
            let context = try makeContext()
            let chore = makeChore(completedOn: day(2026, 6, 8), in: context)
            chore.addCompletion(at: day(2027, 3, 1))
            #expect(chore.lastCompletion(asOf: now) == day(2026, 6, 8))
        }

        // MARK: Done, overdue, and due-this-month

        @Test func dueTodayIsNotOverdueAndShowsThisMonth() throws {
            let context = try makeContext()
            let chore = makeChore(nextDueDate: testCalendar.startOfDay(for: now), in: context)

            #expect(!chore.isDone(asOf: now))
            #expect(!chore.isOverdue(asOf: now), "Due today is not late yet")
            #expect(chore.isDue(inPeriodContaining: now))
        }

        @Test func dueYesterdayIsOverdue() throws {
            let context = try makeContext()
            let chore = makeChore(nextDueDate: day(2026, 11, 7, hour: 23, minute: 59), in: context)
            #expect(chore.isOverdue(asOf: now))
            #expect(chore.isDue(inPeriodContaining: now))
        }

        @Test func dueLaterThisMonthIsUncheckedButListed() throws {
            // Done May 25 → due Nov 25. It's in this month's list, not done,
            // and not late.
            let context = try makeContext()
            let chore = makeChore(completedOn: day(2026, 5, 25), in: context)

            #expect(chore.dueDate(asOf: now) == day(2026, 11, 25))
            #expect(!chore.isDone(asOf: now))
            #expect(!chore.isOverdue(asOf: now))
            #expect(chore.isDue(inPeriodContaining: now))
        }

        @Test func dueNextMonthIsUpcoming() throws {
            let context = try makeContext()
            let chore = makeChore(completedOn: day(2026, 6, 8), in: context) // due Dec 8
            #expect(!chore.isDue(inPeriodContaining: now))
            #expect(!chore.isDone(asOf: now))
            #expect(!chore.isOverdue(asOf: now))
        }

        @Test func overdueFromAPastMonthShowsThisMonth() throws {
            let context = try makeContext()
            let chore = makeChore(completedOn: day(2026, 4, 8), in: context) // due Oct 8
            #expect(chore.isOverdue(asOf: now))
            #expect(chore.isDue(inPeriodContaining: now))
            #expect(!chore.isDone(asOf: now))
        }

        @Test func dueOnTheLastDayOfTheMonthCountsAsThisMonth() throws {
            let context = try makeContext()
            let chore = makeChore(nextDueDate: day(2026, 11, 30, hour: 23, minute: 59), in: context)
            #expect(chore.isDue(inPeriodContaining: now))

            let firstOfNext = makeChore(nextDueDate: day(2026, 12, 1, hour: 0), in: context)
            #expect(!firstOfNext.isDue(inPeriodContaining: now))
        }

        @Test func weeklyChoresAreNeverRolling() throws {
            let context = try makeContext()
            let chore = Chore(name: "Vacuum", frequency: .weekly, sortOrder: 0)
            context.insert(chore)
            #expect(chore.dueDate(asOf: now) == nil)
            #expect(!chore.isOverdue(asOf: now))
            #expect(!chore.isDue(inPeriodContaining: now))
        }

        // MARK: Toggling

        @Test func checkingAnOverdueChorePushesTheDueDateOut() throws {
            let context = try makeContext()
            let chore = makeChore(completedOn: day(2026, 4, 8), in: context) // due Oct 8

            chore.toggleCompletion(on: now, in: context)

            #expect(chore.isDone(asOf: now))
            #expect(!chore.isOverdue(asOf: now))
            #expect(chore.dueDate(asOf: now) == day(2027, 5, 8, hour: 12))
            #expect(chore.isDue(inPeriodContaining: now), "Stays visible as done until the month ends")
            #expect(chore.allCompletions.count == 2)
        }

        @Test func uncheckingRestoresThePreviousCycle() throws {
            let context = try makeContext()
            let chore = makeChore(completedOn: day(2026, 4, 8), in: context)
            chore.toggleCompletion(on: now, in: context)

            chore.toggleCompletion(on: now, in: context)

            #expect(!chore.isDone(asOf: now))
            #expect(chore.isOverdue(asOf: now))
            #expect(chore.dueDate(asOf: now) == day(2026, 10, 8))
            #expect(chore.allCompletions.count == 1, "The April completion is untouched")
        }

        @Test func checkingEarlyMovesItIntoThisMonth() throws {
            let context = try makeContext()
            let chore = makeChore(completedOn: day(2026, 6, 8), in: context) // due Dec 8, upcoming
            #expect(!chore.isDue(inPeriodContaining: now))

            chore.toggleCompletion(on: now, in: context)

            #expect(chore.isDone(asOf: now))
            #expect(chore.isDue(inPeriodContaining: now))
            #expect(chore.dueDate(asOf: now) == day(2027, 5, 8, hour: 12))
        }

        @Test func aCompletionThisMonthDropsOutNextMonth() throws {
            let context = try makeContext()
            let chore = makeChore(completedOn: day(2026, 4, 8), in: context)
            chore.toggleCompletion(on: now, in: context)

            let december = day(2026, 12, 15)
            #expect(!chore.isDone(asOf: december))
            #expect(!chore.isDue(inPeriodContaining: december), "Due May 2027, so it's upcoming in December")
        }
    }
}
