import Foundation
import SwiftData

// Initial model stubs — fields will grow as the PDF pipeline (ticket 06) and
// later features firm up their needs.

@Model
final class Book {
    var title: String
    var author: String?
    var addedAt: Date
    var sourceFileName: String?
    /// Stable key for the book's on-disk wiki directory (assigned lazily so
    /// books imported before this field existed migrate cleanly).
    var wikiID: UUID?
    @Relationship(deleteRule: .cascade, inverse: \Chapter.book)
    var chapters: [Chapter] = []
    @Relationship(deleteRule: .cascade, inverse: \ReadingPosition.book)
    var readingPosition: ReadingPosition?
    @Relationship(deleteRule: .cascade, inverse: \DiscussionThread.book)
    var threads: [DiscussionThread] = []
    @Relationship(deleteRule: .cascade, inverse: \Note.book)
    var notes: [Note] = []

    init(title: String, author: String? = nil, addedAt: Date = .now, sourceFileName: String? = nil) {
        self.title = title
        self.author = author
        self.addedAt = addedAt
        self.sourceFileName = sourceFileName
    }
}

@Model
final class Chapter {
    var index: Int
    var title: String
    var book: Book?
    @Relationship(deleteRule: .cascade, inverse: \BookSection.chapter)
    var sections: [BookSection] = []

    init(index: Int, title: String) {
        self.index = index
        self.title = title
    }
}

// Named BookSection to avoid clashing with SwiftUI.Section.
@Model
final class BookSection {
    var index: Int
    var title: String?
    var text: String
    var chapter: Chapter?

    init(index: Int, title: String? = nil, text: String) {
        self.index = index
        self.title = title
        self.text = text
    }
}

@Model
final class ReadingPosition {
    var chapterIndex: Int
    var sectionIndex: Int
    var wordIndex: Int
    var wordsPerMinute: Int
    var updatedAt: Date
    var book: Book?

    init(chapterIndex: Int = 0, sectionIndex: Int = 0, wordIndex: Int = 0, wordsPerMinute: Int = 250, updatedAt: Date = .now) {
        self.chapterIndex = chapterIndex
        self.sectionIndex = sectionIndex
        self.wordIndex = wordIndex
        self.wordsPerMinute = wordsPerMinute
        self.updatedAt = updatedAt
    }
}

// Named DiscussionThread to avoid clashing with Foundation.Thread.
@Model
final class DiscussionThread {
    var createdAt: Date
    var selectedText: String
    var kind: String // "define" | "explain"
    /// Latest Claude CLI session id — follow-ups thread via `--resume`.
    /// (Optional: pre-existing stores migrate cleanly; a lost session just
    /// means the next follow-up re-sends the context block.)
    var sessionID: String?
    /// Where in the book the selection was made (for context re-assembly on
    /// reopened threads, and jump-back later). All optional for migration.
    var chapterIndex: Int?
    var sectionIndex: Int?
    /// Word index *within the section* (ContextAssembler convention).
    var wordIndex: Int?
    var book: Book?
    @Relationship(deleteRule: .cascade, inverse: \ThreadMessage.thread)
    var messages: [ThreadMessage] = []

    init(createdAt: Date = .now, selectedText: String, kind: String) {
        self.createdAt = createdAt
        self.selectedText = selectedText
        self.kind = kind
    }
}

@Model
final class ThreadMessage {
    var createdAt: Date
    var role: String // "user" | "assistant"
    var text: String
    var thread: DiscussionThread?

    init(createdAt: Date = .now, role: String, text: String) {
        self.createdAt = createdAt
        self.role = role
        self.text = text
    }
}

@Model
final class Note {
    var createdAt: Date
    /// The passage the note is anchored to (display excerpt + fallback).
    var anchoredText: String?
    /// Anchor: chapter + section + word offset *within the section* + word
    /// count (same convention as DiscussionThread / ContextAssembler).
    /// Layout-independent, so it survives restarts, resizes, and font
    /// changes. All optional for store migration.
    var chapterIndex: Int?
    var sectionIndex: Int?
    var wordIndex: Int?
    var wordLength: Int?
    /// "selection" (Note action on the page) | "thread" (saved from a
    /// Define/Explain answer).
    var source: String?
    /// The reader's own thought (may be empty for a bare highlight), or the
    /// saved answer text for thread-sourced notes.
    var text: String
    var book: Book?

    init(createdAt: Date = .now, anchoredText: String? = nil, chapterIndex: Int? = nil, sectionIndex: Int? = nil, wordIndex: Int? = nil, wordLength: Int? = nil, source: String? = nil, text: String) {
        self.createdAt = createdAt
        self.anchoredText = anchoredText
        self.chapterIndex = chapterIndex
        self.sectionIndex = sectionIndex
        self.wordIndex = wordIndex
        self.wordLength = wordLength
        self.source = source
        self.text = text
    }
}
