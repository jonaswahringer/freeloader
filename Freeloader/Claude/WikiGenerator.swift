import Foundation
import SwiftData
import SwiftUI

// WikiGenerator — background analysis job.
//
// On import (and retroactively on launch for books missing a wiki) it walks
// the book chapter by chapter, asks Claude for a summary + glossary + key
// ideas in one structured-output call, and writes the three markdown files
// per chapter (see BookWiki for the layout). Books queue serially and
// chapters run one at a time — subscription rate limits favor a quiet
// background drip over a fan-out, and the AsyncGate in ClaudeService keeps
// a lane free for interactive calls.
//
// Graceful degradation: when Claude is unavailable (iPad, missing binary,
// logged out) books are marked `.unavailable` and nothing else happens; a
// later launch retries. Failed chapters are retried once, then skipped so
// one bad chapter can't wedge the book.

struct WikiProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case generating
        case done
        case failed(String)
        case unavailable
    }
    var completed: Int
    var total: Int
    var phase: Phase

    var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
}

/// Tunables — cheap knobs for morning review.
enum WikiTuning {
    /// Per-chapter prompt budget in words (head 70% / tail 30% when over).
    static let maxPromptWords = 9000
    /// Skip near-empty chapters (blank pages, part dividers).
    static let minChapterWords = 120
    static let model = "sonnet"
}

@MainActor
@Observable
final class WikiGenerator {
    static let shared = WikiGenerator()

    /// Per-book progress keyed by wikiID; empty for books whose wiki is
    /// already complete and untouched this launch.
    private(set) var progress: [UUID: WikiProgress] = [:]

    private var queuedOrRunning: Set<UUID> = []
    private var chain: Task<Void, Never> = Task {}

    // MARK: Entry points

    /// Kick off (or resume) wiki generation for one book. Idempotent.
    func ensureWiki(for book: Book) {
        guard ClaudeService.shared.isAvailable else {
            if let id = book.wikiID { progress[id] = incompleteProgress(book: book, wikiID: id, phase: .unavailable) }
            return
        }
        let wikiID: UUID
        if let existing = book.wikiID {
            wikiID = existing
        } else {
            wikiID = UUID()
            book.wikiID = wikiID
            try? book.modelContext?.save()
        }
        guard !queuedOrRunning.contains(wikiID) else { return }

        let snapshot = ChapterWorkSet(book: book, wikiID: wikiID)
        guard !snapshot.pending.isEmpty else {
            progress[wikiID] = nil // already complete
            return
        }
        queuedOrRunning.insert(wikiID)
        progress[wikiID] = WikiProgress(
            completed: snapshot.totalEligible - snapshot.pending.count,
            total: snapshot.totalEligible,
            phase: .generating
        )
        let work = snapshot
        chain = Task { [previous = chain] in
            await previous.value
            await Self.generate(work) { update in
                await MainActor.run { WikiGenerator.shared.apply(update, wikiID: work.wikiID) }
            }
            await MainActor.run { _ = WikiGenerator.shared.queuedOrRunning.remove(work.wikiID) }
        }
    }

    /// Retroactive pass over the whole library (call from the library view).
    func scan(books: [Book]) {
        for book in books { ensureWiki(for: book) }
    }

    func progress(for book: Book) -> WikiProgress? {
        book.wikiID.flatMap { progress[$0] }
    }

    // MARK: Internals

    private func incompleteProgress(book: Book, wikiID: UUID, phase: WikiProgress.Phase) -> WikiProgress? {
        let set = ChapterWorkSet(book: book, wikiID: wikiID)
        guard !set.pending.isEmpty else { return nil }
        return WikiProgress(completed: set.totalEligible - set.pending.count, total: set.totalEligible, phase: phase)
    }

    private func apply(_ update: GenerationUpdate, wikiID: UUID) {
        switch update {
        case .chapterDone:
            progress[wikiID]?.completed += 1
        case .finished(let failures):
            if failures == 0 {
                progress[wikiID] = nil // quiet success — the indicator just disappears
            } else {
                progress[wikiID]?.phase = .failed("\(failures) chapter(s) failed; will retry next launch")
            }
        case .aborted(let reason):
            progress[wikiID]?.phase = reason
        }
    }

    private enum GenerationUpdate: Sendable {
        case chapterDone
        case finished(failures: Int)
        case aborted(WikiProgress.Phase)
    }

    /// Plain-data snapshot so generation never touches SwiftData off-main.
    private struct ChapterWorkSet: Sendable {
        struct Item: Sendable {
            let index: Int
            let title: String
            let text: String
        }
        let wikiID: UUID
        let bookTitle: String
        let totalEligible: Int
        let pending: [Item]

        @MainActor
        init(book: Book, wikiID: UUID) {
            self.wikiID = wikiID
            self.bookTitle = book.title
            var eligible = 0
            var pending: [Item] = []
            for chapter in book.chapters.sorted(by: { $0.index < $1.index }) {
                let text = chapter.sections
                    .sorted { $0.index < $1.index }
                    .map(\.text)
                    .joined(separator: "\n\n")
                let wordCount = text.split(separator: " ", omittingEmptySubsequences: true).count
                guard wordCount >= WikiTuning.minChapterWords else { continue }
                eligible += 1
                if !BookWiki.isChapterComplete(wikiID: wikiID, chapterIndex: chapter.index) {
                    pending.append(Item(index: chapter.index, title: chapter.title, text: text))
                }
            }
            self.totalEligible = eligible
            self.pending = pending
        }
    }

    private struct ChapterWikiPayload: Codable, Sendable {
        let summary: String
        let glossary: String
        let keyIdeas: String
    }

    private nonisolated static let payloadSchema = """
    {"type":"object","properties":{"summary":{"type":"string"},"glossary":{"type":"string"},"keyIdeas":{"type":"string"}},"required":["summary","glossary","keyIdeas"],"additionalProperties":false}
    """

    private nonisolated static func generate(
        _ work: ChapterWorkSet,
        report: @escaping @Sendable (GenerationUpdate) async -> Void
    ) async {
        var manifest = BookWiki.loadManifest(wikiID: work.wikiID)
            ?? BookWiki.Manifest(bookTitle: work.bookTitle, model: WikiTuning.model)
        var failures = 0

        for item in work.pending {
            var succeeded = false
            for attempt in 0..<2 {
                do {
                    try await generateChapter(item, work: work)
                    succeeded = true
                    break
                } catch let error as ClaudeError {
                    switch error {
                    case .unavailable, .notLoggedIn:
                        await report(.aborted(.unavailable))
                        return
                    default:
                        if attempt == 1 { NSLog("Wiki generation failed for chapter \(item.index): \(error)") }
                    }
                } catch {
                    if attempt == 1 { NSLog("Wiki generation failed for chapter \(item.index): \(error)") }
                }
            }
            manifest.chapters.removeAll { $0.index == item.index }
            manifest.chapters.append(.init(
                index: item.index,
                title: item.title,
                status: succeeded ? "done" : "failed",
                generatedAt: succeeded ? .now : nil
            ))
            manifest.chapters.sort { $0.index < $1.index }
            BookWiki.saveManifest(manifest, wikiID: work.wikiID)
            if succeeded {
                await report(.chapterDone)
            } else {
                failures += 1
            }
        }
        await report(.finished(failures: failures))
    }

    private nonisolated static func generateChapter(_ item: ChapterWorkSet.Item, work: ChapterWorkSet) async throws {
        let bounded = boundedText(item.text, maxWords: WikiTuning.maxPromptWords)
        var request = ClaudeRequest(prompt: """
        Here is chapter \(item.index + 1), “\(item.title)”, of the book “\(work.bookTitle)”:

        <chapter>
        \(bounded)
        </chapter>

        Produce study notes for this chapter as three markdown bodies (no top-level heading; \
        it is added later):
        - summary: 2–4 paragraphs capturing the chapter's argument and arc.
        - glossary: the terms, names, and concepts a reader might want defined, as \
        "**Term** — definition" lines, most important first (5–20 entries; fewer if the \
        chapter is simple).
        - keyIdeas: the 3–7 ideas worth retaining, as a numbered list, each 1–2 sentences.

        Write for a reader who has just read the chapter and will use these notes for \
        recall and quick lookup. Use only the chapter text; do not invent content.
        """)
        request.systemPrompt = "You write precise, faithful study notes for books. No preamble, no meta-commentary."
        request.workingDirectory = BookWiki.directory(for: work.wikiID)
        request.allowedTools = [] // pure generation, no tools needed
        request.maxTurns = 8
        request.model = WikiTuning.model
        request.jsonSchema = payloadSchema
        request.timeout = 600

        let reply = try await ClaudeService.shared.run(request)
        let payload = try reply.decodeStructured(ChapterWikiPayload.self)
        try BookWiki.write(wikiID: work.wikiID, chapterIndex: item.index, chapterTitle: item.title, facet: .summary, body: payload.summary)
        try BookWiki.write(wikiID: work.wikiID, chapterIndex: item.index, chapterTitle: item.title, facet: .glossary, body: payload.glossary)
        try BookWiki.write(wikiID: work.wikiID, chapterIndex: item.index, chapterTitle: item.title, facet: .keyIdeas, body: payload.keyIdeas)
    }

    /// Bound huge chapters: keep the head (70%) and tail (30%) with an elision
    /// marker, since openings and closings carry most of a chapter's structure.
    nonisolated static func boundedText(_ text: String, maxWords: Int) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        guard words.count > maxWords else { return text }
        let headCount = maxWords * 7 / 10
        let tailCount = maxWords - headCount
        let head = words.prefix(headCount).joined(separator: " ")
        let tail = words.suffix(tailCount).joined(separator: " ")
        return head + "\n\n[… middle of chapter elided for length …]\n\n" + tail
    }
}
