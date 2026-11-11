import Testing
import Foundation
import SwiftData
@testable import ChoreCycle

/// A `UserDefaults` suite that exists only for one test and is wiped after.
private func makeIsolatedDefaults() -> (UserDefaults, cleanup: () -> Void) {
    let suiteName = "ChoreCycleTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return (defaults, { defaults.removePersistentDomain(forName: suiteName) })
}

@MainActor
struct UserSettingsTests {
    @Test func freshInstallDefaults() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        let settings = UserSettings(defaults: defaults)

        #expect(settings.displayName == "")
        #expect(settings.accentTheme == .teal)
        #expect(settings.appearance == .system)
        #expect(settings.celebrationsEnabled)
        #expect(settings.remindersEnabled)
    }

    @Test func changesSurviveARelaunch() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }

        let first = UserSettings(defaults: defaults)
        first.displayName = "Hector"
        first.accentTheme = .purple
        first.appearance = .dark
        first.celebrationsEnabled = false
        first.remindersEnabled = false

        // A second instance over the same store stands in for a relaunch.
        let second = UserSettings(defaults: defaults)
        #expect(second.displayName == "Hector")
        #expect(second.accentTheme == .purple)
        #expect(second.appearance == .dark)
        #expect(!second.celebrationsEnabled)
        #expect(!second.remindersEnabled)
    }

    @Test func unknownStoredValuesFallBackToDefaults() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        defaults.set("neon", forKey: "accentTheme")
        defaults.set("sepia", forKey: "appearance")

        let settings = UserSettings(defaults: defaults)
        #expect(settings.accentTheme == .teal)
        #expect(settings.appearance == .system)
    }

    @Test func initialsComeFromTheFirstTwoWords() {
        let (defaults, cleanup) = makeIsolatedDefaults()
        defer { cleanup() }
        let settings = UserSettings(defaults: defaults)

        settings.displayName = "Hector Hernandez"
        #expect(settings.initials == "HH")

        settings.displayName = "hector"
        #expect(settings.initials == "H")

        settings.displayName = "Ana Maria Lopez"
        #expect(settings.initials == "AM")

        settings.displayName = ""
        #expect(settings.initials == "")
    }

    @Test func everyAccentThemeHasAUniqueStableRawValue() {
        let rawValues = AccentTheme.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
        #expect(AccentTheme(rawValue: "teal") == .teal)
        #expect(AccentTheme(rawValue: "graphite") == .graphite)
    }
}

extension DatabaseTests {
    @MainActor
    struct StarterChoresTests {
        @Test func seedsOnceIntoAnEmptyDatabase() throws {
            let (defaults, cleanup) = makeIsolatedDefaults()
            defer { cleanup() }
            let (cloud, cleanupCloud) = makeIsolatedDefaults()
            defer { cleanupCloud() }
            let context = try makeContext()

            StarterChores.seedIfNeeded(into: context, defaults: defaults, cloud: cloud)
            let afterFirst = try context.fetchCount(FetchDescriptor<Chore>())
            #expect(afterFirst == StarterChores.weekly.count + StarterChores.monthly.count)

            StarterChores.seedIfNeeded(into: context, defaults: defaults, cloud: cloud)
            let afterSecond = try context.fetchCount(FetchDescriptor<Chore>())
            #expect(afterSecond == afterFirst, "Seeding is a one-time event")
        }

        @Test func doesNotReseedAfterTheUserDeletesEverything() throws {
            let (defaults, cleanup) = makeIsolatedDefaults()
            defer { cleanup() }
            let (cloud, cleanupCloud) = makeIsolatedDefaults()
            defer { cleanupCloud() }
            let context = try makeContext()

            StarterChores.seedIfNeeded(into: context, defaults: defaults, cloud: cloud)
            for chore in try context.fetch(FetchDescriptor<Chore>()) {
                context.delete(chore)
            }
            try context.save()

            StarterChores.seedIfNeeded(into: context, defaults: defaults, cloud: cloud)
            #expect(try context.fetchCount(FetchDescriptor<Chore>()) == 0)
        }

        @Test func doesNotSeedOnASecondDeviceThatAlreadySeededViaICloud() throws {
            let (defaults, cleanup) = makeIsolatedDefaults()
            defer { cleanup() }
            let (cloud, cleanupCloud) = makeIsolatedDefaults()
            defer { cleanupCloud() }
            let context = try makeContext()

            // Another device already seeded and synced the flag.
            cloud.set(true, forKey: "didSeedStarterChores")

            StarterChores.seedIfNeeded(into: context, defaults: defaults, cloud: cloud)
            #expect(try context.fetchCount(FetchDescriptor<Chore>()) == 0)
            #expect(defaults.bool(forKey: "didSeedStarterChores"), "The flag is copied locally")
        }

        @Test func copiesALocalSeedFlagUpToICloud() throws {
            let (defaults, cleanup) = makeIsolatedDefaults()
            defer { cleanup() }
            let (cloud, cleanupCloud) = makeIsolatedDefaults()
            defer { cleanupCloud() }
            let context = try makeContext()

            // This device seeded before iCloud sync existed.
            defaults.set(true, forKey: "didSeedStarterChores")

            StarterChores.seedIfNeeded(into: context, defaults: defaults, cloud: cloud)
            #expect(cloud.bool(forKey: "didSeedStarterChores"))
        }

        @Test func starterChoresAreAllCalendarAligned() throws {
            let context = try makeContext()
            StarterChores.insert(into: context)
            let chores = try context.fetch(FetchDescriptor<Chore>())
            #expect(chores.allSatisfy { $0.frequency.isCalendarAligned })
            #expect(chores.allSatisfy { $0.nextDueDate == nil })
        }
    }
}
