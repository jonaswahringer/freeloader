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
    var anchoredText: String?
    var chapterIndex: Int?
    var sectionIndex: Int?
    var text: String
    var book: Book?

    init(createdAt: Date = .now, anchoredText: String? = nil, chapterIndex: Int? = nil, sectionIndex: Int? = nil, text: String) {
        self.createdAt = createdAt
        self.anchoredText = anchoredText
        self.chapterIndex = chapterIndex
        self.sectionIndex = sectionIndex
        self.text = text
    }
}
