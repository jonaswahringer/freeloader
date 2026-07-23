import Foundation
import SwiftData
import Observation

// DiscussionController — state machine behind the Define/Explain modal
// (ticket 08).
//
// One controller per open modal. It owns:
// - the SwiftData DiscussionThread (created fresh from a selection, or
//   reopened from the per-book history),
// - the AssembledContext (ticket 07's convention: wiki-dir cwd + inline
//   excerpt; assembled ONCE at open — follow-ups on a resumed session skip
//   the context block because the CLI carries state),
// - the ask/answer lifecycle: thinking → answer appended → idle, or a
//   graceful failure with retry.
//
// Threading: every reply's session_id is persisted on the thread, so
// follow-ups — including ones days later from the history list — resume the
// same CLI conversation. If a resumed session turns out to be lost, the
// question is re-sent once as a fresh conversation with the full context.

@MainActor
@Observable
final class DiscussionController {
    enum Phase: Equatable {
        case idle
        case thinking
        case failed(String)
    }

    let thread: DiscussionThread
    /// False for the sample-chapter flow: the thread stays in memory only.
    let persists: Bool

    private let context: AssembledContext
    private let modelContext: ModelContext
    private(set) var phase: Phase = .idle
    /// Question awaiting an answer — kept for retry after a failure.
    private var pendingQuestion: String?
    private var task: Task<Void, Never>?

    var sortedMessages: [ThreadMessage] {
        thread.messages.sorted { $0.createdAt < $1.createdAt }
    }

    var hasMessages: Bool { !thread.messages.isEmpty }

    init(
        thread: DiscussionThread,
        context: AssembledContext,
        modelContext: ModelContext,
        persists: Bool = true
    ) {
        self.thread = thread
        self.context = context
        self.modelContext = modelContext
        self.persists = persists
    }

    /// The canned opening question. Not stored as a message — the thread's
    /// kind + selected text already encode it; the transcript starts with
    /// the answer.
    var initialQuestion: String {
        thread.kind == "define"
            ? "Define “\(thread.selectedText)” as it is used in this passage — briefly, in the book's own terms."
            : "Explain the selected passage: what is it saying, and why does it matter at this point in the book?"
    }

    /// Fires the opening Define/Explain question. Safe to call on reopened
    /// threads — it no-ops once messages exist.
    func begin() {
        guard thread.messages.isEmpty, phase == .idle else { return }
        ask(initialQuestion)
    }

    func sendFollowUp(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, phase != .thinking else { return }
        let message = ThreadMessage(role: "user", text: question)
        if persists { modelContext.insert(message) }
        message.thread = thread
        ask(question)
    }

    func retry() {
        guard case .failed = phase, let question = pendingQuestion else { return }
        ask(question)
    }

    /// Stops waiting for an in-flight reply (the CLI process winds down on
    /// its own watchdog; we just drop the result).
    func cancel() {
        task?.cancel()
        task = nil
    }

    private func ask(_ question: String) {
        pendingQuestion = question
        phase = .thinking
        let resume = thread.sessionID
        let context = self.context
        task = Task { [weak self] in
            do {
                let reply: ClaudeReply
                do {
                    reply = try await ClaudeService.shared.ask(
                        question, context: context, resume: resume
                    )
                } catch let error as ClaudeError {
                    // A stale/lost session shouldn't strand the thread —
                    // resend once as a fresh conversation with full context.
                    guard resume != nil, case .processFailed = error else { throw error }
                    reply = try await ClaudeService.shared.ask(
                        question, context: context, resume: nil
                    )
                }
                guard let self, !Task.isCancelled else { return }
                let answer = ThreadMessage(role: "assistant", text: reply.text)
                if self.persists { self.modelContext.insert(answer) }
                answer.thread = self.thread
                if let sessionID = reply.sessionID { self.thread.sessionID = sessionID }
                self.pendingQuestion = nil
                self.phase = .idle
            } catch {
                guard let self, !Task.isCancelled else { return }
                let message = (error as? ClaudeError)?.errorDescription
                    ?? error.localizedDescription
                self.phase = .failed(message)
            }
        }
    }
}
