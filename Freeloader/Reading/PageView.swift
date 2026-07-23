import SwiftUI

// One fixed page of the paginated reading view (ticket 05).
//
// Every word is its own Text positioned at a frame the Paginator computed,
// so the Dock-style magnifier is pure visual scale: the word under the amber
// cursor grows to MagnifierTunables.maxScale, same-line neighbors swell with
// a raised-cosine falloff, and nothing ever reflows. A single amber capsule
// slides under the current word (one spring, not a per-word storm), and a
// spatial tap anywhere on the page jumps the cursor to the nearest word.
//
// Ticket 08 adds selection: a drag that STARTS on a word sweeps out a word
// range (per-line amber wash behind the text), and releasing surfaces the
// small Define/Explain menu above the selection. Drags that start on
// whitespace still read as page-turn swipes; a tap while a selection exists
// clears it instead of jumping the cursor.

struct PageView: View {
    let page: BuiltPage
    let paginated: PaginatedChapter
    let spec: PageLayoutSpec
    let scheme: ColorScheme
    /// Global word index of the cursor (may be on another page).
    let cursor: Int
    let magnify: Bool
    /// In-progress or committed selection (global word indices).
    let selection: Range<Int>?
    /// True once a selection drag has ended — shows the Define/Explain menu.
    let menuVisible: Bool
    /// Whether the selection menu offers the Note action (needs a real book).
    let canNote: Bool
    /// Anchored notes intersecting this chapter (ticket 10), as global word
    /// ranges — rendered as faint amber underlines, a pencil line in the
    /// margin rather than a highlighter smear.
    let noteRanges: [Range<Int>]
    let onTapWord: (Int) -> Void
    let onSelectionChanged: (Range<Int>?) -> Void
    let onSelectionEnded: () -> Void
    let onSelectionAction: (SelectionAction) -> Void
    /// Swipe-like drag that didn't start on a word: +1 next page, -1 previous.
    let onSwipe: (Int) -> Void

    /// Transient drag state (resets with the page's identity).
    @State private var dragAnchor: Int?
    @State private var dragIsSwipe = false
    /// Last single-tap (word id + time): a second tap on the same word within
    /// `doubleTapWindow` upgrades to a one-word selection with the menu shown,
    /// so double-clicking the highlighted word reaches Define/Explain/Note.
    @State private var lastTap: (word: Int, at: Date)?
    private static let doubleTapWindow: TimeInterval = 0.35

    private var pageWords: ArraySlice<PageWord> {
        paginated.words[page.wordRange]
    }

    private var currentWord: PageWord? {
        guard page.wordRange.contains(cursor) else { return nil }
        return paginated.words[cursor]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Note underlines: a thin amber pencil line beneath each noted
            // line — persistent, quieter than both cursor and selection.
            ForEach(Array(noteRects.enumerated()), id: \.offset) { _, rect in
                Capsule()
                    .fill(ReadingPalette.noteUnderline(scheme))
                    .frame(width: rect.width + 4, height: 2)
                    .position(x: rect.midX, y: rect.maxY + 3.5)
            }

            // Selection wash: one rounded rect per selected line, behind
            // both the cursor capsule and the text.
            ForEach(Array(selectionRects.enumerated()), id: \.offset) { _, rect in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(ReadingPalette.selectionHighlight(scheme))
                    .frame(width: rect.width + 9, height: rect.height + 4)
                    .position(x: rect.midX, y: rect.midY + 1)
            }

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
                WordGlyph(word: word, scale: scale(for: word), xOffset: xOffset(for: word))
                    .equatable()
            }

            if menuVisible, let position = menuPosition {
                SelectionMenu(scheme: scheme, canNote: canNote, onAction: onSelectionAction)
                    .position(position)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .frame(width: spec.columnWidth, height: spec.pageHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(selectionOrSwipeDrag)
        .gesture(
            SpatialTapGesture().onEnded { tap in
                guard let hit = nearestWord(to: tap.location) else {
                    if selection != nil { onSelectionAction(.dismiss) }
                    return
                }
                if let last = lastTap, last.word == hit.id,
                   Date().timeIntervalSince(last.at) < Self.doubleTapWindow {
                    lastTap = nil
                    onSelectionChanged(hit.id..<(hit.id + 1))
                    onSelectionEnded()
                } else {
                    lastTap = (hit.id, Date())
                    if selection != nil {
                        onSelectionAction(.dismiss)
                    } else {
                        onTapWord(hit.id)
                    }
                }
            }
        )
    }

    // MARK: Selection drag (falls back to a page-turn swipe off-text)

    private var selectionOrSwipeDrag: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if dragAnchor == nil && !dragIsSwipe {
                    if let hit = selectionHit(value.startLocation, maxCost: 460) {
                        dragAnchor = hit.id
                    } else {
                        dragIsSwipe = true
                    }
                }
                if let anchor = dragAnchor, let current = selectionHit(value.location) {
                    let lo = min(anchor, current.id)
                    let hi = max(anchor, current.id)
                    onSelectionChanged(lo..<(hi + 1))
                }
            }
            .onEnded { value in
                let wasSelecting = dragAnchor != nil
                dragAnchor = nil
                dragIsSwipe = false
                if wasSelecting {
                    onSelectionEnded()
                } else {
                    let dx = value.translation.width
                    if abs(dx) > 60, abs(dx) > abs(value.translation.height) {
                        onSwipe(dx < 0 ? 1 : -1)
                    }
                }
            }
    }

    /// Word nearest the point for selection: line distance dominates, then
    /// horizontal distance — so sweeping below a line still tracks it.
    /// `maxCost` gates drag *starts* (must begin close to actual text).
    private func selectionHit(
        _ point: CGPoint, maxCost: CGFloat = .infinity
    ) -> PageWord? {
        var best: (word: PageWord, cost: CGFloat)?
        for word in pageWords {
            let f = word.frame
            let dy = max(0, max(f.minY - point.y, point.y - f.maxY))
            let dx = max(0, max(f.minX - point.x, point.x - f.maxX))
            let cost = dy * 100 + dx
            if cost < (best?.cost ?? .infinity) { best = (word, cost) }
        }
        guard let best, best.cost <= maxCost else { return nil }
        return best.word
    }

    /// One rect per selected line on this page.
    private var selectionRects: [CGRect] {
        guard let selection else { return [] }
        return lineRects(of: selection)
    }

    /// Per-line rects for every note range that touches this page.
    private var noteRects: [CGRect] {
        noteRanges.flatMap(lineRects(of:))
    }

    /// Groups a global word range into one rect per rendered line.
    private func lineRects(of range: Range<Int>) -> [CGRect] {
        let clamped = range.clamped(to: page.wordRange)
        guard !clamped.isEmpty else { return [] }
        var rects: [CGRect] = []
        var current: CGRect?
        for word in paginated.words[clamped] {
            if let c = current, abs(c.minY - word.frame.minY) < 1 {
                current = c.union(word.frame)
            } else {
                if let c = current { rects.append(c) }
                current = word.frame
            }
        }
        if let c = current { rects.append(c) }
        return rects
    }

    /// Menu floats above the selection's first line (below the last line
    /// when the selection starts too close to the page top), clamped into
    /// the column.
    private var menuPosition: CGPoint? {
        guard let first = selectionRects.first, let last = selectionRects.last else {
            return nil
        }
        let halfWidth: CGFloat = canNote ? 128 : 95
        let x = min(max(first.midX, halfWidth), max(spec.columnWidth - halfWidth, halfWidth))
        let y = first.minY > 52 ? first.minY - 30 : last.maxY + 32
        return CGPoint(x: x, y: y)
    }

    /// Dock falloff: only the cursor's own line swells, by word distance.
    private func scale(for word: PageWord) -> CGFloat {
        guard magnify,
              let current = currentWord,
              abs(word.frame.minY - current.frame.minY) < 1
        else { return 1 }
        return MagnifierTunables.scale(distance: Double(abs(word.id - current.id)))
    }

    /// Dock push-apart: neighbors on the cursor's line shift outward so the
    /// swollen words never overlap. A word moves by half the cursor word's
    /// extra width, the full extra width of every swollen word between them
    /// (ids on one line are contiguous), and half its own — the spacing each
    /// pair needs to keep its original gap.
    private func xOffset(for word: PageWord) -> CGFloat {
        guard magnify,
              let current = currentWord,
              word.id != current.id,
              abs(word.frame.minY - current.frame.minY) < 1
        else { return 0 }
        var shift = (extraWidth(of: current) + extraWidth(of: word)) / 2
        for id in (min(word.id, current.id) + 1)..<max(word.id, current.id) {
            shift += extraWidth(of: paginated.words[id])
        }
        let direction: CGFloat = word.id > current.id ? 1 : -1
        return direction * shift * MagnifierTunables.pushApart
    }

    /// Width a word gains from magnification (0 when outside the falloff).
    private func extraWidth(of word: PageWord) -> CGFloat {
        word.frame.width * (scale(for: word) - 1)
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
    let xOffset: CGFloat

    static func == (lhs: WordGlyph, rhs: WordGlyph) -> Bool {
        lhs.word.id == rhs.word.id
            && lhs.scale == rhs.scale
            && lhs.xOffset == rhs.xOffset
            && lhs.word.frame == rhs.word.frame
    }

    var body: some View {
        Text(word.text)
            .fixedSize()
            .scaleEffect(scale, anchor: MagnifierTunables.anchor)
            .position(x: word.frame.midX + xOffset, y: word.frame.midY)
    }
}
