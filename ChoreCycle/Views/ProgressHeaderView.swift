import SwiftUI

/// The card at the top of each checklist: a progress ring, a "3 of 7 done"
/// summary, and the date range of the current week or month.
struct ProgressHeaderView: View {
    let frequency: Frequency
    let doneCount: Int
    let totalCount: Int
    /// The reference date used to work out the current period.
    let now: Date

    private var isAllDone: Bool {
        totalCount > 0 && doneCount == totalCount
    }

    /// 0...1 fraction of chores finished, used by the ring.
    private var progress: Double {
        totalCount == 0 ? 0 : Double(doneCount) / Double(totalCount)
    }

    /// "Nov 3 – Nov 9" for weeks, "November 2026" for months.
    private var periodLabel: String {
        let period = frequency.period(containing: now)
        switch frequency {
        case .weekly:
            // The interval's end is the first instant of next week, so step
            // back a second to land on the last day of this week.
            let lastDay = period.end.addingTimeInterval(-1)
            return (period.start..<lastDay).formatted(.interval.month(.abbreviated).day())
        case .monthly, .everyThreeMonths, .everySixMonths, .yearly:
            return period.start.formatted(.dateTime.month(.wide).year())
        }
    }

    private var headline: String {
        if totalCount == 0 {
            return "Nothing scheduled"
        }
        return isAllDone ? "All done!" : "\(totalCount - doneCount) left"
    }

    private var detail: String {
        totalCount == 0 ? "Add a chore to get started" : "\(doneCount) of \(totalCount) done"
    }

    var body: some View {
        HStack(spacing: 16) {
            // A native circular gauge gives us the progress ring for free,
            // including Dynamic Type and dark-mode handling.
            Gauge(value: progress) {
                EmptyView()
            } currentValueLabel: {
                if isAllDone {
                    Image(systemName: "checkmark")
                        .fontWeight(.bold)
                        .foregroundStyle(.tint)
                } else {
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .fontWeight(.semibold)
                        .contentTransition(.numericText())
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(.accentColor)
            .scaleEffect(1.15)
            .padding(4)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.title3.weight(.semibold))
                    .contentTransition(.numericText())
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Text(periodLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .animation(.snappy, value: doneCount)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headline). \(detail). \(periodLabel)")
    }
}

#Preview {
    List {
        ProgressHeaderView(frequency: .weekly, doneCount: 2, totalCount: 5, now: .now)
        ProgressHeaderView(frequency: .monthly, doneCount: 3, totalCount: 3, now: .now)
        ProgressHeaderView(frequency: .weekly, doneCount: 0, totalCount: 0, now: .now)
    }
}
