import Foundation
import SwiftData

// ContextAssembler — THE context-assembly convention.
//
// Every Claude feature (Define/Explain ticket 08, retention grading, …)
// builds its prompt through this type instead of ad-hoc strings. The
// convention it encodes:
//
//   1. cwd = the book's wiki directory. Wiki markdown stays ON DISK; the
//      prompt lists the available relative paths and Claude Reads only the
//      ones it needs. Only the immediate passage is inlined.
//   2. The inline excerpt is a bounded word window around the reader's
//      position (default ±350 words within the current section), wrapped in
//      <excerpt> tags, with the reader's selection (if any) in <selection>.
//   3. A shared system prompt fixes the role: reading companion for THIS
//      book, grounded in the excerpt + wiki, concise by default.
//   4. Follow-ups reuse the same AssembledContext but pass the stored
//      `session_id` to ClaudeService.ask(resume:) — the CLI threads state,
//      so follow-up prompts carry only the new question.
//
// Usage (ticket 08):
//   let ctx = ContextAssembler.assemble(book:…, chapterIndex:…, …)
//   let reply = try await ClaudeService.shared.ask("Define ‘saccade’", context: ctx)
//   // persist reply.sessionID on the DiscussionThread; follow-ups:
//   let more = try await ClaudeService.shared.ask(followUp, context: ctx, resume: sessionID)

struct AssembledContext: Sendable {
    /// The book's wiki directory (nil when the book has no wiki yet — calls
    /// still work, just without wiki grounding or a stable session scope).
    let workingDirectory: URL?
    let systemPrompt: String
    /// Book/chapter framing + wiki file inventory + inline excerpt.
    let contextBlock: String

    /// Full prompt for a question. Follow-ups on a resumed session skip the
    /// context block — the session already holds it.
    func prompt(question: String, isFollowUp: Bool = false) -> String {
        isFollowUp ? question : contextBlock + "\n\n" + question
    }
}

enum ContextAssembler {
    /// Default word radius around the reading position inlined into prompts.
    static let defaultRadius = 350

    @MainActor
    static func assemble(
        book: Book,
        chapterIndex: Int,
        sectionIndex: Int,
        wordIndex: Int? = nil,
        selection: String? = nil,
        radiusWords: Int = defaultRadius
    ) -> AssembledContext {
        let chapters = book.chapters.sorted { $0.index < $1.index }
        let chapter = chapters.first { $0.index == chapterIndex }
        let sections = chapter?.sections.sorted { $0.index < $1.index } ?? []
        let section = sections.first { $0.index == sectionIndex }

        var lines: [String] = []
        lines.append("You are helping a reader inside the book “\(book.title)”\(book.author.map { " by \($0)" } ?? "").")
        if let chapter {
            lines.append("They are currently in chapter \(chapter.index + 1), “\(chapter.title)”\(section?.title.map { ", section “\($0)”" } ?? "").")
        }

        // Wiki inventory — files Claude may Read (relative to cwd).
        var wikiDirectory: URL?
        if let wikiID = book.wikiID {
            wikiDirectory = BookWiki.directory(for: wikiID)
            let files = BookWiki.availableFiles(wikiID: wikiID)
            if files.isEmpty {
                lines.append("No wiki notes exist for this book yet; rely on the excerpt and your own knowledge.")
            } else {
                lines.append("""
                Background notes on this book are available as markdown files you can Read \
                (relative paths, one summary/glossary/key-ideas trio per chapter, numbered \
                by chapter). Read the ones relevant to the question — at minimum the current \
                chapter's — rather than guessing:
                """)
                lines.append(files.map { "- \($0)" }.joined(separator: "\n"))
            }
        }

        // Bounded inline excerpt around the reading position.
        if let section {
            let words = section.text.split(separator: " ", omittingEmptySubsequences: false)
            let center = min(max(wordIndex ?? 0, 0), max(words.count - 1, 0))
            let lo = max(0, center - radiusWords)
            let hi = min(words.count, center + radiusWords)
            var excerpt = words[lo..<hi].joined(separator: " ")
            if lo > 0 { excerpt = "… " + excerpt }
            if hi < words.count { excerpt += " …" }
            lines.append("The passage around the reader's position:\n<excerpt>\n\(excerpt)\n</excerpt>")
        }

        if let selection, !selection.isEmpty {
            lines.append("The reader selected this text:\n<selection>\(selection)</selection>")
        }

        return AssembledContext(
            workingDirectory: wikiDirectory,
            systemPrompt: Self.companionRole,
            contextBlock: lines.joined(separator: "\n\n")
        )
    }

    static let companionRole = """
    You are Freeloader's reading companion: a calm, precise explainer living \
    inside a reading app for easily-distracted readers. Ground every answer in \
    the provided excerpt and the book's wiki notes; say so plainly when the book \
    doesn't cover something. Default to 2–5 sentences — the reader wants to get \
    back to the page. Never use markdown headings; plain prose (a short list is \
    fine when defining multiple senses of a term).
    """
}
