import Foundation
import PDFKit
#if canImport(AppKit)
import AppKit
private typealias PlatformFont = NSFont
#else
import UIKit
private typealias PlatformFont = UIFont
#endif

// Pure extraction + structuring pipeline (no SwiftUI/SwiftData) so it can be
// exercised from a command-line harness against real PDFs.
//
// Structuring is heuristics-only for now; the LLM structure pass (ticket 07)
// will refine chapter/section boundaries using the same heading candidates.

enum PDFImportError: LocalizedError {
    case cannotOpen
    case locked
    case scannedOrEmpty

    var errorDescription: String? {
        switch self {
        case .cannotOpen: "The file could not be opened as a PDF."
        case .locked: "This PDF is password-protected."
        case .scannedOrEmpty: "This PDF has no extractable text — scanned/image PDFs aren't supported."
        }
    }
}

struct ExtractedLine {
    var text: String
    var size: CGFloat
    var bold: Bool
    var mono: Bool
    var page: Int
}

struct ExtractedDocument {
    var title: String?
    var author: String?
    var pageCount: Int
    var lines: [ExtractedLine]
}

struct StructuredSection {
    var title: String?
    var paragraphs: [String]
}

struct StructuredChapter {
    var title: String
    var sections: [StructuredSection]
}

struct StructuredBook {
    var title: String
    var author: String?
    var chapters: [StructuredChapter]
    var diagnostics: [String]
}

enum PDFExtraction {

    // MARK: - Extraction

    static func extract(url: URL) throws -> ExtractedDocument {
        guard let doc = PDFDocument(url: url) else { throw PDFImportError.cannotOpen }
        if doc.isLocked { throw PDFImportError.locked }

        var lines: [ExtractedLine] = []
        var charsPerPage: [Int] = []
        for p in 0..<doc.pageCount {
            guard let page = doc.page(at: p) else { continue }
            let attr = page.attributedString ?? NSAttributedString()
            charsPerPage.append(attr.length)
            lines.append(contentsOf: linesFrom(attr, page: p))
        }

        let sorted = charsPerPage.sorted()
        let medianChars = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        guard medianChars >= 200 else { throw PDFImportError.scannedOrEmpty }

        let attrs = doc.documentAttributes
        let title = (attrs?[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let author = (attrs?[PDFDocumentAttribute.authorAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ExtractedDocument(
            title: (title?.isEmpty == false) ? title : nil,
            author: (author?.isEmpty == false) ? author : nil,
            pageCount: doc.pageCount,
            lines: lines
        )
    }

    private struct RunStyle: Hashable {
        var size: CGFloat
        var bold: Bool
        var mono: Bool
    }

    private static func linesFrom(_ attr: NSAttributedString, page: Int) -> [ExtractedLine] {
        var result: [ExtractedLine] = []
        var current = ""
        var styleChars: [RunStyle: Int] = [:]

        func flush() {
            let text = normalize(current)
            let styles = styleChars
            current = ""
            styleChars = [:]
            guard !text.isEmpty else { return }
            let dominant = styles.max { $0.value < $1.value }?.key
                ?? RunStyle(size: 12, bold: false, mono: false)
            result.append(ExtractedLine(
                text: text, size: dominant.size, bold: dominant.bold,
                mono: dominant.mono, page: page
            ))
        }

        let full = attr.string as NSString
        attr.enumerateAttribute(.font, in: NSRange(location: 0, length: attr.length)) { value, range, _ in
            let font = value as? PlatformFont
            let style = RunStyle(size: font?.pointSize ?? 12, bold: isBold(font), mono: isMono(font))
            var rest = Substring(full.substring(with: range))
            while let nl = rest.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
                let head = rest[..<nl]
                current += head
                styleChars[style, default: 0] += head.count
                flush()
                rest = rest[rest.index(after: nl)...]
            }
            current += rest
            styleChars[style, default: 0] += rest.count
        }
        flush()
        return result
    }

    private static let ligatures: [(String, String)] = [
        ("\u{FB00}", "ff"), ("\u{FB01}", "fi"), ("\u{FB02}", "fl"),
        ("\u{FB03}", "ffi"), ("\u{FB04}", "ffl"), ("\u{00A0}", " "),
    ]

    private static func normalize(_ raw: String) -> String {
        var s = raw
        for (from, to) in ligatures { s = s.replacingOccurrences(of: from, with: to) }
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func isBold(_ font: PlatformFont?) -> Bool {
        guard let font else { return false }
        #if canImport(AppKit)
        if font.fontDescriptor.symbolicTraits.contains(.bold) { return true }
        #else
        if font.fontDescriptor.symbolicTraits.contains(.traitBold) { return true }
        #endif
        let name = font.fontName.lowercased()
        return name.contains("bold") || name.contains("semibold") || name.contains("heavy")
    }

    private static func isMono(_ font: PlatformFont?) -> Bool {
        guard let font else { return false }
        let name = font.fontName.lowercased()
        return name.contains("mono") || name.contains("courier")
            || name.contains("consol") || name.contains("code")
    }

    // MARK: - Structuring

    static func structure(_ doc: ExtractedDocument, fallbackTitle: String) -> StructuredBook {
        var diags: [String] = []
        let pageCount = max(doc.pageCount, 1)
        let lines = doc.lines

        // Body size: weighted mode of line font sizes.
        var sizeWeight: [CGFloat: Int] = [:]
        for l in lines { sizeWeight[(l.size * 2).rounded() / 2, default: 0] += l.text.count }
        let bodySize = sizeWeight.max { $0.value < $1.value }?.key ?? 12
        diags.append("Body font \(bodySize)pt across \(pageCount) pages, \(lines.count) raw lines")

        // Furniture: lines whose digit-normalized form repeats across many pages
        // (running headers/footers, watermarks), bare page numbers, and small
        // repeated print artifacts.
        var pagesForKey: [String: Set<Int>] = [:]
        for l in lines { pagesForKey[furnitureKey(l.text), default: []].insert(l.page) }
        let repeatThreshold = max(3, pageCount / 8)

        func isFurniture(_ l: ExtractedLine) -> Bool {
            if isPureNumber(l.text) { return true }
            guard l.text.count < 100 else { return false }
            let pages = pagesForKey[furnitureKey(l.text)]?.count ?? 0
            if pages >= repeatThreshold { return true }
            if l.size < bodySize * 0.75 && pages >= 3 { return true }
            return false
        }

        var kept: [ExtractedLine] = []
        var droppedCount = 0
        for l in lines {
            if isFurniture(l) { droppedCount += 1 } else { kept.append(l) }
        }
        diags.append("Stripped \(droppedCount) furniture lines (repeat threshold \(repeatThreshold) pages)")

        // Heading candidates: font-size/weight outliers vs body. Lines that are
        // mostly symbols (display math set in large fonts) don't qualify.
        func isHeading(_ l: ExtractedLine) -> Bool {
            guard !l.mono, (1...90).contains(l.text.count) else { return false }
            let nonSpace = l.text.filter { !$0.isWhitespace }
            let letters = nonSpace.filter(\.isLetter).count
            guard Double(letters) >= 0.6 * Double(max(nonSpace.count, 1)) else { return false }
            if l.size >= bodySize * 1.4 { return true }
            if l.bold && l.size >= bodySize * 1.2 { return true }
            return false
        }

        // Merge consecutive heading lines on the same page (multi-line titles,
        // chapter-number line + title line).
        enum Item {
            case heading(text: String, size: CGFloat, page: Int)
            case body(ExtractedLine)
        }
        // A numbered heading ("2.1 Models …") starts a fresh heading even when
        // adjacent to the chapter title above it.
        let numberedHeading = #"^\d+(\.\d+)+\s"#
        var items: [Item] = []
        for l in kept {
            if isHeading(l) {
                if case .heading(let t, let s, let p)? = items.last, p == l.page,
                   abs(s - l.size) <= max(s, l.size) * 0.35,
                   l.text.range(of: numberedHeading, options: .regularExpression) == nil {
                    items[items.count - 1] = .heading(
                        text: joinHeading(t, l.text), size: max(s, l.size), page: p
                    )
                } else {
                    items.append(.heading(text: l.text, size: l.size, page: l.page))
                }
            } else {
                items.append(.body(l))
            }
        }

        let headingIdx = items.indices.filter {
            if case .heading = items[$0] { return true } else { return false }
        }
        diags.append("\(headingIdx.count) heading candidates")

        // Chapter tier: explicit "Chapter N"/"Part N" style headings when
        // present; otherwise the largest font tier among candidates.
        func headingText(_ i: Int) -> String {
            if case .heading(let t, _, _) = items[i] { return t } else { return "" }
        }
        func headingSize(_ i: Int) -> CGFloat {
            if case .heading(_, let s, _) = items[i] { return s } else { return 0 }
        }

        let chapterPattern = #"^(chapter|part|appendix)\b[\s\d]"#
        var chapterIdx = Set(headingIdx.filter {
            headingText($0).range(of: chapterPattern, options: [.regularExpression, .caseInsensitive]) != nil
        })
        if chapterIdx.count < 2 {
            let maxSize = headingIdx.map(headingSize).max() ?? 0
            let top = headingIdx.filter { headingSize($0) >= maxSize - 1 }
            if (2...60).contains(top.count) {
                chapterIdx = Set(top)
            } else if (2...60).contains(headingIdx.count) {
                chapterIdx = Set(headingIdx)   // flat: every heading starts a chapter
            } else {
                chapterIdx = []
            }
        }
        diags.append("\(chapterIdx.count) chapter headings")

        // Median body-line length drives paragraph-break detection.
        let bodyLens = kept.filter { !isHeading($0) && $0.text.count > 15 }
            .map { $0.text.count }.sorted()
        let medianLen = bodyLens.isEmpty ? 60 : bodyLens[bodyLens.count / 2]

        // Assemble Chapter → Section → paragraphs.
        var chapters: [StructuredChapter] = []
        var currentChapter = StructuredChapter(title: "Front Matter", sections: [])
        var currentSection = StructuredSection(title: nil, paragraphs: [])
        var buffer: [ExtractedLine] = []

        func closeSection(nextTitle: String? = nil) {
            currentSection.paragraphs.append(contentsOf: reflow(buffer, medianLen: medianLen))
            buffer = []
            if !currentSection.paragraphs.isEmpty || currentSection.title != nil {
                currentChapter.sections.append(currentSection)
            }
            currentSection = StructuredSection(title: nextTitle, paragraphs: [])
        }
        func closeChapter(nextTitle: String? = nil) {
            closeSection()
            if !currentChapter.sections.isEmpty {
                chapters.append(currentChapter)
            }
            currentChapter = StructuredChapter(title: nextTitle ?? "", sections: [])
        }

        // A bare "Chapter N" label absorbs the heading right after it — that's
        // the chapter's real title, not its first section.
        let bareLabel = #"^(chapter|part|appendix)\b[\s\d]*$"#
        var skip = Set<Int>()
        var i = 0
        while i < items.count {
            defer { i += 1 }
            guard !skip.contains(i) else { continue }
            switch items[i] {
            case .body(let l):
                buffer.append(l)
            case .heading(var t, _, _):
                if chapterIdx.contains(i) {
                    if t.range(of: bareLabel, options: [.regularExpression, .caseInsensitive]) != nil,
                       i + 1 < items.count, !chapterIdx.contains(i + 1),
                       case .heading(let next, _, _) = items[i + 1] {
                        t += " · " + next
                        skip.insert(i + 1)
                    }
                    closeChapter(nextTitle: t)
                } else {
                    closeSection(nextTitle: t)
                }
            }
        }
        closeChapter()

        let title = doc.title ?? fallbackTitle
        if chapters.count == 1, chapters[0].title == "Front Matter" {
            chapters[0].title = title
        }
        let words = chapters.flatMap(\.sections).flatMap(\.paragraphs)
            .reduce(0) { $0 + $1.split(separator: " ").count }
        diags.append("\(chapters.count) chapters, \(chapters.map(\.sections.count).reduce(0, +)) sections, ~\(words) words")

        return StructuredBook(title: title, author: doc.author, chapters: chapters, diagnostics: diags)
    }

    // MARK: - Helpers

    /// Join two lines of one heading, repairing a hyphenated break: lowercase
    /// continuation means a soft break ("Vari- ables" → "Variables"); uppercase
    /// keeps the compound's hyphen ("Discrete- State" → "Discrete-State").
    private static func joinHeading(_ a: String, _ b: String) -> String {
        guard a.hasSuffix("-"), let first = b.first, first.isLetter else {
            return a + " " + b
        }
        return first.isLowercase ? String(a.dropLast()) + b : a + b
    }

    private static func furnitureKey(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: #"\d+"#, with: "#", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func isPureNumber(_ text: String) -> Bool {
        text.range(of: #"^([0-9]+|[ivxlcdm]+)$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Merge lines into paragraphs: repair hyphenated breaks, break on
    /// sentence-final short lines (no geometry available from PDFKit).
    private static func reflow(_ lines: [ExtractedLine], medianLen: Int) -> [String] {
        var paragraphs: [String] = []
        var current = ""
        let shortLine = Int(Double(medianLen) * 0.8)

        for line in lines {
            let t = line.text
            if current.isEmpty {
                current = t
            } else if current.hasSuffix("-"), let first = t.first, first.isLowercase {
                current.removeLast()
                current += t
            } else {
                current += " " + t
            }
            let endsSentence = t.last.map { ".!?:\u{201D}\")".contains($0) } ?? false
            if endsSentence && t.count < shortLine {
                paragraphs.append(current)
                current = ""
            }
        }
        if !current.isEmpty { paragraphs.append(current) }
        return paragraphs
    }
}
