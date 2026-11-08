import SwiftUI

/// A single checklist row: a check circle, the chore name, and an info button.
struct ChoreRowView: View {
    let chore: Chore
    let isDone: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    // SF Symbols: Apple's built-in icon set, referenced by name.
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isDone ? Color.accentColor : Color.secondary)
                        .accessibilityHidden(true)

                    Text(chore.name)
                        .strikethrough(isDone)
                        .foregroundStyle(isDone ? Color.secondary : Color.primary)

                    Spacer()
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
            Button("Edit \(chore.name)", systemImage: "info.circle", action: onEdit)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        // Long-pressing the row shows this menu.
        .contextMenu {
            Button("Edit", systemImage: "pencil", action: onEdit)
        }
    }
}
