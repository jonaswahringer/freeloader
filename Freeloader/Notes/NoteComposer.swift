import SwiftUI

// Note composer (ticket 10).
//
// 0.5s: a small parchment card floating over the dimmed page — an amber
// NOTE kicker, the passage the reader just marked in serif quotes, and one
// quiet field inviting a thought. User: a reader who wants to pin this
// passage and keep moving. Emotional intent: CALM — saving a note is one
// keystroke, the page waits visibly underneath, and the thought is optional
// (a bare highlight is a perfectly good note).

/// The anchor a composed note will attach to — captured from the live
/// selection when the composer opens, so the selection can't shift under it.
struct NoteDraftTarget: Equatable {
    let excerpt: String
    let chapterIndex: Int
    let sectionIndex: Int
    /// Word offset within the section (ContextAssembler convention).
    let wordIndex: Int
    let wordLength: Int
}

struct NoteComposer: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let target: NoteDraftTarget
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var thought = ""
    @State private var appeared = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack {
            ReadingPalette.scrim(scheme)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)
                .opacity(appeared ? 1 : 0)

            card
                .padding(28)
                .scaleEffect(appeared ? 1 : 0.965, anchor: .center)
                .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? .default : .smooth(duration: 0.25)) {
                appeared = true
            }
            fieldFocused = true
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("NOTE")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(3.2)
                    .foregroundStyle(ReadingPalette.brand(scheme))
                Text("“\(target.excerpt)”")
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(ReadingPalette.ink(scheme))
                    .lineLimit(3)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Rectangle()
                .fill(ReadingPalette.brand(scheme).opacity(0.13))
                .frame(height: 1)

            TextField("Add a thought (optional)…", text: $thought, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5, design: .serif))
                .foregroundStyle(ReadingPalette.ink(scheme))
                .lineLimit(1...5)
                .focused($fieldFocused)
                .onSubmit(save)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            HStack {
                Spacer()
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .semibold, design: .serif))
                        .foregroundStyle(ReadingPalette.inkFaded(scheme))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Button(action: save) {
                    HStack(spacing: 5) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Save Note")
                            .font(.system(size: 12, weight: .semibold, design: .serif))
                    }
                    .foregroundStyle(ReadingPalette.brand(scheme))
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(
                        ReadingPalette.brand(scheme).opacity(0.35)
                    ))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .help("Save note (Return)")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: 420)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ReadingPalette.paperGlow(scheme))
                .shadow(
                    color: .black.opacity(scheme == .dark ? 0.5 : 0.2),
                    radius: 28, y: 12
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ReadingPalette.brand(scheme).opacity(0.22))
        )
    }

    private func save() {
        onSave(thought.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
