import SwiftUI

// 0.5s: a warm paper page — one serene serif column with rhythmic bold
// word-starts, floating on parchment; a single amber word marks the reader.
// User: an easily-pulled-away reader settling in for a focused session.
// Emotional intent: CALM / FOCUSED — zero chrome, the screen IS the page.
//
// Performance model (ticket 12): bionic AttributedStrings are built off the
// main thread by ChapterBuilder (actor, LRU cache keyed by chapter/size/
// scheme) with neighbor-chapter prefetch, so chapter switches are cache hits.
// The column is a LazyVStack, and the old whole-column `.animation(value:
// fontSize)` is gone — resizes swap in a prebuilt column instead of
// animating a full re-layout.

// MARK: - Palette (seed 38°, analogous, WCAG-validated)

enum ReadingPalette {
    static func paper(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(hue: 0.1056, saturation: 0.05, brightness: 0.09)
            : Color(hue: 0.1056, saturation: 0.03, brightness: 0.985)
    }

    static func paperGlow(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(hue: 0.1056, saturation: 0.12, brightness: 0.13)
            : Color(hue: 0.1056, saturation: 0.06, brightness: 0.96)
    }

    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(hue: 0.1056, saturation: 0.04, brightness: 0.88)
            : Color(hue: 0.1056, saturation: 0.30, brightness: 0.16)
    }

    static func inkFaded(_ scheme: ColorScheme) -> Color {
        ink(scheme).opacity(scheme == .dark ? 0.62 : 0.72)
    }

    static func brand(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(hue: 0.1056, saturation: 0.70, brightness: 0.59)
            : Color(hue: 0.1056, saturation: 0.65, brightness: 0.55)
    }

    static func cursorHighlight(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(hue: 0.1056, saturation: 0.75, brightness: 0.45).opacity(0.55)
            : Color(hue: 0.1056, saturation: 0.55, brightness: 0.92).opacity(0.9)
    }
}

// MARK: - Sample content (no-book preview)

enum SampleChapter {
    static let source = ChapterSource(
        id: "sample",
        kicker: "Chapter 3",
        title: "The Shape of Attention",
        sections: [
            ChapterSource.Section(title: nil, text: [
                "Attention is not a spotlight you aim; it is a current you enter. Every reader knows the feeling of the current catching — the page dissolves, the room goes quiet, and the words stop being ink and start being thought. The tragedy of most reading tools is that they interrupt precisely this moment, mistaking engagement for stimulation.",
                "The eye does not read letter by letter. It leaps in saccades, landing three or four characters into a word and inferring the rest from shape and context. A skilled reader recognizes whole word-forms the way a face is recognized: instantly, and without inspection. Anchoring the first few letters of each word gives the leaping eye a place to land — a stepping-stone path across the sentence.",
                "This is why pacing matters more than speed. A metronome does not make a pianist faster; it makes her steady. When the pace is steady, the mind stops negotiating with itself about whether to continue, and the decision to read the next word — a decision the distracted mind makes hundreds of times a minute — is quietly retired.",
                "What remains is comprehension, which has its own rhythm. Ideas arrive in paragraphs, not words. A reader who moves steadily through the text but pauses at its joints — the end of a section, the turn of an argument — retains more than one who sprints and rereads. The joints are where understanding is assembled.",
                "So the instrument we want is neither a speed-reader nor a teleprompter. It is closer to a quiet companion: one finger resting on the line, moving at your pace, patient at the joints, and silent the rest of the time."
            ].joined(separator: "\n\n"))
        ]
    )
}

// MARK: - Reading view

struct ReadingView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var fontSize: CGFloat = 25
    @State private var showTypeControls = false
    @State private var chapterIndex: Int = 0
    @State private var built: BuiltChapter?

    var book: Book?

    private var lineSpacing: CGFloat { fontSize * 0.58 }
    private var columnWidth: CGFloat { min(fontSize * 34, 720) }

    private var sortedChapters: [Chapter] {
        (book?.chapters ?? []).sorted { $0.index < $1.index }
    }

    /// Cheap value snapshot of the chapter at `index` (main thread; no text
    /// processing — splitting/attributing happens in ChapterBuilder).
    private func source(at index: Int) -> ChapterSource? {
        guard let book else { return index == 0 ? SampleChapter.source : nil }
        let chapters = sortedChapters
        guard chapters.indices.contains(index) else { return nil }
        let ch = chapters[index]
        return ChapterSource(
            id: "\(String(describing: ch.persistentModelID))",
            kicker: book.title,
            title: ch.title,
            sections: ch.sections
                .sorted { $0.index < $1.index }
                .map { ChapterSource.Section(title: $0.title, text: $0.text) }
        )
    }

    /// Cheap per-body-eval metadata (no section text access — SwiftData
    /// string fetches stay out of the render path).
    private struct ChapterMeta: Equatable {
        let id: String
        let kicker: String
        let title: String
    }

    private var currentMeta: ChapterMeta {
        guard let book else {
            let s = SampleChapter.source
            return ChapterMeta(id: s.id, kicker: s.kicker, title: s.title)
        }
        let chapters = sortedChapters
        guard chapters.indices.contains(chapterIndex) else {
            return ChapterMeta(id: "empty", kicker: book.title, title: "Empty Book")
        }
        let ch = chapters[chapterIndex]
        return ChapterMeta(
            id: "\(String(describing: ch.persistentModelID))",
            kicker: book.title,
            title: ch.title
        )
    }

    /// Only show built text that belongs to the current chapter — never
    /// stale paragraphs under a new header. (Stale *sizes* of the same
    /// chapter are fine: they keep text on screen during a resize.)
    private var displayed: BuiltChapter? {
        guard let built, built.sourceID == currentMeta.id else { return nil }
        return built
    }

    private struct BuildRequest: Equatable {
        let chapterID: String
        let size: CGFloat
        let dark: Bool
    }

    private var buildRequest: BuildRequest {
        BuildRequest(chapterID: currentMeta.id, size: fontSize, dark: scheme == .dark)
    }

    var body: some View {
        ZStack {
            backdrop

            ScrollView {
                LazyVStack(alignment: .leading, spacing: lineSpacing * 1.6) {
                    header
                        .padding(.bottom, lineSpacing)

                    if let displayed {
                        ForEach(Array(displayed.sections.enumerated()), id: \.offset) { _, section in
                            if let title = section.title {
                                Text(title)
                                    .font(.system(size: fontSize * 1.25, weight: .semibold, design: .serif))
                                    .foregroundStyle(ReadingPalette.ink(scheme))
                                    .padding(.top, lineSpacing)
                            }
                            ForEach(section.paragraphs) { para in
                                Text(para.text)
                                    .lineSpacing(lineSpacing)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                        }

                        sectionEndMark
                            .padding(.top, lineSpacing)

                        if book != nil, chapterIndex + 1 < sortedChapters.count {
                            nextChapterButton
                        }
                    }
                }
                .frame(maxWidth: columnWidth, alignment: .leading)
                .padding(.horizontal, 48)
                .padding(.top, 64)
                .padding(.bottom, 120)
                .frame(maxWidth: .infinity)
            }
            .id(chapterIndex)   // reset scroll offset on chapter change
        }
        .overlay(alignment: .bottomTrailing) { typeButton }
        .preferredColorScheme(.dark)
        .toolbar { if book != nil { chapterMenu } }
        .onAppear {
            if let position = book?.readingPosition {
                chapterIndex = position.chapterIndex
            }
        }
        .onChange(of: chapterIndex) {
            book?.readingPosition?.chapterIndex = chapterIndex
            book?.readingPosition?.updatedAt = .now
        }
        .task(id: buildRequest) {
            let request = buildRequest
            // Full text snapshot happens only here, once per build request.
            guard let src = source(at: chapterIndex) ?? (book == nil ? SampleChapter.source : nil) else {
                built = nil
                return
            }
            let result = await ChapterBuilder.shared.built(
                for: src, size: request.size, scheme: scheme
            )
            guard !Task.isCancelled else { return }
            if displayed == nil {
                // First paint of this chapter: quick fade beats a pop-in.
                withAnimation(.easeOut(duration: 0.15)) { built = result }
            } else {
                built = result
            }
            prefetchNeighbors(of: chapterIndex, size: request.size)
        }
    }

    /// Warm the cache for the chapters the reader is most likely to open
    /// next, so switching is a cache hit (instant).
    private func prefetchNeighbors(of index: Int, size: CGFloat) {
        let currentScheme = scheme
        for neighbor in [index + 1, index - 1] {
            guard let src = source(at: neighbor) else { continue }
            Task.detached(priority: .utility) {
                await ChapterBuilder.shared.prefetch(src, size: size, scheme: currentScheme)
            }
        }
    }

    private var chapterMenu: some ToolbarContent {
        ToolbarItem {
            Menu {
                ForEach(Array(sortedChapters.enumerated()), id: \.offset) { i, ch in
                    Button {
                        chapterIndex = i
                    } label: {
                        if i == chapterIndex {
                            Label(ch.title, systemImage: "checkmark")
                        } else {
                            Text(ch.title)
                        }
                    }
                }
            } label: {
                Label("Chapters", systemImage: "list.bullet")
            }
        }
    }

    private var nextChapterButton: some View {
        Button {
            chapterIndex += 1
        } label: {
            HStack(spacing: 8) {
                Text("Next Chapter")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(ReadingPalette.brand(scheme))
            .padding(.vertical, 10)
            .padding(.horizontal, 18)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(ReadingPalette.brand(scheme).opacity(0.25)))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.top, lineSpacing)
    }

    private var backdrop: some View {
        RadialGradient(
            colors: [ReadingPalette.paperGlow(scheme), ReadingPalette.paper(scheme)],
            center: .init(x: 0.5, y: 0.25),
            startRadius: 0,
            endRadius: 900
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(currentMeta.kicker.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(3.2)
                .foregroundStyle(ReadingPalette.brand(scheme))
            Text(currentMeta.title)
                .font(.system(size: fontSize * 1.9, weight: .bold, design: .serif))
                .foregroundStyle(ReadingPalette.ink(scheme))
        }
    }

    private var sectionEndMark: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(ReadingPalette.brand(scheme).opacity(0.55))
                    .frame(width: 4, height: 4)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var typeButton: some View {
        Button {
            showTypeControls.toggle()
        } label: {
            Text("Aa")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(ReadingPalette.ink(scheme))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(ReadingPalette.brand(scheme).opacity(0.25)))
        }
        .buttonStyle(.plain)
        .padding(24)
        .popover(isPresented: $showTypeControls, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Text Size")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Text("Aa").font(.system(size: 12, design: .serif))
                    Slider(value: $fontSize, in: 15...27, step: 1)
                        .frame(width: 180)
                    Text("Aa").font(.system(size: 22, design: .serif))
                }
            }
            .padding(16)
        }
    }
}

#Preview {
    ReadingView()
}
