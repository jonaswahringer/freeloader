import SwiftUI

// The little amber affordance that surfaces when the reader selects words
// on the page (ticket 08). Two actions for now; ticket 10 adds `.note` as a
// third item — the enum and the pill layout leave room for it.

enum SelectionAction {
    case define
    case explain
    // case note — ticket 10
    /// Tap-away / escape: clear the selection without acting on it.
    case dismiss
}

struct SelectionMenu: View {
    let scheme: ColorScheme
    let onAction: (SelectionAction) -> Void

    var body: some View {
        HStack(spacing: 0) {
            item("character.book.closed", "Define", .define)
            divider
            item("sparkles", "Explain", .explain)
        }
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(ReadingPalette.brand(scheme).opacity(0.35)))
        .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.15), radius: 12, y: 4)
    }

    private var divider: some View {
        Rectangle()
            .fill(ReadingPalette.brand(scheme).opacity(0.25))
            .frame(width: 1, height: 15)
    }

    private func item(
        _ symbol: String, _ label: String, _ action: SelectionAction
    ) -> some View {
        Button {
            onAction(action)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(label)
                    .font(.system(size: 12.5, weight: .semibold, design: .serif))
            }
            .foregroundStyle(ReadingPalette.brand(scheme))
            .padding(.horizontal, 13)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
    }
}
