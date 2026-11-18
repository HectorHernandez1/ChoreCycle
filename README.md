# ChoreCycle

ChoreCycle is a personal chore tracker for iPhone, iPad, and Mac, built with SwiftUI and SwiftData. Chores live in weekly and monthly checklists that reset automatically at the start of each new cycle, so you always know what still needs doing. This is a learning project for exploring iOS development.

## Features

- **Weekly and monthly checklists.** Weeks run Monday to Sunday. Checking a chore off records a completion rather than flipping a flag, so lists "reset" on their own when a new week or month starts and past check-offs are kept as history.
- **Long-cycle chores.** Chores that repeat every 2 weeks, 3 months, 6 months, or yearly are due a fixed interval after you last did them. Every-2-weeks chores appear on the Weekly tab, the rest on the Monthly tab, under "Due This Week/Month" when they're due and in a collapsed "Upcoming" section otherwise.
- **Pinned days.** Weekly and every-2-weeks chores can be set to a day of the week ("trash goes out Tuesday"), which shows "Due Tuesday" or "Overdue" on the row.
- **Reminders.** A local notification at 9 AM on a long-cycle chore's due date, and on the chosen day for pinned weekly chores.
- **Notes.** Each chore can carry details like a filter size, shown under its name.
- **Reorder and undo.** Drag chores into your own order; deleting a chore shows an Undo banner that restores it with its history.
- **Siri and Shortcuts.** "Mark Vacuum done in ChoreCycle" and "What's left in ChoreCycle", plus actions in the Shortcuts app.
- **History.** A History tab shows weekly and monthly streaks (periods where every chore got done), your best streaks, and a week-by-week log of everything checked off.
- **Celebrations.** Confetti and haptics when you check a chore off, with a bigger burst when the whole list is done. Respects Reduce Motion.
- **Profile.** Display name, accent color, light/dark appearance, and toggles for confetti and reminders.
- **Big screens.** On the unfolded iPhone, iPad, or a wide Mac window, This Week and This Month sit side by side, chores are edited in a side panel, History shows its stats beside the log, and the tab bar can become a sidebar. Folding back switches to the phone layout.
- **Accessibility.** Accent colors and warning text meet WCAG contrast minimums, every control has a VoiceOver label, and text and icons scale with Dynamic Type.
- **iCloud sync.** Chores and check-offs sync across devices signed in to the same Apple Account through CloudKit.

## Project layout

| Folder | Contents |
| --- | --- |
| `ChoreCycle/Models` | SwiftData models (`Chore`, `Completion`), scheduling logic, history and streaks, reminders, settings |
| `ChoreCycle/Views` | SwiftUI screens and components, plus `SampleData` for previews |
| `ChoreCycle/Intents` | App Intents for Siri, Shortcuts, and Spotlight |
| `ChoreCycleTests` | Swift Testing unit tests for the scheduling, history, seeding, and settings logic |

## Building

Open `ChoreCycle.xcodeproj` in Xcode and run the `ChoreCycle` scheme. Run the tests with ⌘U.

iCloud sync uses the CloudKit container `iCloud.com.hectorhernandezpersonalteam.ChoreCycle`, which requires signing with a paid Apple Developer account. Tests and previews always use an in-memory database and never touch iCloud.
