# AGENTS.md

Guidance for coding agents working on ChoreCycle. Read this before changing code; the README covers what the app does.

## Project at a glance

- SwiftUI + SwiftData app for iPhone, iPad, and Mac (iOS 27 SDK, Swift 5 mode with Swift 6 concurrency features on). No third-party dependencies.
- One app target (`ChoreCycle`) and one test target (`ChoreCycleTests`, Swift Testing, hosted in the app).
- The owner is learning iOS development. Code comments explain *why* in plain language, often comparing to Python/SQL ideas. Keep that style and density when you add code.

## Build and test

- Prefer the Xcode MCP tools: `BuildProject` (use `buildForTesting: true` when tests changed), `RunAllTests`, `RenderPreview`, `XcodeRefreshCodeIssuesInFile`.
- All tests must pass before committing. Check the build log for new warnings too; Swift 6 isolation warnings become errors later.
- Previews: `#Preview(traits: .sampleData)` gives an in-memory database with sample chores (`Views/SampleData.swift`). For the foldable iPhone Duo, render with `previewVariantOverrides` `{"Display": "Inner"}` (wide, regular size class) and `{"Display": "Outer"}` (compact).

## Layout

| Path | What's there |
| --- | --- |
| `ChoreCycle/Models` | `Chore`, `Completion` (SwiftData), scheduling (`Chore+Period.swift`), `ChoreHistory`, `ChoreReminders`, `UserSettings`, `DeletedChore` (undo snapshot) |
| `ChoreCycle/Views` | Screens and components; `MainTabView` is the root |
| `ChoreCycle/Intents` | App Intents for Siri, Shortcuts, Spotlight |
| `ChoreCycleTests` | One file per area; shared helpers at the top of `ChoreCycleTests.swift` |

## Rules that aren't obvious from the code

### Data model (SwiftData + iCloud/CloudKit)
- Every stored property needs a default value or must be optional, and relationships must be optional. CloudKit rejects the model otherwise.
- Never add a non-optional property whose default must be unique (like a UUID): migration gives every existing row the same value. Make it optional and backfill, as `Chore.choreID` does with `assignMissingIDs(in:)`.
- Enum raw values (`Frequency`, `AccentTheme`, `AppearanceMode`, `ChecklistKind`) are persisted. Never rename or reuse them; only add cases.
- Read completions through `allCompletions` / `addCompletion(at:isSkip:)`, not the optional `completions` array.
- `sortOrder` is shared across all chores. Reordering hands a section's existing values back out (`Chore.reorder`); don't renumber from zero.

### Scheduling semantics
- A "check-off" is a `Completion`; a skip is a `Completion` with `isSkip = true`.
  - `isDone` = real check-off this period; `isSkipped` = skip only; `isHandled` = either.
  - `lastCompletion` includes skips (drives due dates); `lastDone` excludes them (for "Last done" labels).
- Weeks run Monday to Sunday (`Calendar.mondayFirst`). Use it everywhere; tests pin "now" to Sunday Nov 8, 2026 (`sundayNoon`).
- Weekly/monthly chores are calendar-aligned. Every 2 weeks, 3/6 months, and yearly are rolling (`rollingInterval`). Every 2 weeks lives on the Weekly tab; the rest on Monthly (`calendarComponent` decides).
- `Chore.checklist(for:from:asOf:)` is the single rule for "what's on this tab's checklist". Reuse it rather than re-deriving.
- Reminder timing lives in `Chore.nextReminderDate`; `ChoreReminders.sync` replaces all pending reminders. Call `sync` after anything that could move a due date.

### Concurrency
- The target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Plain value types the system touches off the main thread need `nonisolated` (see `Frequency`, `Streak`, `Color.warning`, notification constants).
- Don't put `nonisolated` on App Intent / `AppEntity` structs; it clashes with `@Parameter`/`@Property` wrappers. Their `perform()` and query methods are `@MainActor` and use `container.mainContext`.
- Write `array.map { Type($0) }`, not `array.map(Type.init)`, for main-actor initializers.

### App Intents
- The database reaches intents through `@Dependency`, registered in `MyApp.init` with `AppDependencyManager`. The system only fills `@Dependency` when *it* runs the intent, so tests call the static helpers (`CompleteChoreIntent.markDone`, `ChoreQuery.entities(...)`) instead of `perform()`.
- `ChoreEntity.id` (the chore's `choreID`) and the App Shortcut phrases are a public contract: changing them breaks saved shortcuts or voice commands.
- Intents must be idempotent: "Mark done" never unchecks.

### Tests
- Tests run inside the app, which opens one in-memory container when hosting tests (`MyApp.testContainer`). Database suites extend `DatabaseTests` (`.serialized`) and start with `makeContext()`, which wipes it. Never create a second `ModelContainer` for these models in tests.
- `StarterChores.seedIfNeeded` takes injectable `UserDefaults` / `FlagStore`; never touch real iCloud key-value storage in tests.

### Layout and accessibility
- Adapt on `horizontalSizeClass == .regular`, never on device type. Wide screens get the Checklists tab (both lists), the editor as an inspector, and two-column History.
- The chore editor is app-wide: open it via `ChoreEditorPresenter` from the environment (`editor.edit(_:)`, `editor.add(_:)`). `ChoreListView` falls back to its own sheets only when shown alone in previews.
- Contrast: accent colors and `Color.warning` were tuned to meet WCAG ratios (3:1 for icons/large text, 4.5:1 for small text). Don't swap in lighter system colors or `.tertiary` text without rechecking.
- Every control needs a VoiceOver label; decorative images are `accessibilityHidden`; sizes that sit next to text use `@ScaledMetric`.
- Xcode previews choke on `Button("…", action: storedClosure)` inside some views; use a trailing closure instead.

## Working agreements

- One feature per commit, tests passing, then `git push origin main`. End commit messages with the attribution line the harness provides.
- Keep changes scoped to the request; mention unrelated issues instead of fixing them silently.
- Features needing a paid Apple Developer account (App Groups for widgets/Control Center, settings sync) are on hold until the owner says otherwise. The bundle ID suggests a free Personal Team; device signing with the existing iCloud entitlements may need a paid team.
- Not yet verified on real devices: iCloud sync between devices, Siri phrases, reminders and their "Mark Done" button, and fold/unfold transitions.
