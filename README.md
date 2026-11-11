# ChoreCycle

ChoreCycle is a personal chore tracker for iPhone, iPad, and Mac, built with SwiftUI and SwiftData. Chores live in weekly and monthly checklists that reset automatically at the start of each new cycle, so you always know what still needs doing. This is a learning project for exploring iOS development.

## Features

- **Weekly and monthly checklists.** Weeks run Monday to Sunday. Checking a chore off records a completion rather than flipping a flag, so lists "reset" on their own when a new week or month starts and past check-offs are kept as history.
- **Long-cycle chores.** Chores that repeat every 3 months, 6 months, or yearly are due a fixed number of months after you last did them. They appear on the Monthly tab under "Due This Month" when they're due and sit in a collapsed "Upcoming" section otherwise.
- **Reminders.** Long-cycle chores get a local notification at 9 AM on their due date.
- **History.** A History tab shows weekly and monthly streaks (periods where every chore got done), your best streaks, and a week-by-week log of everything checked off.
- **Celebrations.** Confetti and haptics when you check a chore off, with a bigger burst when the whole list is done. Respects Reduce Motion.
- **Profile.** Display name, accent color, light/dark appearance, and toggles for confetti and reminders.
- **iCloud sync.** Chores and check-offs sync across devices signed in to the same Apple Account through CloudKit.

## Project layout

| Folder | Contents |
| --- | --- |
| `ChoreCycle/Models` | SwiftData models (`Chore`, `Completion`), scheduling logic, history and streaks, reminders, settings |
| `ChoreCycle/Views` | SwiftUI screens and components, plus `SampleData` for previews |
| `ChoreCycleTests` | Swift Testing unit tests for the scheduling, history, seeding, and settings logic |

## Building

Open `ChoreCycle.xcodeproj` in Xcode and run the `ChoreCycle` scheme. Run the tests with ⌘U.

iCloud sync uses the CloudKit container `iCloud.com.hectorhernandezpersonalteam.ChoreCycle`, which requires signing with a paid Apple Developer account. Tests and previews always use an in-memory database and never touch iCloud.
