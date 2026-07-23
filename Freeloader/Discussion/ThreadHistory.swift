import SwiftUI
import SwiftData

// Per-book discussion history (ticket 08): a quiet popover list of past
// Define/Explain threads. Tapping one reopens the modal on the stored
// thread — follow-ups continue the same Claude session via its persisted
// session id. Right-click deletes.

struct ThreadHistoryList: View {
    @Environment(\.colorScheme) private var scheme

    let threads: [DiscussionThread]
    let onOpen: (DiscussionThread) -> Void
    let onDelete: (DiscussionThread) -> Void

    var body: some View {
        if threads.isEmpty {
            VStack(spacing: 9) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 22))
                    .foregroundStyle(.tertiary)
                Text("No discussions yet")
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                Text("Select any passage while reading\nto define or explain it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(26)
            .frame(width: 300)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(threads) { thread in
                        row(thread)
                    }
                }
                .padding(8)
            }
            .frame(width: 340)
            .frame(maxHeight: 420)
        }
    }

    private func row(_ thread: DiscussionThread) -> some View {
        Button {
            onOpen(thread)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(thread.kind.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(ReadingPalette.brand(scheme))
                    Spacer()
                    Text(thread.createdAt, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text("“\(thread.selectedText)”")
                    .font(.system(size: 13, weight: .medium, design: .serif))
                    .lineLimit(2)
                if let answer = firstAnswer(of: thread) {
                    Text(answer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete Discussion", role: .destructive) { onDelete(thread) }
        }
    }

    private func firstAnswer(of thread: DiscussionThread) -> String? {
        thread.messages
            .sorted { $0.createdAt < $1.createdAt }
            .first { $0.role == "assistant" }?
            .text
    }
}
