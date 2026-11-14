import Testing
import Foundation
import SwiftData
@testable import ChoreCycle

extension DatabaseTests {
    /// The work behind the Siri / Shortcuts intents, run against the test
    /// database. (The intents themselves read the database through
    /// `@Dependency`, which only the system fills in, so tests call the
    /// static helpers they delegate to.)
    @MainActor
    struct ChoreIntentsTests {
        private func insert(_ name: String, _ frequency: Frequency = .weekly,
                            sortOrder: Int = 0, in context: ModelContext) -> Chore {
            let chore = Chore(name: name, frequency: frequency, sortOrder: sortOrder)
            context.insert(chore)
            return chore
        }

        @Test func markingDoneTwiceOnlyChecksOffOnce() throws {
            let context = try makeContext()
            let chore = insert("Vacuum", in: context)
            try context.save()
            let id = try #require(chore.choreID)

            let first = try CompleteChoreIntent.markDone(id, in: context, on: sundayNoon)
            #expect(first.didCheckOff)
            #expect(chore.isDone(asOf: sundayNoon))

            // Siri can retry an intent; a second run must not uncheck it.
            let second = try CompleteChoreIntent.markDone(id, in: context, on: sundayNoon)
            #expect(!second.didCheckOff)
            #expect(chore.isDone(asOf: sundayNoon))
            #expect(chore.allCompletions.count == 1)
        }

        @Test func markingADeletedChoreFails() throws {
            let context = try makeContext()
            #expect(throws: ChoreIntentError.self) {
                _ = try CompleteChoreIntent.markDone(UUID(), in: context)
            }
        }

        @Test func queryFindsChoresByIDAndName() throws {
            let context = try makeContext()
            let vacuum = insert("Vacuum the living room", in: context)
            _ = insert("Laundry", sortOrder: 1, in: context)
            try context.save()

            let byID = try ChoreQuery.entities(for: [try #require(vacuum.choreID)], in: context)
            #expect(byID.map(\.name) == ["Vacuum the living room"])

            let byName = try ChoreQuery.entities(matching: "living", in: context)
            #expect(byName.map(\.name) == ["Vacuum the living room"])

            let all = try ChoreQuery.allChores(in: context).map(\.name)
            #expect(all == ["Vacuum the living room", "Laundry"])
        }

        @Test func choresWithoutAnIDGetOneAtLaunch() throws {
            let context = try makeContext()
            let old = insert("Old chore", in: context)
            old.choreID = nil
            let other = insert("Other old chore", in: context)
            other.choreID = nil
            try context.save()

            Chore.assignMissingIDs(in: context)
            #expect(old.choreID != nil)
            #expect(other.choreID != nil)
            #expect(old.choreID != other.choreID, "Each chore gets its own ID")
        }

        @Test func monthlyChecklistIncludesLongCycleChoresDueThisMonth() throws {
            let context = try makeContext()
            let bills = insert("Pay bills", .monthly, in: context)
            let dueNow = Chore(name: "Smoke detectors", frequency: .everySixMonths, sortOrder: 1,
                               nextDueDate: day(2026, 11, 20))
            let later = Chore(name: "Gutters", frequency: .yearly, sortOrder: 2,
                              nextDueDate: day(2027, 4, 1))
            let weekly = insert("Vacuum", in: context)
            context.insert(dueNow)
            context.insert(later)

            let monthly = Chore.checklist(for: .monthly, from: [bills, dueNow, later, weekly], asOf: sundayNoon)
            #expect(monthly.map(\.name) == ["Pay bills", "Smoke detectors"])

            let thisWeek = Chore.checklist(for: .weekly, from: [bills, dueNow, later, weekly], asOf: sundayNoon)
            #expect(thisWeek.map(\.name) == ["Vacuum"])
        }
    }
}
