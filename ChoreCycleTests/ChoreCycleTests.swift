import Testing
import Foundation
import SwiftData
@testable import ChoreCycle

// MARK: - Shared helpers

/// Monday-first calendar, the same one the app uses for all period math.
let testCalendar = Calendar.mondayFirst

/// Builds a date in the current time zone. Defaults to 10:00 so "same day"
/// comparisons don't collide with midnight boundaries.
func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 10, minute: Int = 0) -> Date {
    testCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

/// Sunday, November 8 2026 at noon: the last day of a Monday-first week, so
/// week-boundary bugs show up immediately.
let sundayNoon = day(2026, 11, 8, hour: 12)

/// An empty in-memory database for one test.
///
/// Tests run inside the app, and SwiftData traps when two containers for
/// the same models exist in one process. So the app opens a single
/// in-memory container when it detects it's hosting tests (see `MyApp`),
/// and every test wipes it before starting instead of creating its own.
@MainActor
func makeContext() throws -> ModelContext {
    let container = try #require(MyApp.testContainer, "The app must be launched as the test host")
    let context = container.mainContext
    for completion in try context.fetch(FetchDescriptor<Completion>()) {
        context.delete(completion)
    }
    for chore in try context.fetch(FetchDescriptor<Chore>()) {
        context.delete(chore)
    }
    try context.save()
    return context
}

/// Parent for every suite that touches the database.
///
/// Swift Testing runs suites in parallel by default, but these all share
/// the one in-memory store from `makeContext()`, so they run one test at a
/// time. Pure logic suites (`PeriodTests`, `UserSettingsTests`) stay parallel.
@Suite(.serialized)
enum DatabaseTests {}

// MARK: - Periods

struct PeriodTests {
    @Test func weeklyPeriodRunsMondayToMonday() {
        let period = Frequency.weekly.period(containing: sundayNoon, calendar: testCalendar)
        #expect(period.start == day(2026, 11, 2, hour: 0))
        #expect(period.end == day(2026, 11, 9, hour: 0))
    }

    @Test func midnightMondayBelongsToTheNewWeek() {
        let mondayMidnight = day(2026, 11, 9, hour: 0)
        let period = Frequency.weekly.period(containing: mondayMidnight, calendar: testCalendar)
        #expect(period.start == mondayMidnight)
    }

    @Test func monthlyPeriodIsTheCalendarMonth() {
        let period = Frequency.monthly.period(containing: sundayNoon, calendar: testCalendar)
        #expect(period.start == day(2026, 11, 1, hour: 0))
        #expect(period.end == day(2026, 12, 1, hour: 0))
    }

    @Test func rollingFrequenciesUseAMonthlyChecklistPeriod() {
        for frequency in [Frequency.everyThreeMonths, .everySixMonths, .yearly] {
            let period = frequency.period(containing: sundayNoon, calendar: testCalendar)
            #expect(period.start == day(2026, 11, 1, hour: 0), "\(frequency)")
            #expect(period.end == day(2026, 12, 1, hour: 0), "\(frequency)")
        }
    }

    @Test func containsExcludingEndExcludesTheEndInstant() {
        let period = DateInterval(start: day(2026, 11, 2, hour: 0), end: day(2026, 11, 9, hour: 0))
        #expect(period.containsExcludingEnd(period.start))
        #expect(period.containsExcludingEnd(day(2026, 11, 8, hour: 23, minute: 59)))
        #expect(!period.containsExcludingEnd(period.end))
        #expect(!period.containsExcludingEnd(day(2026, 11, 1, hour: 23, minute: 59)))
    }

    @Test func frequencyMetadataIsConsistent() {
        #expect(Frequency.weekly.isCalendarAligned)
        #expect(Frequency.monthly.isCalendarAligned)
        #expect(!Frequency.everySixMonths.isCalendarAligned)

        #expect(Frequency.weekly.monthInterval == nil)
        #expect(Frequency.monthly.monthInterval == nil)
        #expect(Frequency.everyThreeMonths.monthInterval == 3)
        #expect(Frequency.everySixMonths.monthInterval == 6)
        #expect(Frequency.yearly.monthInterval == 12)

        // Raw values are persisted; make sure nobody renames them by accident.
        #expect(Frequency.weekly.rawValue == "weekly")
        #expect(Frequency.monthly.rawValue == "monthly")
        #expect(Frequency.everyThreeMonths.rawValue == "everyThreeMonths")
        #expect(Frequency.everySixMonths.rawValue == "everySixMonths")
        #expect(Frequency.yearly.rawValue == "yearly")
    }
}

// MARK: - Weekly and monthly chores

extension DatabaseTests {
    @MainActor
    struct CalendarAlignedChoreTests {
        @Test func newChoreIsNotDone() throws {
            let context = try makeContext()
            let chore = Chore(name: "Vacuum", frequency: .weekly, sortOrder: 0)
            context.insert(chore)

            #expect(!chore.isDone(asOf: sundayNoon))
            #expect(chore.dueDate(asOf: sundayNoon) == nil)
            #expect(!chore.isDue(inPeriodContaining: sundayNoon))
        }

        @Test func checkingAddsOneCompletion() throws {
            let context = try makeContext()
            let chore = Chore(name: "Vacuum", frequency: .weekly, sortOrder: 0)
            context.insert(chore)

            chore.toggleCompletion(on: sundayNoon, in: context)

            #expect(chore.isDone(asOf: sundayNoon))
            #expect(chore.allCompletions.count == 1)
            #expect(chore.allCompletions.first?.completedAt == sundayNoon)
        }

        @Test func weeklyChoreResetsOnMonday() throws {
            let context = try makeContext()
            let chore = Chore(name: "Vacuum", frequency: .weekly, sortOrder: 0)
            context.insert(chore)
            chore.toggleCompletion(on: sundayNoon, in: context)

            #expect(chore.isDone(asOf: day(2026, 11, 8, hour: 23, minute: 59)))
            #expect(!chore.isDone(asOf: day(2026, 11, 9, hour: 0)))
        }

        @Test func checkingInANewWeekKeepsLastWeeksHistory() throws {
            let context = try makeContext()
            let chore = Chore(name: "Vacuum", frequency: .weekly, sortOrder: 0)
            context.insert(chore)
            chore.toggleCompletion(on: sundayNoon, in: context)

            let nextTuesday = day(2026, 11, 10)
            chore.toggleCompletion(on: nextTuesday, in: context)

            #expect(chore.allCompletions.count == 2)
            #expect(chore.isDone(asOf: nextTuesday))
        }

        @Test func uncheckingRemovesOnlyThisPeriodsCompletion() throws {
            let context = try makeContext()
            let chore = Chore(name: "Vacuum", frequency: .weekly, sortOrder: 0)
            context.insert(chore)
            let lastWeek = day(2026, 11, 1)
            chore.toggleCompletion(on: lastWeek, in: context)
            chore.toggleCompletion(on: sundayNoon, in: context)
            #expect(chore.allCompletions.count == 2)

            // Second toggle this week unchecks it.
            chore.toggleCompletion(on: sundayNoon, in: context)

            #expect(!chore.isDone(asOf: sundayNoon))
            #expect(chore.allCompletions.count == 1)
            #expect(chore.allCompletions.first?.completedAt == lastWeek)
        }

        @Test func monthlyChoreResetsOnTheFirst() throws {
            let context = try makeContext()
            let chore = Chore(name: "Pay bills", frequency: .monthly, sortOrder: 0)
            context.insert(chore)
            chore.toggleCompletion(on: day(2026, 11, 30, hour: 22), in: context)

            #expect(chore.isDone(asOf: day(2026, 11, 30, hour: 23, minute: 59)))
            #expect(!chore.isDone(asOf: day(2026, 12, 1, hour: 0)))
            #expect(chore.isDone(asOf: day(2026, 11, 1, hour: 0)), "Any time in November counts")
        }

        @Test func deletingAChoreCascadesToItsCompletions() throws {
            let context = try makeContext()
            let chore = Chore(name: "Vacuum", frequency: .weekly, sortOrder: 0)
            context.insert(chore)
            chore.toggleCompletion(on: sundayNoon, in: context)
            try context.save()

            context.delete(chore)
            try context.save()

            let remaining = try context.fetch(FetchDescriptor<Completion>())
            #expect(remaining.isEmpty)
        }
    }

    @MainActor
    struct ReorderTests {
        @Test func movingAChoreReusesTheSectionsSortOrders() throws {
            let context = try makeContext()
            // Gaps in the numbers stand in for chores in other tabs.
            let trash = Chore(name: "Trash", frequency: .weekly, sortOrder: 0)
            let laundry = Chore(name: "Laundry", frequency: .weekly, sortOrder: 3)
            let vacuum = Chore(name: "Vacuum", frequency: .weekly, sortOrder: 7)
            let bills = Chore(name: "Bills", frequency: .monthly, sortOrder: 5)
            for chore in [trash, laundry, vacuum, bills] {
                context.insert(chore)
            }

            // Drag Vacuum to the top.
            Chore.reorder([trash, laundry, vacuum], fromOffsets: [2], toOffset: 0)

            #expect(vacuum.sortOrder == 0)
            #expect(trash.sortOrder == 3)
            #expect(laundry.sortOrder == 7)
            #expect(bills.sortOrder == 5, "Chores in other sections are untouched")
        }

        @Test func movingDownTheList() throws {
            let context = try makeContext()
            let chores = (0..<4).map { Chore(name: "Chore \($0)", frequency: .weekly, sortOrder: $0) }
            chores.forEach(context.insert)

            // `toOffset` counts positions before the move, so 3 lands it
            // just above the last chore.
            Chore.reorder(chores, fromOffsets: [0], toOffset: 3)

            let order = chores.sorted { $0.sortOrder < $1.sortOrder }.map(\.name)
            #expect(order == ["Chore 1", "Chore 2", "Chore 0", "Chore 3"])
        }
    }

    @MainActor
    struct UndoDeleteTests {
        @Test func restoringADeletedChoreBringsBackItsHistory() throws {
            let context = try makeContext()
            let created = day(2026, 1, 1)
            let chore = Chore(name: "Furnace filter", frequency: .everySixMonths, sortOrder: 4,
                              createdAt: created, nextDueDate: day(2026, 3, 1),
                              notes: "16×25×1, MERV 8")
            let originalID = chore.choreID
            context.insert(chore)
            chore.addCompletion(at: day(2026, 5, 1))
            chore.addCompletion(at: day(2026, 11, 2))
            try context.save()

            let snapshot = DeletedChore(chore)
            context.delete(chore)
            try context.save()
            #expect(try context.fetchCount(FetchDescriptor<Completion>()) == 0)

            snapshot.restore(into: context)
            try context.save()

            let restored = try #require(try context.fetch(FetchDescriptor<Chore>()).first)
            #expect(restored.name == "Furnace filter")
            #expect(restored.frequency == .everySixMonths)
            #expect(restored.sortOrder == 4)
            #expect(restored.createdAt == created)
            #expect(restored.nextDueDate == day(2026, 3, 1))
            #expect(restored.notes == "16×25×1, MERV 8")
            #expect(restored.choreID == originalID, "Saved Siri shortcuts keep working")
            #expect(Set(restored.allCompletions.map(\.completedAt)) == [day(2026, 5, 1), day(2026, 11, 2)])
            #expect(restored.dueDate(asOf: sundayNoon) == day(2027, 5, 2))
        }
    }
}
