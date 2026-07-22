import SwiftUI

// Off-main-thread bionic text preparation with caching.
//
// Building the bionic AttributedString for a whole chapter is the expensive
// part of the reading view (per-word allocations across tens of thousands of
// words). This file makes it a pure, Sendable pipeline:
//
//   Chapter (SwiftData, main) → ChapterSource (value snapshot)
//        → ChapterBuilder.shared (actor, background) → BuiltChapter (cached)
//
// Cache key: (stable chapter id, font size, color scheme). Neighbor chapters
// are prefetched so chapter switches hit the cache and feel instant.
//
// NOTE for ticket 05 (pagination): BuiltParagraph carries `wordRanges`
// (character offsets into `text`) so a page/cursor model can highlight a
// single word via `highlighting(wordIndex:color:)` without rebuilding the
// paragraph, and can split paragraphs across pages by word boundary.

// MARK: - Bionic rendering (pure functions, callable off-main)

enum Bionic {
    /// Bold-prefix length for a word with `letters` significant characters.
    static func prefixCount(letters: Int) -> Int {
        switch letters {
        case ...0: 0
        case 1...3: 1
        case 4...5: 2
        case 6...8: 3
        default: Int((Double(letters) * 0.4).rounded(.up))
        }
    }

    /// Builds a bionic paragraph plus per-word character ranges.
    static func buildParagraph(
        _ paragraph: String,
        size: CGFloat,
        scheme: ColorScheme
    ) -> BuiltParagraph {
        let ink = ReadingPalette.ink(scheme)
        let faded = ReadingPalette.inkFaded(scheme)
        var result = AttributedString()
        var wordRanges: [Range<Int>] = []
        var offset = 0
        let words = paragraph.split(separator: " ", omittingEmptySubsequences: false)
        wordRanges.reserveCapacity(words.count)
        for (i, word) in words.enumerated() {
            if i > 0 {
                var gap = AttributedString(" ")
                gap.font = .system(size: size, design: .serif)
                gap.kern = size * 0.28
                result += gap
                offset += 1
            }
            let count = word.count
            wordRanges.append(offset..<(offset + count))
            result += bionicWord(String(word), size: size, ink: ink, faded: faded)
            offset += count
        }
        return BuiltParagraph(text: result, wordRanges: wordRanges)
    }

    /// Index just past the bold prefix of `word` (shared by the renderer and
    /// the pagination measurer so widths always match what is drawn).
    static func boldPrefixEnd(of word: String) -> String.Index {
        let letters = word.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }.count
        let k = prefixCount(letters: letters)
        var boldEnd = word.startIndex
        var seen = 0
        for idx in word.indices {
            if word[idx].isLetter || word[idx].isNumber { seen += 1 }
            if seen == k { boldEnd = word.index(after: idx); break }
        }
        return boldEnd
    }

    private static func bionicWord(
        _ word: String, size: CGFloat, ink: Color, faded: Color
    ) -> AttributedString {
        let boldEnd = boldPrefixEnd(of: word)

        var head = AttributedString(String(word[word.startIndex..<boldEnd]))
        head.font = .system(size: size, weight: .bold, design: .serif)
        head.foregroundColor = ink

        var tail = AttributedString(String(word[boldEnd...]))
        tail.font = .system(size: size, weight: .regular, design: .serif)
        tail.foregroundColor = faded

        return head + tail
    }
}

// MARK: - Value snapshots (Sendable; safe to hand to the actor)

/// A plain-value snapshot of one chapter, taken from SwiftData on the main
/// thread. `id` must be stable for the lifetime of the chapter content.
struct ChapterSource: Sendable, Equatable {
    struct Section: Sendable, Equatable {
        let title: String?
        let text: String
    }

    let id: String
    let kicker: String
    let title: String
    let sections: [Section]
}

struct BuiltParagraph: Sendable, Identifiable {
    // Stable enough within one BuiltChapter; paragraphs are addressed by
    // (section index, paragraph index) when precision matters.
    let id = UUID()
    let text: AttributedString
    /// Character offsets of each word inside `text` (gaps are 1 char).
    /// Used by the pacing cursor (ticket 05) to highlight without rebuilding.
    let wordRanges: [Range<Int>]

    /// Returns `text` with one word's background set — the amber cursor.
    func highlighting(wordIndex: Int, color: Color) -> AttributedString {
        guard wordRanges.indices.contains(wordIndex) else { return text }
        var copy = text
        let range = wordRanges[wordIndex]
        let chars = copy.characters
        guard let start = chars.index(
            chars.startIndex, offsetBy: range.lowerBound, limitedBy: chars.endIndex
        ), let end = chars.index(
            start, offsetBy: range.count, limitedBy: chars.endIndex
        ) else { return text }
        copy[start..<end].backgroundColor = color
        return copy
    }
}

struct BuiltSection: Sendable {
    let title: String?
    let paragraphs: [BuiltParagraph]
}

struct BuiltChapter: Sendable {
    let sourceID: String
    let kicker: String
    let title: String
    let sections: [BuiltSection]
}

// MARK: - Builder actor with LRU cache

actor ChapterBuilder {
    static let shared = ChapterBuilder()

    struct Key: Hashable {
        let chapterID: String
        let size: CGFloat
        let dark: Bool
    }

    private var cache: [Key: BuiltChapter] = [:]
    private var lru: [Key] = []
    // Holds a full slider sweep (13 sizes) of one chapter plus neighbors.
    private let capacity = 24
    private var inFlight: [Key: Task<BuiltChapter, Never>] = [:]

    func built(
        for source: ChapterSource, size: CGFloat, scheme: ColorScheme
    ) async -> BuiltChapter {
        let key = Key(chapterID: source.id, size: size, dark: scheme == .dark)
        if let hit = cache[key] {
            touch(key)
            return hit
        }
        if let task = inFlight[key] {
            return await task.value
        }
        let task = Task.detached(priority: .userInitiated) {
            Self.build(source: source, size: size, scheme: scheme)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        store(result, at: key)
        return result
    }

    /// Warm the cache (e.g. adjacent chapters) without blocking anyone.
    func prefetch(_ source: ChapterSource, size: CGFloat, scheme: ColorScheme) async {
        _ = await built(for: source, size: size, scheme: scheme)
    }

    private func store(_ chapter: BuiltChapter, at key: Key) {
        cache[key] = chapter
        touch(key)
        while lru.count > capacity, let oldest = lru.first {
            lru.removeFirst()
            cache[oldest] = nil
        }
    }

    private func touch(_ key: Key) {
        if let i = lru.firstIndex(of: key) { lru.remove(at: i) }
        lru.append(key)
    }

    // Pure build; runs on a background executor via Task.detached.
    private static func build(
        source: ChapterSource, size: CGFloat, scheme: ColorScheme
    ) -> BuiltChapter {
        let sections = source.sections.map { section in
            BuiltSection(
                title: section.title,
                paragraphs: section.text
                    .components(separatedBy: "\n\n")
                    .filter { !$0.isEmpty }
                    .map { Bionic.buildParagraph($0, size: size, scheme: scheme) }
            )
        }
        return BuiltChapter(
            sourceID: source.id,
            kicker: source.kicker,
            title: source.title,
            sections: sections
        )
    }
}
