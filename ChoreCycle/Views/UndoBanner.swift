import SwiftUI

/// A floating "Deleted Vacuum · Undo" bar shown at the bottom of a list
/// right after a delete.
struct UndoBanner: View {
    let message: String
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Undo") { onUndo() }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
            Button("Dismiss", systemImage: "xmark") { onDismiss() }
                .labelStyle(.iconOnly)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    VStack {
        Spacer()
        UndoBanner(message: "Deleted “Vacuum”", onUndo: {}, onDismiss: {})
    }
}
