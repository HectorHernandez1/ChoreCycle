import SwiftUI

/// A single checklist row: an animated check circle, the chore name, and a
/// subtle edit button.
struct ChoreRowView: View {
    let chore: Chore
    let isDone: Bool
    /// Optional line under the name, e.g. "Due Nov 20" for long-cycle chores.
    var detail: String? = nil
    /// Tints the detail line to draw attention to an overdue chore.
    var isOverdue: Bool = false
    /// Called with the center of the check circle (in the chore list's
    /// coordinate space) so confetti can burst from the right spot.
    let onToggle: (CGPoint) -> Void
    let onEdit: () -> Void

    /// Where the check circle currently sits on screen, kept up to date as
    /// the list scrolls.
    @State private var checkCenter = CGPoint.zero

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onToggle(checkCenter)
            } label: {
                HStack(spacing: 14) {
                    checkCircle

                    VStack(alignment: .leading, spacing: 2) {
                        Text(chore.name)
                            .font(.body.weight(.medium))
                            .strikethrough(isDone, color: .secondary)
                            .foregroundStyle(isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                            .lineLimit(2)

                        if let detail {
                            Text(detail)
                                .font(.caption.weight(isOverdue && !isDone ? .semibold : .regular))
                                .foregroundStyle(isOverdue && !isDone ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                                .contentTransition(.numericText())
                        }

                        if !chore.notes.isEmpty {
                            Label(chore.notes, systemImage: "note.text")
                                .labelStyle(NoteLabelStyle())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 0)
                }
                // Makes the empty space (the Spacer) tappable too, so a tap
                // anywhere on the row toggles the chore.
                .contentShape(.rect)
            }
            // `.plain` stops the whole row from flashing like a big button
            // and keeps the text its normal color.
            .buttonStyle(.plain)
            .accessibilityValue(isDone ? "Done" : "Not done")

            // `.borderless` lets this button receive its own taps inside a
            // List row instead of the row treating every tap as one button.
            Button("Edit \(chore.name)", systemImage: "ellipsis.circle", action: onEdit)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.tertiary)
                .font(.title3)
        }
        .padding(.vertical, 4)
        .animation(.snappy(duration: 0.3), value: isDone)
        // Long-pressing the row shows this menu.
        .contextMenu {
            Button("Edit", systemImage: "pencil", action: onEdit)
        }
    }

    /// A filled accent circle when done, an outlined ring when not. The
    /// symbol swap animates with a small bounce.
    private var checkCircle: some View {
        ZStack {
            Circle()
                .fill(isDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
                .overlay {
                    Circle()
                        .strokeBorder(isDone ? AnyShapeStyle(.clear) : AnyShapeStyle(.tertiary), lineWidth: 1.5)
                }

            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .opacity(isDone ? 1 : 0)
                .scaleEffect(isDone ? 1 : 0.4)
        }
        .frame(width: 26, height: 26)
        .symbolEffect(.bounce, value: isDone)
        .onGeometryChange(for: CGPoint.self) { proxy in
            let frame = proxy.frame(in: .named(ChoreListView.confettiSpace))
            return CGPoint(x: frame.midX, y: frame.midY)
        } action: { center in
            checkCenter = center
        }
        .accessibilityHidden(true)
    }
}

/// A small icon in front of a chore's note, aligned to its first line.
private struct NoteLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            configuration.icon
                .imageScale(.small)
                .accessibilityHidden(true)
            configuration.title
        }
    }
}

#Preview {
    List {
        ChoreRowView(
            chore: Chore(name: "Vacuum the living room", frequency: .weekly, sortOrder: 0),
            isDone: false,
            onToggle: { _ in },
            onEdit: {}
        )
        ChoreRowView(
            chore: Chore(name: "Water the plants", frequency: .weekly, sortOrder: 1,
                         notes: "Fern needs extra, cactus every other time"),
            isDone: true,
            onToggle: { _ in },
            onEdit: {}
        )
        ChoreRowView(
            chore: Chore(name: "Replace furnace filter", frequency: .everySixMonths, sortOrder: 2),
            isDone: false,
            detail: "Overdue · was due Oct 20",
            isOverdue: true,
            onToggle: { _ in },
            onEdit: {}
        )
    }
}
