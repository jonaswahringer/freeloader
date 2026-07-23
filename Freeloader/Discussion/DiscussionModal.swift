import SwiftUI
import SwiftData

// Define/Explain modal (ticket 08).
//
// 0.5s: a warm parchment card floating over the dimmed page — an amber
// DEFINE kicker, the reader's own words in serif quotes, and beneath a
// hairline, the answer settling in like a margin note.
// User: a reader who hit an unfamiliar term mid-flow; they want the answer
// and to get BACK to the page. Emotional intent: CALM — the page waits
// underneath, visibly; nothing about this feels like leaving the book.
//
// Anatomy: header (kind kicker + selected text + close) / transcript
// (answers in reading serif, follow-up questions as thin amber-barred
// asides, a three-dot thinking pulse, a quiet failure state with retry) /
// composer ("Ask a follow-up…"). Esc or tapping the scrim closes; the
// reading position underneath is untouched.

struct DiscussionModal: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let controller: DiscussionController
    let onClose: () -> Void

    @State private var draft = ""
    @State private var appeared = false
    @FocusState private var composerFocused: Bool

    private var thread: DiscussionThread { controller.thread }

    var body: some View {
        ZStack {
            ReadingPalette.scrim(scheme)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
                .opacity(appeared ? 1 : 0)

            panel
                .padding(28)
                .scaleEffect(appeared ? 1 : 0.965, anchor: .center)
                .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? .default : .smooth(duration: 0.28)) {
                appeared = true
            }
        }
        .onChange(of: controller.phase) {
            if controller.phase == .idle { composerFocused = true }
        }
    }

    // MARK: Panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 15)
            hairline
            transcript
            hairline
            composer
                .padding(14)
        }
        .frame(maxWidth: 580)
        .frame(maxHeight: 620)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(ReadingPalette.paperGlow(scheme))
                .shadow(
                    color: .black.opacity(scheme == .dark ? 0.5 : 0.2),
                    radius: 32, y: 14
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(ReadingPalette.brand(scheme).opacity(0.22))
        )
    }

    private var hairline: some View {
        Rectangle()
            .fill(ReadingPalette.brand(scheme).opacity(0.13))
            .frame(height: 1)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(thread.kind == "define" ? "DEFINE" : "EXPLAIN")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(3.2)
                    .foregroundStyle(ReadingPalette.brand(scheme))
                Text("“\(thread.selectedText)”")
                    .font(.system(size: 16, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(ReadingPalette.ink(scheme))
                    .lineLimit(3)
            }
            Spacer(minLength: 12)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ReadingPalette.inkFaded(scheme))
                    .frame(width: 27, height: 27)
                    .background(.ultraThinMaterial, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Back to reading")
        }
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(controller.sortedMessages) { message in
                        messageView(message)
                    }
                    if controller.phase == .thinking {
                        thinkingView
                            .transition(.opacity)
                    }
                    if case .failed(let message) = controller.phase {
                        failureView(message)
                            .transition(.opacity)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.smooth(duration: 0.25), value: controller.phase)
            }
            .onChange(of: controller.sortedMessages.count) {
                withAnimation(.smooth(duration: 0.25)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: controller.phase) {
                withAnimation(.smooth(duration: 0.25)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func messageView(_ message: ThreadMessage) -> some View {
        if message.role == "user" {
            // Follow-up question: a quiet aside with a thin amber bar.
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(ReadingPalette.brand(scheme).opacity(0.8))
                    .frame(width: 2)
                Text(message.text)
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(ReadingPalette.inkFaded(scheme))
                    .textSelection(.enabled)
            }
            .padding(.top, 4)
        } else {
            // Answer: the same reading serif the page uses, a size down.
            Text(message.text)
                .font(.system(size: 15.5, design: .serif))
                .lineSpacing(4.5)
                .foregroundStyle(ReadingPalette.ink(scheme))
                .textSelection(.enabled)
        }
    }

    private var thinkingView: some View {
        HStack(spacing: 10) {
            if reduceMotion {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ReadingPalette.brand(scheme))
            } else {
                PhaseAnimator([0, 1, 2]) { phase in
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(ReadingPalette.brand(scheme))
                                .frame(width: 5, height: 5)
                                .opacity(phase == i ? 1 : 0.35)
                                .offset(y: phase == i ? -2 : 0)
                        }
                    }
                } animation: { _ in .easeInOut(duration: 0.32) }
            }
            Text(thread.book?.wikiID != nil
                 ? "Consulting the book’s notes…"
                 : "Thinking…")
                .font(.system(size: 12, design: .serif))
                .italic()
                .foregroundStyle(ReadingPalette.inkFaded(scheme))
        }
        .padding(.top, controller.sortedMessages.isEmpty ? 2 : 6)
    }

    private func failureView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Couldn’t reach Claude")
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(ReadingPalette.ink(scheme))
            }
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if ClaudeService.shared.isAvailable {
                Button(action: controller.retry) {
                    Text("Try Again")
                        .font(.system(size: 12, weight: .semibold, design: .serif))
                        .foregroundStyle(ReadingPalette.brand(scheme))
                        .padding(.horizontal, 13)
                        .frame(height: 28)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(
                            ReadingPalette.brand(scheme).opacity(0.3)
                        ))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    // MARK: Composer

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && controller.phase != .thinking
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask a follow-up…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5, design: .serif))
                .foregroundStyle(ReadingPalette.ink(scheme))
                .lineLimit(1...4)
                .focused($composerFocused)
                .onSubmit(sendDraft)
            Button(action: sendDraft) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 21))
                    .foregroundStyle(
                        canSend
                            ? AnyShapeStyle(ReadingPalette.brand(scheme))
                            : AnyShapeStyle(.quaternary)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .help("Send follow-up")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(ReadingPalette.brand(scheme).opacity(0.16))
        )
    }

    private func sendDraft() {
        guard canSend else { return }
        let text = draft
        draft = ""
        controller.sendFollowUp(text)
    }
}
