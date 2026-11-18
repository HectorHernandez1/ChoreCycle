import SwiftUI
import SwiftData

/// Streaks and a week-by-week log of everything that's been checked off.
struct HistoryView: View {
    @Query(sort: [SortDescriptor(\Chore.sortOrder), SortDescriptor(\Chore.createdAt)])
    private var chores: [Chore]

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Reference date for "this week", refreshed when the app comes back.
    @State private var now = Date.now

    /// On a wide screen the stats sit in their own column on the left and
    /// stay put while the log scrolls on the right.
    private var isWide: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        NavigationStack {
            let weeks = ChoreHistory.weeks(of: chores, asOf: now)

            Group {
                if isWide {
                    HStack(spacing: 0) {
                        List {
                            statsSection(weeks: weeks)
                        }
                        .frame(width: 320)
                        Divider()
                            .ignoresSafeArea()
                        List {
                            weekSections(weeks)
                        }
                        // A list beside another view loses its leading
                        // margin; give the cards room off the divider.
                        .contentMargins(.leading, 16, for: .scrollContent)
                        .overlay { emptyState(weeks) }
                    }
                } else {
                    List {
                        statsSection(weeks: weeks)
                        weekSections(weeks)
                    }
                    .overlay { emptyState(weeks) }
                }
            }
            .navigationTitle("History")
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                now = .now
            }
        }
    }

    /// The streak and total tiles, with the footer explaining streaks.
    @ViewBuilder
    private func statsSection(weeks: [HistoryWeek]) -> some View {
        let weeklyStreak = ChoreHistory.streak(
            from: ChoreHistory.summaries(of: chores, frequency: .weekly, asOf: now))
        let monthlyStreak = ChoreHistory.streak(
            from: ChoreHistory.summaries(of: chores, frequency: .monthly, asOf: now))
        let totalDone = weeks.reduce(0) { $0 + $1.entries.filter { !$0.isSkip }.count }
        // Three side-by-side tiles get too narrow at the largest text sizes
        // and in the wide layout's narrow stats column, so they stack
        // there. `AnyLayout` switches between the two without rebuilding
        // the tiles.
        let statsLayout = dynamicTypeSize.isAccessibilitySize || isWide
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 0))

        Section {
            statsLayout {
                StatTile(value: weeklyStreak.current, unit: "week",
                         title: "Weekly Streak", best: weeklyStreak.best)
                Divider()
                StatTile(value: monthlyStreak.current, unit: "month",
                         title: "Monthly Streak", best: monthlyStreak.best)
                Divider()
                StatTile(value: totalDone, unit: nil, title: "Checked Off", best: nil)
            }
            .padding(.vertical, 6)
        } footer: {
            Text("A streak counts every week or month in which all of those chores got done.")
        }
    }

    /// One section per week, newest first.
    private func weekSections(_ weeks: [HistoryWeek]) -> some View {
        ForEach(weeks) { week in
            Section {
                ForEach(week.entries) { entry in
                    HistoryRow(entry: entry)
                }
            } header: {
                WeekHeader(week: week, isCurrent: week.period.containsExcludingEnd(now))
            }
        }
    }

    @ViewBuilder
    private func emptyState(_ weeks: [HistoryWeek]) -> some View {
        if weeks.isEmpty {
            ContentUnavailableView(
                "No History Yet",
                systemImage: "clock.arrow.circlepath",
                description: Text("Chores you check off will show up here, week by week.")
            )
            // In the single-column layout, keep clear of the stats card.
            .padding(.top, isWide ? 0 : 140)
        }
    }
}

/// One number in the stats card, e.g. "3 weeks / Weekly Streak / Best 5".
private struct StatTile: View {
    let value: Int
    /// Singular unit shown after the number ("week" becomes "weeks").
    let unit: String?
    let title: String
    let best: Int?

    private var unitLabel: String? {
        unit.map { value == 1 ? $0 : $0 + "s" }
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value, format: .number)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(value > 0 && best != nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .contentTransition(.numericText())
                if let unitLabel {
                    Text(unitLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let best {
                Text("Best \(best)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}

/// Section header: the week's dates plus its weekly-chore score.
private struct WeekHeader: View {
    let week: HistoryWeek
    let isCurrent: Bool

    private var dateLabel: String {
        if isCurrent {
            return "This Week"
        }
        // The period ends at the first instant of the next week; step back
        // a second to land on Sunday.
        let lastDay = week.period.end.addingTimeInterval(-1)
        return (week.period.start..<lastDay).formatted(.interval.month(.abbreviated).day())
    }

    var body: some View {
        HStack {
            Text(dateLabel)
            Spacer()
            if let summary = week.weeklySummary {
                if summary.isComplete {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
                Text("\(summary.doneCount)/\(summary.scheduledCount) weekly")
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One check-off (or skip): the chore's name, how often it repeats, and the
/// day.
private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.choreName)
                    .foregroundStyle(entry.isSkip ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                if entry.isSkip {
                    Label("Skipped", systemImage: "forward.end")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(entry.frequency.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(entry.completedAt, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview(traits: .sampleData) {
    HistoryView()
}
