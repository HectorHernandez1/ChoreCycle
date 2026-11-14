import Testing
import Foundation
import SwiftData
@testable import ChoreCycle

extension DatabaseTests {
    /// Skipping a chore for a week or month. "Now" is Sunday Nov 8, 2026.
    @MainActor
    struct SkipTests {
        private func makeChore(_ frequency: Frequency = .weekly,
                               createdAt: Date = day(2026, 10, 5),
                               weekday: Int? = nil,
                               in context: ModelContext) -> Chore {
            let chore = Chore(name: "Mow", frequency: frequency, sortOrder: 0,
                              createdAt: createdAt, dueWeekday: weekday)
            context.insert(chore)
            return chore
        }

        @Test func aSkippedChoreIsHandledButNotDone() throws {
            let context = try makeContext()
            let chore = makeChore(in: context)
            chore.skip(on: sundayNoon, in: context)

            #expect(chore.isSkipped(asOf: sundayNoon))
            #expect(chore.isHandled(asOf: sundayNoon))
            #expect(!chore.isDone(asOf: sundayNoon))
            #expect(!chore.isSkipped(asOf: day(2026, 11, 9)), "A new week starts fresh")
        }

        @Test func tappingASkippedChoreUnskipsIt() throws {
            let context = try makeContext()
            let chore = makeChore(in: context)
            chore.skip(on: sundayNoon, in: context)
            chore.toggleCompletion(on: sundayNoon, in: context)

            #expect(!chore.isHandled(asOf: sundayNoon))
            #expect(chore.allCompletions.isEmpty)
        }

        @Test func skippingReplacesACheckOffAndMarkDoneReplacesASkip() throws {
            let context = try makeContext()
            let chore = makeChore(in: context)
            chore.toggleCompletion(on: sundayNoon, in: context)
            chore.skip(on: sundayNoon, in: context)
            #expect(chore.isSkipped(asOf: sundayNoon))
            #expect(chore.allCompletions.count == 1)

            #expect(chore.markDone(on: sundayNoon, in: context))
            #expect(chore.isDone(asOf: sundayNoon))
            #expect(chore.allCompletions.count == 1)
            #expect(!chore.markDone(on: sundayNoon, in: context), "Already done: no change")
        }

        @Test func skippingALongCycleChoreStartsItsNextCycle() throws {
            let context = try makeContext()
            let chore = makeChore(.everySixMonths, in: context)
            chore.skip(on: day(2026, 11, 2), in: context)

            #expect(chore.dueDate(asOf: sundayNoon) == day(2027, 5, 2))
            #expect(chore.lastDone(asOf: sundayNoon) == nil, "A skip isn't a time it was done")
            #expect(chore.isDue(inPeriodContaining: sundayNoon), "Stays listed as skipped this month")
        }

        @Test func skippingAPinnedChoreClearsOverdueAndMovesTheReminder() throws {
            let context = try makeContext()
            let tuesday = makeChore(weekday: 3, in: context)
            #expect(tuesday.isOverdue(asOf: sundayNoon))

            tuesday.skip(on: sundayNoon, in: context)
            #expect(!tuesday.isOverdue(asOf: sundayNoon))
            #expect(tuesday.nextReminderDate(after: sundayNoon, hour: 9) == day(2026, 11, 10, hour: 9))
        }

        @Test func skippedChoresDontCountAgainstTheWeek() throws {
            let context = try makeContext()
            let vacuum = makeChore(in: context)
            let mow = makeChore(in: context)
            vacuum.toggleCompletion(on: day(2026, 11, 3), in: context)
            mow.skip(on: day(2026, 11, 3), in: context)

            let summaries = ChoreHistory.summaries(of: [vacuum, mow], frequency: .weekly, asOf: sundayNoon)
            let thisWeek = try #require(summaries.last)
            #expect(thisWeek.scheduledCount == 1)
            #expect(thisWeek.isComplete)
        }

        @Test func aWeekWhereEverythingWasSkippedDoesntBreakTheStreak() throws {
            let context = try makeContext()
            // Created Oct 19: weeks of Oct 19, Oct 26, Nov 2.
            let chore = makeChore(createdAt: day(2026, 10, 19), in: context)
            chore.toggleCompletion(on: day(2026, 10, 20), in: context)
            chore.skip(on: day(2026, 10, 27), in: context)      // away that week
            chore.toggleCompletion(on: day(2026, 11, 3), in: context)

            let summaries = ChoreHistory.summaries(of: [chore], frequency: .weekly, asOf: sundayNoon)
            #expect(summaries.map(\.scheduledCount) == [1, 0, 1])
            #expect(ChoreHistory.streak(from: summaries) == Streak(current: 2, best: 2))
        }

        @Test func historyShowsSkipsSeparately() throws {
            let context = try makeContext()
            let chore = makeChore(in: context)
            chore.skip(on: day(2026, 11, 3), in: context)

            let weeks = ChoreHistory.weeks(of: [chore], asOf: sundayNoon)
            #expect(weeks.first?.entries.map(\.isSkip) == [true])
        }

        @Test func undoRestoresSkips() throws {
            let context = try makeContext()
            let chore = makeChore(in: context)
            chore.skip(on: sundayNoon, in: context)
            let snapshot = DeletedChore(chore)
            context.delete(chore)

            let restored = snapshot.restore(into: context)
            #expect(restored.isSkipped(asOf: sundayNoon))
        }
    }
}

struct SkippedStreakTests {
    @Test func neutralWeeksAreIgnoredAnywhereInTheRun() {
        func week(_ offset: Int, scheduled: Int, done: Int) -> PeriodSummary {
            let start = testCalendar.date(byAdding: .weekOfYear, value: offset, to: day(2026, 10, 5, hour: 0))!
            return PeriodSummary(period: DateInterval(start: start, duration: 7 * 86_400),
                                 scheduledCount: scheduled, doneCount: done)
        }
        let summaries = [
            week(0, scheduled: 2, done: 2),
            week(1, scheduled: 0, done: 0),   // all skipped
            week(2, scheduled: 2, done: 2),
            week(3, scheduled: 0, done: 0),   // this week, all skipped so far
        ]
        #expect(ChoreHistory.streak(from: summaries) == Streak(current: 2, best: 2))
    }
}
