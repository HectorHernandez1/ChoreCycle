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

    /// Replaces all pending reminders with one per long-cycle chore whose
    /// due date is still ahead of us. Does nothing (beyond clearing) when
    /// reminders are turned off or not permitted.
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
        for chore in chores where chore.hasReminder {
            // `nextReminderDate` decides when (or whether) to fire; see the
            // rules there.
            guard let fireDate = chore.nextReminderDate(after: now, hour: fireHour, calendar: calendar)
            else { continue }
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)

            let content = UNMutableNotificationContent()
            content.title = chore.name
            content.body = "Due today. Repeats \(chore.frequency.title.lowercased())."
            content.sound = .default

            // Identifiers only need to be unique within this batch, since
            // the whole batch is replaced on every sync.
            let request = UNNotificationRequest(
                identifier: identifierPrefix + UUID().uuidString,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }
}
