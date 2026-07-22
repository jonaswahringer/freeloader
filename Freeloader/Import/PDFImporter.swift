import Foundation
import SwiftData

enum PDFImporter {
    /// Extract + structure off the main actor, then populate SwiftData models.
    @MainActor
    static func importPDF(at url: URL, into context: ModelContext) async throws -> Book {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        let structured = try await Task.detached(priority: .userInitiated) {
            let doc = try PDFExtraction.extract(url: url)
            return PDFExtraction.structure(doc, fallbackTitle: fallbackTitle)
        }.value

        let book = Book(
            title: structured.title,
            author: structured.author,
            sourceFileName: url.lastPathComponent
        )
        context.insert(book)
        for (ci, ch) in structured.chapters.enumerated() {
            let chapter = Chapter(index: ci, title: ch.title)
            chapter.sections = ch.sections.enumerated().map { si, s in
                BookSection(index: si, title: s.title, text: s.paragraphs.joined(separator: "\n\n"))
            }
            book.chapters.append(chapter)
        }
        book.readingPosition = ReadingPosition(
            chapterIndex: firstContentChapterIndex(structured)
        )
        try context.save()
        return book
    }

    /// Skip a leading "Front Matter" chapter when opening a fresh book.
    private static func firstContentChapterIndex(_ book: StructuredBook) -> Int {
        if book.chapters.count > 1, book.chapters[0].title == "Front Matter" { return 1 }
        return 0
    }
}
