import Testing
import Foundation
import SwiftData
@testable import ChoreCycle

/// Streaks never touch the database, so they're tested on plain summaries.
struct StreakTests {
    /// Builds back-to-back weekly summaries starting Monday Oct 5, 2026.
    /// `true` means every chore was done that week.
    private func weeks(_ results: [Bool]) -> [PeriodSummary] {
        results.enumerated().map { index, complete in
            let start = testCalendar.date(byAdding: .weekOfYear, value: index, to: day(2026, 10, 5, hour: 0))!
            return PeriodSummary(period: DateInterval(start: start, duration: 7 * 86_400),
                                 scheduledCount: 2,
                                 doneCount: complete ? 2 : 1)
        }
    }

    @Test func noHistoryMeansNoStreak() {
        #expect(ChoreHistory.streak(from: []) == Streak(current: 0, best: 0))
    }

    @Test func anUnfinishedCurrentWeekDoesNotBreakTheStreak() {
        let streak = ChoreHistory.streak(from: weeks([true, true, false]))
        #expect(streak == Streak(current: 2, best: 2))
    }

    @Test func finishingTheCurrentWeekExtendsTheStreak() {
        let streak = ChoreHistory.streak(from: weeks([true, true, true]))
        #expect(streak == Streak(current: 3, best: 3))
    }

    @Test func aMissedPastWeekResetsTheStreakButKeepsTheBest() {
        let streak = ChoreHistory.streak(from: weeks([true, true, true, false, true, false]))
        #expect(streak == Streak(current: 1, best: 3))
    }

    @Test func aPeriodWithNothingScheduledIsNotComplete() {
        let empty = PeriodSummary(period: DateInterval(start: sundayNoon, duration: 1),
                                  scheduledCount: 0, doneCount: 0)
        #expect(!empty.isComplete)
    }
}

extension DatabaseTests {
    /// History built from real chores and completions. "Now" is Sunday
    /// Nov 8, 2026, the last day of the week of Nov 2.
    @MainActor
    struct ChoreHistoryTests {
        private let now = sundayNoon

        private func makeChore(_ name: String,
                               _ frequency: Frequency = .weekly,
                               createdAt: Date = day(2026, 10, 19),
                               doneOn dates: [Date] = [],
                               in context: ModelContext) -> Chore {
            let chore = Chore(name: name, frequency: frequency, sortOrder: 0, createdAt: createdAt)
            context.insert(chore)
            for date in dates {
                chore.addCompletion(at: date)
            }
            return chore
        }

        @Test func summariesRunFromTheFirstChoreThroughThisWeek() throws {
            let context = try makeContext()
            // Created Monday Oct 19: weeks of Oct 19, Oct 26, Nov 2.
            let chore = makeChore("Vacuum", doneOn: [day(2026, 10, 20), day(2026, 11, 3)], in: context)

            let summaries = ChoreHistory.summaries(of: [chore], frequency: .weekly, asOf: now)
            #expect(summaries.map(\.period.start) == [day(2026, 10, 19, hour: 0),
                                                       day(2026, 10, 26, hour: 0),
                                                       day(2026, 11, 2, hour: 0)])
            #expect(summaries.map(\.isComplete) == [true, false, true])
        }

        @Test func choresAddedLaterOnlyCountFromTheirFirstWeek() throws {
            let context = try makeContext()
            let vacuum = makeChore("Vacuum", doneOn: [day(2026, 10, 20), day(2026, 10, 27)], in: context)
            // Added Wednesday Oct 28 and never done.
            let laundry = makeChore("Laundry", createdAt: day(2026, 10, 28), in: context)

            let summaries = ChoreHistory.summaries(of: [vacuum, laundry], frequency: .weekly, asOf: now)
            #expect(summaries.map(\.scheduledCount) == [1, 2, 2])
            #expect(summaries.map(\.doneCount) == [1, 1, 0])
        }

        @Test func weeklyStreakFromRealCompletions() throws {
            let context = try makeContext()
            let chore = makeChore("Vacuum", createdAt: day(2026, 10, 5),
                                  doneOn: [day(2026, 10, 6), day(2026, 10, 20), day(2026, 10, 27)],
                                  in: context)

            // Oct 5 done, Oct 12 missed, Oct 19 and 26 done, Nov 2 in progress.
            let summaries = ChoreHistory.summaries(of: [chore], frequency: .weekly, asOf: now)
            #expect(ChoreHistory.streak(from: summaries) == Streak(current: 2, best: 2))
        }

        @Test func monthlySummariesUseCalendarMonths() throws {
            let context = try makeContext()
            let chore = makeChore("Pay bills", .monthly, createdAt: day(2026, 9, 15),
                                  doneOn: [day(2026, 9, 30), day(2026, 10, 1)], in: context)

            let summaries = ChoreHistory.summaries(of: [chore], frequency: .monthly, asOf: now)
            #expect(summaries.map(\.isComplete) == [true, true, false])
            #expect(ChoreHistory.streak(from: summaries) == Streak(current: 2, best: 2))
        }

        @Test func rollingFrequenciesHaveNoSummaries() throws {
            let context = try makeContext()
            let chore = makeChore("Furnace filter", .everySixMonths, in: context)
            #expect(ChoreHistory.summaries(of: [chore], frequency: .everySixMonths, asOf: now).isEmpty)
        }

        @Test func weeksGroupCheckOffsNewestFirstAndSkipEmptyWeeks() throws {
            let context = try makeContext()
            let vacuum = makeChore("Vacuum", doneOn: [day(2026, 10, 20), day(2026, 11, 3)], in: context)
            let filter = makeChore("Furnace filter", .everySixMonths,
                                   doneOn: [day(2026, 11, 5)], in: context)

            let weeks = ChoreHistory.weeks(of: [vacuum, filter], asOf: now)
            // The week of Oct 26 had nothing checked off.
            #expect(weeks.map(\.period.start) == [day(2026, 11, 2, hour: 0), day(2026, 10, 19, hour: 0)])
            #expect(weeks[0].entries.map(\.choreName) == ["Furnace filter", "Vacuum"])
            #expect(weeks[0].weeklySummary?.doneCount == 1)
            #expect(weeks[1].entries.count == 1)
        }

        @Test func futureCheckOffsAreLeftOut() throws {
            let context = try makeContext()
            let chore = makeChore("Vacuum", doneOn: [day(2026, 11, 3), day(2026, 11, 10)], in: context)
            let weeks = ChoreHistory.weeks(of: [chore], asOf: now)
            #expect(weeks.count == 1)
            #expect(weeks[0].entries.count == 1)
        }
    }
}
