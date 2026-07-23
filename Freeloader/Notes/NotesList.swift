import SwiftUI
import SwiftData

// Per-book notes list (ticket 10): a quiet popover of anchored notes —
// the marked passage in serif quotes, the reader's thought (or the saved
// answer) beneath it. Tapping a note jumps the reading view back to its
// passage; right-click deletes. Mirrors the discussions history language.

struct NotesList: View {
    @Environment(\.colorScheme) private var scheme

    let notes: [Note]
    /// Chapter titles by index, for the little location line.
    let chapterTitles: [Int: String]
    let onOpen: (Note) -> Void
    let onDelete: (Note) -> Void

    var body: some View {
        if notes.isEmpty {
            VStack(spacing: 9) {
                Image(systemName: "bookmark")
                    .font(.system(size: 22))
                    .foregroundStyle(.tertiary)
                Text("No notes yet")
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                Text("Select a passage and choose Note,\nor save an answer from a discussion.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(26)
            .frame(width: 300)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(notes) { note in
                        row(note)
                    }
                }
                .padding(8)
            }
            .frame(width: 340)
            .frame(maxHeight: 420)
        }
    }

    private func row(_ note: Note) -> some View {
        Button {
            onOpen(note)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: note.source == "thread" ? "bubble.left" : "bookmark.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(ReadingPalette.brand(scheme))
                    Text(location(of: note))
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(ReadingPalette.brand(scheme))
                        .lineLimit(1)
                    Spacer()
                    Text(note.createdAt, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let excerpt = note.anchoredText, !excerpt.isEmpty {
                    Text("“\(excerpt)”")
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .lineLimit(2)
                }
                if !note.text.isEmpty {
                    Text(note.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("Jump to this passage")
        .contextMenu {
            Button("Delete Note", role: .destructive) { onDelete(note) }
        }
    }

    private func location(of note: Note) -> String {
        guard let index = note.chapterIndex else { return "NOTE" }
        return (chapterTitles[index] ?? "Chapter \(index + 1)").uppercased()
    }
}
