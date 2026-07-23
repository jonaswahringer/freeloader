import SwiftUI
import CoreText

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// Pagination engine (ticket 05).
//
// Takes a BuiltChapter (ticket 12's cached bionic paragraphs) and lays it out
// into fixed pages sized to the view. Words are measured with CoreText using
// the same serif fonts SwiftUI draws with, then positioned absolutely — the
// page view renders each word as its own Text at a computed frame. That is
// what makes the Dock-style magnification cheap: the cursor scales words
// visually (scaleEffect) without ever reflowing text, and word frames double
// as hit-test targets for click-to-jump.
//
//   BuiltChapter ──(Paginator actor, off-main, LRU cache)──▶ PaginatedChapter
//     pages: [BuiltPage]  ·  flat word list with frames, pacing weights,
//     section indices (for ReadingPosition persistence)

// MARK: - Tunables

/// Dock-style magnification. The current word scales to `maxScale`; same-line
/// neighbors swell with a raised-cosine falloff over `radius` words.
enum MagnifierTunables {
    /// Scale of the word under the cursor. 1.0 disables magnification.
    static let maxScale: CGFloat = 1.24
    /// Falloff radius in words (neighbors within this distance swell).
    static let radius: Double = 2.6
    /// Scale anchor: x centered, y near the baseline so words grow upward
    /// out of the line, like Dock icons growing off the shelf.
    static let anchor = UnitPoint(x: 0.5, y: 0.82)
    /// Extra ink opacity boost for the magnified word (0 = none).
    static let highlightPadding = CGSize(width: 10, height: 4)
    /// Fraction of the swollen words' extra width that same-line neighbors
    /// are pushed outward by (Dock push-apart). 1 = exact no-overlap
    /// compensation, 0 = words bleed into each other when magnified.
    static let pushApart: CGFloat = 1.0

    /// Raised-cosine falloff: 1 at distance 0 → 0 at `radius`.
    static func scale(distance: Double) -> CGFloat {
        guard distance < radius else { return 1 }
        let t = cos((distance / radius) * .pi / 2)
        return 1 + (maxScale - 1) * CGFloat(t * t)
    }
}

/// Word-by-word pacing. The interval for a word is (60 / WPM) × weight,
/// where weight ≈ 1 for a typical 5-letter word and grows with length and
/// trailing punctuation. Guides, never forces: the reader can pause, scrub,
/// or click any word at any time.
enum PacingTunables {
    static let range: ClosedRange<Double> = 100...600
    /// Flat share of the interval every word gets regardless of length.
    static let baseShare = 0.55
    /// Additional weight per significant letter (5-letter word ≈ 1.0 total).
    static let perLetter = 0.09
    /// Extra beats after clause punctuation (, ; : — parentheses).
    static let clauseBonus = 0.45
    /// Extra beats after sentence punctuation (. ! ? …).
    static let sentenceBonus = 1.1
    /// Extra beat at a paragraph's last word — "patient at the joints".
    static let paragraphBonus = 0.7
    static let minWeight = 0.6
    static let maxWeight = 3.6

    static func weight(word: String, isParagraphEnd: Bool) -> Double {
        let letters = word.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }.count
        var w = baseShare + perLetter * Double(letters)
        if let last = word.unicodeScalars.reversed().first(where: {
            !CharacterSet(charactersIn: "\"')]»’”").contains($0)
        }) {
            if CharacterSet(charactersIn: ".!?…").contains(last) {
                w += sentenceBonus
            } else if CharacterSet(charactersIn: ",;:—–)").contains(last) {
                w += clauseBonus
            }
        }
        if isParagraphEnd { w += paragraphBonus }
        return min(max(w, minWeight), maxWeight)
    }

    static func interval(weight: Double, wpm: Double) -> Double {
        (60.0 / max(wpm, 40)) * weight
    }
}

/// Motion tokens for the reading experience (see /ios-animations).
enum ReadingMotion {
    /// Cursor hop + magnification swell: one spring covers both.
    static let cursor = Animation.smooth(duration: 0.26)
    /// Page drift-fade on turn.
    static let pageTurn = Animation.smooth(duration: 0.32)
    /// Chrome show/hide.
    static let controls = Animation.snappy(duration: 0.2)
}

// MARK: - Page models (Sendable snapshots)

struct PageWord: Sendable, Identifiable {
    /// Global word index within the chapter (== index in `PaginatedChapter.words`).
    let id: Int
    let text: AttributedString
    let plain: String
    /// Frame in page coordinates (origin at the page's top-leading corner).
    let frame: CGRect
    /// Line number within the page — magnification falloff stays on one line.
    let line: Int
    let sectionIndex: Int
    /// Precomputed pacing weight (length + punctuation + paragraph joint).
    let pacingWeight: Double
}

struct PageBlock: Sendable, Identifiable {
    enum Kind: Sendable {
        case kicker(String)
        case chapterTitle(String)
        case sectionTitle(String)
    }
    let id: Int
    let kind: Kind
    let frame: CGRect
}

struct BuiltPage: Sendable, Identifiable {
    let id: Int                 // page index
    let wordRange: Range<Int>   // into PaginatedChapter.words
    let blocks: [PageBlock]
}

struct PaginatedChapter: Sendable {
    let chapterID: String
    /// The layout spec these pages were built for — the view must render
    /// with this (not the current spec) so frames always match.
    let spec: PageLayoutSpec
    let pages: [BuiltPage]
    let words: [PageWord]
    /// pageOfWord[globalWordIndex] = page index.
    let pageOfWord: [Int]

    var wordCount: Int { words.count }

    func pageIndex(ofWord index: Int) -> Int {
        guard pageOfWord.indices.contains(index) else { return 0 }
        return pageOfWord[index]
    }
}

// MARK: - Layout spec

struct PageLayoutSpec: Hashable, Sendable {
    var fontSize: CGFloat
    var columnWidth: CGFloat
    var pageHeight: CGFloat
    var dark: Bool

    var lineSpacing: CGFloat { fontSize * 0.58 }
    var paragraphSpacing: CGFloat { lineSpacing * 1.6 }
    /// Word gap: matches the reading view's wide-gap language
    /// (space width is measured; kern 0.28×size added on top).
    var extraKern: CGFloat { fontSize * 0.28 }
}

// MARK: - Paginator actor

actor Paginator {
    static let shared = Paginator()

    private struct Key: Hashable {
        let chapterID: String
        let spec: PageLayoutSpec
    }

    private var cache: [Key: PaginatedChapter] = [:]
    private var lru: [Key] = []
    private let capacity = 6

    func paginate(_ chapter: BuiltChapter, spec: PageLayoutSpec) async -> PaginatedChapter {
        let key = Key(chapterID: chapter.sourceID, spec: spec)
        if let hit = cache[key] {
            touch(key)
            return hit
        }
        let result = await Task.detached(priority: .userInitiated) {
            Self.build(chapter, spec: spec)
        }.value
        cache[key] = result
        touch(key)
        while lru.count > capacity, let oldest = lru.first {
            lru.removeFirst()
            cache[oldest] = nil
        }
        return result
    }

    private func touch(_ key: Key) {
        if let i = lru.firstIndex(of: key) { lru.remove(at: i) }
        lru.append(key)
    }

    // MARK: Font helpers (CoreText; same New York serif SwiftUI draws)

    #if os(macOS)
    private static func serifFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let sys = NSFont.systemFont(ofSize: size, weight: weight)
        guard let desc = sys.fontDescriptor.withDesign(.serif),
              let serif = NSFont(descriptor: desc, size: size) else { return sys }
        return serif
    }
    #else
    private static func serifFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let sys = UIFont.systemFont(ofSize: size, weight: weight)
        guard let desc = sys.fontDescriptor.withDesign(.serif) else { return sys }
        return UIFont(descriptor: desc, size: size)
    }
    #endif

    private static func lineWidth(_ attr: NSAttributedString) -> CGFloat {
        let line = CTLineCreateWithAttributedString(attr)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private static func wrappedHeight(_ attr: NSAttributedString, width: CGFloat) -> CGFloat {
        let setter = CTFramesetterCreateWithAttributedString(attr)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            setter, CFRange(location: 0, length: 0), nil,
            CGSize(width: width, height: .greatestFiniteMagnitude), nil
        )
        return ceil(size.height)
    }

    // MARK: The layout pass (pure; runs detached off-main)

    private static func build(_ chapter: BuiltChapter, spec: PageLayoutSpec) -> PaginatedChapter {
        let bold = serifFont(size: spec.fontSize, weight: .bold)
        let regular = serifFont(size: spec.fontSize, weight: .regular)

        // ascender is positive, descender negative on both platforms.
        let lineHeight = ceil(regular.ascender - regular.descender)
        let lineAdvance = lineHeight + spec.lineSpacing

        // NSAttributedString.Key.font ("NSFont") is what CoreText reads too.
        let spaceWidth = lineWidth(NSAttributedString(
            string: " ", attributes: [.font: regular]
        ))
        let gap = spaceWidth + spec.extraKern

        var widthCache: [String: CGFloat] = [:]
        func measure(_ word: String) -> CGFloat {
            if let w = widthCache[word] { return w }
            let attr = NSMutableAttributedString(
                string: word,
                attributes: [.font: regular]
            )
            let boldEnd = Bionic.boldPrefixEnd(of: word)
            let boldRange = NSRange(word.startIndex..<boldEnd, in: word)
            if boldRange.length > 0 {
                attr.addAttribute(.font, value: bold, range: boldRange)
            }
            let w = lineWidth(attr)
            widthCache[word] = w
            return w
        }

        // Header / title metrics (measured with the fonts the view uses).
        let titleFont = serifFont(size: spec.fontSize * 1.9, weight: .bold)
        let sectionFont = serifFont(size: spec.fontSize * 1.25, weight: .semibold)
        let kickerHeight: CGFloat = 16

        var words: [PageWord] = []
        var pageOfWord: [Int] = []
        var pages: [BuiltPage] = []

        // Per-page assembly state.
        var pageStartWord = 0
        var blocks: [PageBlock] = []
        var blockID = 0
        var y: CGFloat = 0

        func closePage() {
            pages.append(BuiltPage(
                id: pages.count,
                wordRange: pageStartWord..<words.count,
                blocks: blocks
            ))
            pageStartWord = words.count
            blocks = []
            y = 0
        }

        /// Ensures at least `needed` points remain on the current page.
        func ensureRoom(_ needed: CGFloat) {
            if y + needed > spec.pageHeight, y > 0 { closePage() }
        }

        // Chapter header on page 0.
        blocks.append(PageBlock(
            id: blockID, kind: .kicker(chapter.kicker),
            frame: CGRect(x: 0, y: y, width: spec.columnWidth, height: kickerHeight)
        ))
        blockID += 1
        y += kickerHeight + 14
        let titleHeight = wrappedHeight(
            NSAttributedString(string: chapter.title, attributes: [.font: titleFont]),
            width: spec.columnWidth
        ) + 6
        blocks.append(PageBlock(
            id: blockID, kind: .chapterTitle(chapter.title),
            frame: CGRect(x: 0, y: y, width: spec.columnWidth, height: titleHeight)
        ))
        blockID += 1
        y += titleHeight + spec.lineSpacing * 2

        for (sectionIndex, section) in chapter.sections.enumerated() {
            if let title = section.title {
                let h = wrappedHeight(
                    NSAttributedString(string: title, attributes: [.font: sectionFont]),
                    width: spec.columnWidth
                ) + 4
                // A section title never strands at a page bottom: it needs
                // room for itself plus one line of text.
                ensureRoom(h + spec.lineSpacing + lineAdvance)
                if y > 0 { y += spec.lineSpacing }
                blocks.append(PageBlock(
                    id: blockID, kind: .sectionTitle(title),
                    frame: CGRect(x: 0, y: y, width: spec.columnWidth, height: h)
                ))
                blockID += 1
                y += h + spec.lineSpacing * 0.8
            }

            for paragraph in section.paragraphs {
                // Slice the built paragraph into per-word attributed runs.
                let slices = wordSlices(of: paragraph)
                guard !slices.isEmpty else { continue }

                ensureRoom(lineHeight)
                var x: CGFloat = 0
                var lineOnPage = Int((y / lineAdvance).rounded())

                for (i, slice) in slices.enumerated() {
                    let width = measure(slice.plain)
                    if x > 0, x + width > spec.columnWidth {
                        // Wrap to next line.
                        x = 0
                        y += lineAdvance
                        lineOnPage += 1
                        if y + lineHeight > spec.pageHeight {
                            closePage()
                            lineOnPage = 0
                        }
                    }
                    let isParagraphEnd = i == slices.count - 1
                    words.append(PageWord(
                        id: words.count,
                        text: slice.text,
                        plain: slice.plain,
                        frame: CGRect(x: x, y: y, width: width, height: lineHeight),
                        line: lineOnPage,
                        sectionIndex: sectionIndex,
                        pacingWeight: PacingTunables.weight(
                            word: slice.plain, isParagraphEnd: isParagraphEnd
                        )
                    ))
                    pageOfWord.append(pages.count)
                    x += width + gap
                }
                y += lineHeight + spec.paragraphSpacing
            }
        }

        closePage()

        return PaginatedChapter(
            chapterID: chapter.sourceID,
            spec: spec,
            pages: pages,
            words: words,
            pageOfWord: pageOfWord
        )
    }

    /// Splits a built paragraph into (attributed, plain) word pairs using the
    /// word ranges ticket 12 recorded — no re-attribution, just slicing.
    private static func wordSlices(
        of paragraph: BuiltParagraph
    ) -> [(text: AttributedString, plain: String)] {
        var result: [(AttributedString, String)] = []
        result.reserveCapacity(paragraph.wordRanges.count)
        let chars = paragraph.text.characters
        var cursor = chars.startIndex
        var cursorOffset = 0
        for range in paragraph.wordRanges {
            guard range.count > 0 else { continue }
            guard let start = chars.index(
                cursor, offsetBy: range.lowerBound - cursorOffset, limitedBy: chars.endIndex
            ), let end = chars.index(
                start, offsetBy: range.count, limitedBy: chars.endIndex
            ) else { break }
            cursor = start
            cursorOffset = range.lowerBound
            let sub = AttributedString(paragraph.text[start..<end])
            result.append((sub, String(chars[start..<end])))
        }
        return result
    }
}
