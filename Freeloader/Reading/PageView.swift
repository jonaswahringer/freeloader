import SwiftUI

// One fixed page of the paginated reading view (ticket 05).
//
// Every word is its own Text positioned at a frame the Paginator computed,
// so the Dock-style magnifier is pure visual scale: the word under the amber
// cursor grows to MagnifierTunables.maxScale, same-line neighbors swell with
// a raised-cosine falloff, and nothing ever reflows. A single amber capsule
// slides under the current word (one spring, not a per-word storm), and a
// spatial tap anywhere on the page jumps the cursor to the nearest word.

struct PageView: View {
    let page: BuiltPage
    let paginated: PaginatedChapter
    let spec: PageLayoutSpec
    let scheme: ColorScheme
    /// Global word index of the cursor (may be on another page).
    let cursor: Int
    let magnify: Bool
    let onTapWord: (Int) -> Void

    private var pageWords: ArraySlice<PageWord> {
        paginated.words[page.wordRange]
    }

    private var currentWord: PageWord? {
        guard page.wordRange.contains(cursor) else { return nil }
        return paginated.words[cursor]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The amber cursor: one capsule sliding beneath the line.
            if let current = currentWord {
                let pad = MagnifierTunables.highlightPadding
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(ReadingPalette.cursorHighlight(scheme))
                    .frame(
                        width: current.frame.width + pad.width,
                        height: current.frame.height + pad.height
                    )
                    .scaleEffect(
                        magnify ? MagnifierTunables.maxScale : 1,
                        anchor: MagnifierTunables.anchor
                    )
                    .position(x: current.frame.midX, y: current.frame.midY + 1)
            }

            ForEach(page.blocks) { block in
                blockView(block)
            }

            ForEach(pageWords) { word in
                WordGlyph(word: word, scale: scale(for: word))
                    .equatable()
            }
        }
        .frame(width: spec.columnWidth, height: spec.pageHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { tap in
                if let hit = nearestWord(to: tap.location) {
                    onTapWord(hit.id)
                }
            }
        )
    }

    /// Dock falloff: only the cursor's own line swells, by word distance.
    private func scale(for word: PageWord) -> CGFloat {
        guard magnify,
              let current = currentWord,
              abs(word.frame.minY - current.frame.minY) < 1
        else { return 1 }
        return MagnifierTunables.scale(distance: Double(abs(word.id - current.id)))
    }

    /// Word whose (slightly inflated) frame contains or is nearest the point.
    private func nearestWord(to point: CGPoint) -> PageWord? {
        var best: (word: PageWord, distance: CGFloat)?
        for word in pageWords {
            let f = word.frame.insetBy(dx: -6, dy: -4)
            if f.contains(point) { return word }
            // Same line band only — no jumping across lines on a miss.
            guard point.y >= f.minY, point.y <= f.maxY else { continue }
            let dx = point.x < f.minX ? f.minX - point.x : point.x - f.maxX
            if dx < 24, dx < (best?.distance ?? .infinity) {
                best = (word, dx)
            }
        }
        return best?.word
    }

    @ViewBuilder
    private func blockView(_ block: PageBlock) -> some View {
        Group {
            switch block.kind {
            case .kicker(let text):
                Text(text.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(3.2)
                    .foregroundStyle(ReadingPalette.brand(scheme))
            case .chapterTitle(let text):
                Text(text)
                    .font(.system(size: spec.fontSize * 1.9, weight: .bold, design: .serif))
                    .foregroundStyle(ReadingPalette.ink(scheme))
            case .sectionTitle(let text):
                Text(text)
                    .font(.system(size: spec.fontSize * 1.25, weight: .semibold, design: .serif))
                    .foregroundStyle(ReadingPalette.ink(scheme))
            }
        }
        .frame(width: block.frame.width, alignment: .topLeading)
        .position(x: block.frame.midX, y: block.frame.midY)
    }
}

/// A single positioned word. Equatable so a cursor tick only re-renders the
/// handful of words whose scale changed.
struct WordGlyph: View, Equatable {
    let word: PageWord
    let scale: CGFloat

    static func == (lhs: WordGlyph, rhs: WordGlyph) -> Bool {
        lhs.word.id == rhs.word.id
            && lhs.scale == rhs.scale
            && lhs.word.frame == rhs.word.frame
    }

    var body: some View {
        Text(word.text)
            .fixedSize()
            .scaleEffect(scale, anchor: MagnifierTunables.anchor)
            .position(x: word.frame.midX, y: word.frame.midY)
    }
}
