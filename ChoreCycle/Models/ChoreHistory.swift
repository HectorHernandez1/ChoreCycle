import Foundation
import SwiftData

/// How one week or month went for chores of a single frequency.
struct PeriodSummary: Identifiable {
    let period: DateInterval
    /// Chores of this frequency that existed at some point during the period.
    let scheduledCount: Int
    /// How many of those were checked off inside the period.
    let doneCount: Int

    var id: Date { period.start }

    /// Every scheduled chore was done.
    var isComplete: Bool {
        scheduledCount > 0 && doneCount == scheduledCount
    }
}

/// A current streak and the best one on record, counted in weeks or months.
struct Streak: Equatable {
    var current: Int
    var best: Int
}

/// One line in the History log: a single check-off.
struct HistoryEntry: Identifiable {
    let id: PersistentIdentifier
    let choreName: String
    let frequency: Frequency
    let completedAt: Date
}

/// One week's worth of check-offs, newest first.
struct HistoryWeek: Identifiable {
    let period: DateInterval
    let entries: [HistoryEntry]
    /// The weekly-chore score for this week, if any weekly chores existed.
    let weeklySummary: PeriodSummary?

    var id: Date { period.start }
}

/// Works out streaks and the week-by-week log shown on the History tab.
///
/// Everything here is derived from the `Completion` records the app already
/// keeps, so there's nothing extra to store or sync.
enum ChoreHistory {
    /// One summary per period for a calendar-aligned frequency (weekly or
    /// monthly), oldest first. History starts with the period in which the
    /// first chore of that frequency was created and runs through the
    /// period containing `now`.
    ///
    /// A chore counts toward a period if it was created before the period
    /// ended, matching the checklist, where a chore added mid-week shows up
    /// in that week's list straight away.
    static func summaries(of chores: [Chore],
                          frequency: Frequency,
                          asOf now: Date = .now,
                          calendar: Calendar = .mondayFirst) -> [PeriodSummary] {
        let matching = chores.filter { $0.frequency == frequency }
        guard frequency.isCalendarAligned,
              let earliest = matching.map(\.createdAt).min() else { return [] }

        var summaries: [PeriodSummary] = []
        var period = frequency.period(containing: min(earliest, now), calendar: calendar)
        let current = frequency.period(containing: now, calendar: calendar)

        while period.start <= current.start {
            let scheduled = matching.filter { $0.createdAt < period.end }
            let done = scheduled.filter { $0.isDone(asOf: period.start, calendar: calendar) }
            summaries.append(PeriodSummary(period: period,
                                           scheduledCount: scheduled.count,
                                           doneCount: done.count))
            // Step to the next period. `period.end` is the next one's first instant.
            period = frequency.period(containing: period.end, calendar: calendar)
        }
        return summaries
    }

    /// Consecutive complete periods. The last summary is the period still
    /// in progress: finishing it extends the streak, but not having
    /// finished it yet doesn't break the streak.
    static func streak(from summaries: [PeriodSummary]) -> Streak {
        var run = 0
        var best = 0
        for (index, summary) in summaries.enumerated() {
            if summary.isComplete {
                run += 1
                best = max(best, run)
            } else if index != summaries.count - 1 {
                run = 0
            }
        }
        return Streak(current: run, best: best)
    }

    /// Every check-off on or before `now`, grouped into Monday-first weeks,
    /// newest week first. Weeks with nothing checked off are left out.
    static func weeks(of chores: [Chore],
                      asOf now: Date = .now,
                      calendar: Calendar = .mondayFirst) -> [HistoryWeek] {
        let entries = chores.flatMap { chore in
            chore.allCompletions
                .filter { $0.completedAt <= now }
                .map { HistoryEntry(id: $0.persistentModelID,
                                    choreName: chore.name,
                                    frequency: chore.frequency,
                                    completedAt: $0.completedAt) }
        }

        // `Dictionary(grouping:by:)` buckets entries by the start of their week.
        let byWeek = Dictionary(grouping: entries) {
            Frequency.weekly.period(containing: $0.completedAt, calendar: calendar).start
        }
        let weeklySummaries = Dictionary(
            uniqueKeysWithValues: summaries(of: chores, frequency: .weekly, asOf: now, calendar: calendar)
                .map { ($0.period.start, $0) }
        )

        return byWeek.keys.sorted(by: >).map { start in
            HistoryWeek(
                period: Frequency.weekly.period(containing: start, calendar: calendar),
                entries: (byWeek[start] ?? []).sorted { $0.completedAt > $1.completedAt },
                weeklySummary: weeklySummaries[start]
            )
        }
    }
}
