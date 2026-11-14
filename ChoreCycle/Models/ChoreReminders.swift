import Foundation
import SwiftData
import UserNotifications

/// Schedules one local notification per rolling chore (every 2 weeks,
/// 3 months, 6 months, yearly) for the morning of its due date, and one per
/// weekly chore pinned to a day ("trash goes out Tuesday") for that morning.
///
/// Other weekly and monthly chores don't get reminders: they're routines
/// you see every time you open the app. Six months, though, is long enough
/// to forget the app exists.
///
/// The approach is deliberately simple: every time anything that could
/// move a due date changes (a check, an edit, a delete, the app coming to
/// the foreground), we throw away all of our pending reminders and schedule
/// the current set again. That avoids ever having a stale reminder.
enum ChoreReminders {
    /// Prefix on every request we create, so we only ever remove our own.
    private static let identifierPrefix = "chore-due."

    /// Local hour at which reminders fire.
    static let fireHour = 9

    /// Asks for notification permission if the person hasn't been asked yet.
    /// Returns whether reminders are allowed afterwards.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    /// Whether the person has explicitly turned notifications off for the
    /// app in Settings. Used to explain why the toggle has no effect.
    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// Replaces all pending reminders with one per chore whose next reminder
    /// is still ahead of us. Does nothing (beyond clearing) when reminders
    /// are turned off or not permitted.
    static func sync(in context: ModelContext,
                     enabled: Bool,
                     now: Date = .now,
                     calendar: Calendar = .mondayFirst) async {
        let center = UNUserNotificationCenter.current()

        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        guard enabled, await requestAuthorization() else { return }

        let chores = (try? context.fetch(FetchDescriptor<Chore>())) ?? []

        // A reminder already sitting in Notification Center is stale once
        // its chore has been dealt with (in the app, by Siri, or on another
        // device), so clear those too.
        let handled = Set(chores.filter { $0.isHandled(asOf: now, calendar: calendar) }
            .compactMap { $0.choreID.map(identifier(for:)) })
        let delivered = await center.deliveredNotifications().map(\.request.identifier)
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter(handled.contains))

        guard enabled, await requestAuthorization() else { return }

        for chore in chores where chore.hasReminder {
            // `nextReminderDate` decides when (or whether) to fire; see the
            // rules there.
            guard let id = chore.choreID,
                  let fireDate = chore.nextReminderDate(after: now, hour: fireHour, calendar: calendar)
            else { continue }
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)

            let request = UNNotificationRequest(
                identifier: identifier(for: id),
                content: content(for: chore, id: id),
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    // MARK: - Mark Done from the notification

    /// Identifies reminders that carry the "Mark Done" button.
    /// (`nonisolated` so the notification handler can read them on
    /// whatever thread the system calls it.)
    nonisolated static let categoryIdentifier = "CHORE_DUE"
    nonisolated static let markDoneActionIdentifier = "MARK_DONE"
    /// Key in `userInfo` holding the chore's `choreID` as a string.
    nonisolated static let choreIDKey = "choreID"

    /// One reminder per chore at a time, so the chore's ID makes a stable
    /// identifier (handy for clearing it once the chore is done).
    static func identifier(for choreID: UUID) -> String {
        identifierPrefix + choreID.uuidString
    }

    /// The notification's text plus what the "Mark Done" button needs to
    /// find the chore again.
    static func content(for chore: Chore, id: UUID) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = chore.name
        content.body = "Due today. Repeats \(chore.frequency.title.lowercased())."
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = [choreIDKey: id.uuidString]
        return content
    }

    /// Registers the "Mark Done" button. Must happen at launch, before any
    /// reminder is delivered.
    static func registerCategories() {
        // No `.foreground` option: tapping the button marks the chore done
        // in the background without opening the app.
        let markDone = UNNotificationAction(identifier: markDoneActionIdentifier,
                                            title: "Mark Done",
                                            options: [])
        let category = UNNotificationCategory(identifier: categoryIdentifier,
                                              actions: [markDone],
                                              intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

/// Receives taps on reminders: "Mark Done" checks the chore off, and while
/// the app is open, reminders still show as banners instead of being
/// silently dropped.
///
/// Notification callbacks can arrive on any thread, so the methods are
/// `nonisolated` and copy what they need out of the (non-sendable)
/// notification before hopping to the main actor to touch the database.
final class ReminderNotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == ChoreReminders.markDoneActionIdentifier,
              let idString = response.notification.request.content.userInfo[ChoreReminders.choreIDKey] as? String,
              let id = UUID(uuidString: idString)
        else { return }
        await markDone(id)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    @MainActor
    private func markDone(_ id: UUID) async {
        let context = container.mainContext
        // A chore deleted since the reminder was scheduled just does nothing.
        guard (try? CompleteChoreIntent.markDone(id, in: context)) != nil else { return }
        // Schedule this chore's next reminder.
        await ChoreReminders.sync(in: context, enabled: UserSettings().remindersEnabled)
    }
}
