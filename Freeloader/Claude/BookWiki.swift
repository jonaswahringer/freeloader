import Foundation

// BookWiki — the on-disk wiki file layout (the "internal wiki" pillar).
//
// Layout, per book (keyed by Book.wikiID):
//
//   ~/Library/Application Support/Freeloader/Wiki/<wikiID>/
//     manifest.json                    generation state (debuggability + resume)
//     chapters/
//       03-summary.md                  # <Chapter Title> — Summary
//       03-glossary.md                 # <Chapter Title> — Glossary
//       03-key-ideas.md                # <Chapter Title> — Key Ideas
//
// Chapter files are zero-padded by chapter index (2 digits). The wiki
// directory doubles as the Claude working directory, so prompts reference
// these files by *relative* path (e.g. "chapters/03-glossary.md") and the
// CLI's Read tool picks them up without inlining them into the prompt.
// Claude session storage is also scoped here (sessions are cwd-scoped).

enum BookWiki {
    enum Facet: String, CaseIterable, Sendable {
        case summary
        case glossary
        case keyIdeas = "key-ideas"

        var heading: String {
            switch self {
            case .summary: "Summary"
            case .glossary: "Glossary"
            case .keyIdeas: "Key Ideas"
            }
        }
    }

    struct Manifest: Codable, Sendable {
        struct ChapterEntry: Codable, Sendable {
            var index: Int
            var title: String
            var status: String // "done" | "failed" | "skipped"
            var generatedAt: Date?
        }
        var version: Int = 1
        var bookTitle: String
        var model: String
        var chapters: [ChapterEntry] = []
    }

    // MARK: Paths

    static func rootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Freeloader/Wiki", isDirectory: true)
    }

    static func directory(for wikiID: UUID) -> URL {
        rootDirectory().appendingPathComponent(wikiID.uuidString, isDirectory: true)
    }

    static func chaptersDirectory(for wikiID: UUID) -> URL {
        directory(for: wikiID).appendingPathComponent("chapters", isDirectory: true)
    }

    /// Relative path (from the wiki directory) of one chapter facet file.
    static func relativePath(chapterIndex: Int, facet: Facet) -> String {
        String(format: "chapters/%02d-%@.md", chapterIndex, facet.rawValue)
    }

    static func fileURL(wikiID: UUID, chapterIndex: Int, facet: Facet) -> URL {
        directory(for: wikiID).appendingPathComponent(relativePath(chapterIndex: chapterIndex, facet: facet))
    }

    // MARK: Queries

    static func isChapterComplete(wikiID: UUID, chapterIndex: Int) -> Bool {
        Facet.allCases.allSatisfy {
            FileManager.default.fileExists(
                atPath: fileURL(wikiID: wikiID, chapterIndex: chapterIndex, facet: $0).path)
        }
    }

    /// Relative paths of all existing wiki files, sorted — used by
    /// ContextAssembler to tell Claude what it may Read.
    static func availableFiles(wikiID: UUID) -> [String] {
        let dir = chaptersDirectory(for: wikiID)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasSuffix(".md") }.sorted().map { "chapters/\($0)" }
    }

    static func read(wikiID: UUID, chapterIndex: Int, facet: Facet) -> String? {
        try? String(contentsOf: fileURL(wikiID: wikiID, chapterIndex: chapterIndex, facet: facet), encoding: .utf8)
    }

    // MARK: Writes

    static func write(wikiID: UUID, chapterIndex: Int, chapterTitle: String, facet: Facet, body: String) throws {
        let url = fileURL(wikiID: wikiID, chapterIndex: chapterIndex, facet: facet)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let content = "# \(chapterTitle) — \(facet.heading)\n\n\(body)\n"
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    static func loadManifest(wikiID: UUID) -> Manifest? {
        let url = directory(for: wikiID).appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Manifest.self, from: data)
    }

    static func saveManifest(_ manifest: Manifest, wikiID: UUID) {
        let url = directory(for: wikiID).appendingPathComponent("manifest.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? encoder.encode(manifest) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func remove(wikiID: UUID) {
        try? FileManager.default.removeItem(at: directory(for: wikiID))
    }
}
