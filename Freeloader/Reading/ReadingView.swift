import SwiftUI
import SwiftData

// 0.5s: a warm paper page — one serene serif column with rhythmic bold
// word-starts, floating on parchment; a single amber word marks the reader.
// User: an easily-pulled-away reader settling in for a focused session.
// Emotional intent: CALM / FOCUSED — zero chrome, the screen IS the page.
//
// Ticket 05: the chapter is paginated into fixed pages sized to the window.
// An amber cursor sweeps word-by-word at the reader's WPM (length- and
// punctuation-weighted), magnifying the current word Dock-style — neighbors
// swell with a cosine falloff, purely visual scale, never a reflow. Pages
// turn themselves when the cursor crosses the fold; the reader can pause,
// flip pages, or click any word to move the cursor. Pacing guides, never
// forces.
//
// Performance model (ticket 12 + 05): bionic AttributedStrings are built
// off-main by ChapterBuilder (LRU cache + neighbor prefetch); Paginator
// (also an actor, off-main, CoreText measurement) turns a BuiltChapter into
// absolutely-positioned word frames. The playback loop is a single async
// task sleeping per-word intervals — one small withAnimation per tick, and
// Equatable word glyphs mean only the few words whose scale changed
// re-render.

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

    /// Selection wash (ticket 08) — quieter than the cursor so the two read
    /// as different intentions in the same amber language.
    static func selectionHighlight(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(hue: 0.1056, saturation: 0.6, brightness: 0.55).opacity(0.3)
            : Color(hue: 0.1056, saturation: 0.5, brightness: 0.88).opacity(0.6)
    }

    /// Note underline (ticket 10) — the quietest amber on the page: a
    /// persistent pencil line that must never fight the pacing cursor.
    static func noteUnderline(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(hue: 0.1056, saturation: 0.65, brightness: 0.58).opacity(0.42)
            : Color(hue: 0.1056, saturation: 0.6, brightness: 0.6).opacity(0.5)
    }

    /// Dim behind the Define/Explain modal — warm-tinted, page still legible.
    static func scrim(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(hue: 0.1056, saturation: 0.15, brightness: 0.03).opacity(0.55)
            : Color(hue: 0.1056, saturation: 0.2, brightness: 0.25).opacity(0.28)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext

    @State private var fontSize: CGFloat = 25
    @State private var showTypeControls = false
    @State private var showPaceControls = false
    @State private var chapterIndex: Int = 0
    @State private var built: BuiltChapter?
    @State private var paginated: PaginatedChapter?
    @State private var pageIndex: Int = 0
    /// Global word index of the amber cursor within the current chapter.
    @State private var cursor: Int = 0
    @State private var isPlaying = false
    @State private var wpm: Double = 250
    /// +1 forward, -1 backward — decides which way pages drift.
    @State private var turnDirection: Int = 1
    @State private var pageArea: CGSize = .zero

    // Ticket 08: selection → Define/Explain → threaded modal.
    /// Global word range of the reader's selection in the current chapter.
    @State private var selection: Range<Int>?
    /// True once the selection drag has ended (surfaces the small menu).
    @State private var selectionMenuShown = false
    /// The open Define/Explain modal, when any.
    @State private var discussion: DiscussionController?
    @State private var showHistory = false

    // Ticket 10: anchored notes.
    /// Anchor captured from the selection while the note composer is open.
    @State private var noteTarget: NoteDraftTarget?
    @State private var showNotes = false
    /// This chapter's note anchors as global word ranges (recomputed off the
    /// render path — see `noteAnchorKey`).
    @State private var noteRanges: [Range<Int>] = []
    /// Jump-back target waiting for another chapter's pagination to land.
    @State private var pendingJump: NoteJump?
    @State private var noteSaves = 0

    var book: Book?

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

    private var layoutSpec: PageLayoutSpec? {
        guard pageArea.width > 60, pageArea.height > 120 else { return nil }
        return PageLayoutSpec(
            fontSize: fontSize,
            columnWidth: min(fontSize * 34, 720, pageArea.width),
            pageHeight: pageArea.height,
            dark: scheme == .dark
        )
    }

    /// Only show pages that belong to the current chapter — never stale
    /// paragraphs under a new header. (A stale *layout* of the same chapter
    /// stays visible during a resize until the new one lands.)
    private var displayedPagination: PaginatedChapter? {
        guard let paginated, paginated.chapterID == currentMeta.id else { return nil }
        return paginated
    }

    private struct PipelineRequest: Equatable {
        let chapterID: String
        let size: CGFloat
        let dark: Bool
        let columnWidth: CGFloat
        let pageHeight: CGFloat
    }

    private var pipelineRequest: PipelineRequest? {
        guard let spec = layoutSpec else { return nil }
        return PipelineRequest(
            chapterID: currentMeta.id,
            size: fontSize,
            dark: spec.dark,
            columnWidth: spec.columnWidth.rounded(),
            pageHeight: spec.pageHeight.rounded()
        )
    }

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 10) {
                pageContainer
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onGeometryChange(for: CGSize.self) { proxy in
                        proxy.size
                    } action: { size in
                        pageArea = size
                    }

                bottomBar
            }
            .padding(.horizontal, 48)
            .padding(.top, 40)
            .padding(.bottom, 16)
        }
        .overlay(alignment: .bottomTrailing) { typeButton }
        .overlay { discussionOverlay }
        .overlay { noteComposerOverlay }
        .sensoryFeedback(.success, trigger: noteSaves)
        .preferredColorScheme(.dark)
        .toolbar {
            if book != nil {
                chapterMenu
                notesButton
                historyButton
            }
        }
        .onAppear(perform: restore)
        .onDisappear {
            isPlaying = false
            persistPosition()
        }
        .onChange(of: chapterIndex) {
            isPlaying = false
            cursor = 0
            pageIndex = 0
            clearSelection()
            persistPosition()
        }
        .onChange(of: pageIndex) {
            clearSelection()
        }
        .onChange(of: wpm) {
            book?.readingPosition?.wordsPerMinute = Int(wpm)
        }
        .task(id: pipelineRequest) { await runPipeline() }
        .task(id: isPlaying) { await playbackLoop() }
        .task(id: noteAnchorKey) { recomputeNoteRanges() }
    }

    // MARK: Pipeline: build (cached) → paginate (cached) → present

    private func runPipeline() async {
        guard let request = pipelineRequest, let spec = layoutSpec else { return }
        guard let src = source(at: chapterIndex) else {
            built = nil
            paginated = nil
            return
        }
        let chapterScheme: ColorScheme = request.dark ? .dark : .light
        let result = await ChapterBuilder.shared.built(
            for: src, size: request.size, scheme: chapterScheme
        )
        guard !Task.isCancelled else { return }
        built = result
        prefetchNeighbors(of: chapterIndex, size: request.size)

        let pages = await Paginator.shared.paginate(result, spec: spec)
        guard !Task.isCancelled else { return }
        present(pages)
    }

    private func present(_ pages: PaginatedChapter) {
        let sameChapter = paginated?.chapterID == pages.chapterID
        var target = cursor
        if !sameChapter {
            // Fresh chapter: restore the persisted word if it lives here.
            if let pos = book?.readingPosition, pos.chapterIndex == chapterIndex {
                target = pos.wordIndex
            } else {
                target = 0
            }
        }
        target = max(0, min(target, pages.wordCount - 1))
        if sameChapter {
            // Re-layout (resize / font change): keep place, no animation.
            paginated = pages
            cursor = max(target, 0)
            pageIndex = pages.pageIndex(ofWord: cursor)
        } else {
            withAnimation(.easeOut(duration: 0.15)) {
                paginated = pages
                cursor = max(target, 0)
                pageIndex = pages.pageIndex(ofWord: cursor)
            }
        }
        // A notes-list jump into another chapter completes here, once the
        // target chapter's pagination has landed.
        if let jump = pendingJump, jump.chapterIndex == chapterIndex {
            pendingJump = nil
            apply(jump, in: pages)
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

    // MARK: Playback (one async loop; variable per-word intervals)

    private func playbackLoop() async {
        guard isPlaying else { return }
        while !Task.isCancelled, isPlaying {
            guard let pag = displayedPagination, pag.wordCount > 0,
                  cursor < pag.wordCount else {
                isPlaying = false
                return
            }
            let word = pag.words[cursor]
            let interval = PacingTunables.interval(weight: word.pacingWeight, wpm: wpm)
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled, isPlaying else { return }
            advance()
        }
    }

    private func advance() {
        guard let pag = displayedPagination else { return }
        let next = cursor + 1
        guard next < pag.wordCount else {
            // Chapter finished: rest on the last word; the reader decides.
            isPlaying = false
            persistPosition()
            return
        }
        let nextPage = pag.pageIndex(ofWord: next)
        if nextPage != pageIndex {
            turnDirection = nextPage > pageIndex ? 1 : -1
            withAnimation(reduceMotion ? .default : ReadingMotion.pageTurn) {
                pageIndex = nextPage
                cursor = next
            }
            persistPosition()
        } else {
            withAnimation(reduceMotion ? nil : ReadingMotion.cursor) {
                cursor = next
            }
            if next % 25 == 0 { persistPosition() }
        }
    }

    private func togglePlay() {
        // Restart a finished chapter from the top.
        if !isPlaying, let pag = displayedPagination,
           cursor >= pag.wordCount - 1, pag.wordCount > 1 {
            turnDirection = -1
            withAnimation(reduceMotion ? .default : ReadingMotion.pageTurn) {
                cursor = 0
                pageIndex = pag.pageIndex(ofWord: 0)
            }
        }
        isPlaying.toggle()
        if !isPlaying { persistPosition() }
    }

    private func turnPage(_ delta: Int) {
        guard let pag = displayedPagination else { return }
        let target = max(0, min(pageIndex + delta, pag.pages.count - 1))
        guard target != pageIndex else { return }
        turnDirection = delta > 0 ? 1 : -1
        withAnimation(reduceMotion ? .default : ReadingMotion.pageTurn) {
            pageIndex = target
            let range = pag.pages[target].wordRange
            if !range.isEmpty { cursor = range.lowerBound }
        }
        persistPosition()
    }

    private func jump(toWord id: Int) {
        withAnimation(reduceMotion ? nil : ReadingMotion.cursor) {
            cursor = id
        }
        persistPosition()
    }

    // MARK: Persistence (SwiftData ReadingPosition)

    private func restore() {
        guard let book else { return }
        if let pos = book.readingPosition {
            chapterIndex = pos.chapterIndex
            cursor = pos.wordIndex
            wpm = Double(pos.wordsPerMinute).clamped(to: PacingTunables.range)
        }
    }

    private func persistPosition() {
        guard let book else { return }
        let pos: ReadingPosition
        if let existing = book.readingPosition {
            pos = existing
        } else {
            pos = ReadingPosition()
            modelContext.insert(pos)
            book.readingPosition = pos
        }
        pos.chapterIndex = chapterIndex
        pos.wordIndex = cursor
        if let pag = displayedPagination, pag.words.indices.contains(cursor) {
            pos.sectionIndex = pag.words[cursor].sectionIndex
        }
        pos.wordsPerMinute = Int(wpm)
        pos.updatedAt = .now
    }

    // MARK: Page container

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let drift = CGFloat(turnDirection) * 44
        return .asymmetric(
            insertion: .offset(x: drift).combined(with: .opacity),
            removal: .offset(x: -drift).combined(with: .opacity)
        )
    }

    @ViewBuilder
    private var pageContainer: some View {
        ZStack(alignment: .top) {
            if let pag = displayedPagination, pag.pages.indices.contains(pageIndex) {
                PageView(
                    page: pag.pages[pageIndex],
                    paginated: pag,
                    spec: pag.spec,
                    scheme: scheme,
                    cursor: cursor,
                    magnify: !reduceMotion,
                    selection: selection,
                    menuVisible: selectionMenuShown,
                    canNote: book != nil,
                    noteRanges: noteRanges,
                    onTapWord: { jump(toWord: $0) },
                    onSelectionChanged: { range in
                        if range != nil, isPlaying { isPlaying = false }
                        selectionMenuShown = false
                        selection = range
                    },
                    onSelectionEnded: {
                        guard selection != nil else { return }
                        withAnimation(reduceMotion ? .default : ReadingMotion.controls) {
                            selectionMenuShown = true
                        }
                    },
                    onSelectionAction: handleSelectionAction,
                    onSwipe: { turnPage($0) }
                )
                .id("\(pag.chapterID)#\(pageIndex)")
                .transition(pageTransition)
            } else {
                // Cold chapter jump: header appears instantly, text fades in
                // when the (usually prefetched) build + layout lands.
                interimHeader
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 60, abs(dx) > abs(value.translation.height) else { return }
                turnPage(dx < 0 ? 1 : -1)
            }
        )
    }

    private var interimHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(currentMeta.kicker.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(3.2)
                .foregroundStyle(ReadingPalette.brand(scheme))
            Text(currentMeta.title)
                .font(.system(size: fontSize * 1.9, weight: .bold, design: .serif))
                .foregroundStyle(ReadingPalette.ink(scheme))
        }
        .frame(maxWidth: min(fontSize * 34, 720), alignment: .leading)
    }

    // MARK: Bottom bar (progress hairline + pacing controls)

    private var chapterProgress: Double {
        guard let pag = displayedPagination, pag.wordCount > 1 else { return 0 }
        return Double(cursor) / Double(pag.wordCount - 1)
    }

    /// Plain-key shortcuts (Space/arrows) belong to the page only while no
    /// modal composer needs the keyboard.
    private var plainKeysActive: Bool {
        discussion == nil && noteTarget == nil
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            // A whisper of progress under the page.
            GeometryReader { geo in
                Capsule()
                    .fill(ReadingPalette.brand(scheme).opacity(0.4))
                    .frame(width: max(geo.size.width * chapterProgress, 2), height: 2)
            }
            .frame(width: min(fontSize * 34, 720, max(pageArea.width, 60)), height: 2)
            .opacity(displayedPagination == nil ? 0 : 1)

            HStack(spacing: 2) {
                // Plain-key shortcuts hand back to the keyboard while a
                // modal is open (Space/arrows must type in the composers).
                controlButton("chevron.left", help: "Previous page") { turnPage(-1) }
                    .keyboardShortcut(plainKeysActive
                        ? KeyboardShortcut(.leftArrow, modifiers: []) : nil)
                    .disabled(pageIndex == 0)

                Button(action: togglePlay) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ReadingPalette.brand(scheme))
                        .frame(width: 40, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(plainKeysActive
                    ? KeyboardShortcut(.space, modifiers: []) : nil)
                .help(isPlaying ? "Pause pacing" : "Start pacing")

                controlButton("chevron.right", help: "Next page") { turnPage(1) }
                    .keyboardShortcut(plainKeysActive
                        ? KeyboardShortcut(.rightArrow, modifiers: []) : nil)
                    .disabled(displayedPagination.map { pageIndex >= $0.pages.count - 1 } ?? true)

                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 8)

                Button {
                    showPaceControls.toggle()
                } label: {
                    Text("\(Int(wpm)) wpm")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(ReadingPalette.ink(scheme))
                        .frame(height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Reading pace")
                .popover(isPresented: $showPaceControls, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pace")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Image(systemName: "tortoise")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Slider(value: $wpm, in: PacingTunables.range, step: 10)
                                .frame(width: 190)
                            Image(systemName: "hare")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Text("\(Int(wpm)) words per minute")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                }

                if let pag = displayedPagination {
                    Text("\(pageIndex + 1) of \(pag.pages.count)")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(ReadingPalette.inkFaded(scheme))
                        .padding(.leading, 8)
                }

                if book != nil, chapterIndex + 1 < sortedChapters.count,
                   let pag = displayedPagination, pageIndex >= pag.pages.count - 1 {
                    nextChapterButton
                        .padding(.leading, 10)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(ReadingPalette.brand(scheme).opacity(0.18)))
        }
    }

    private func controlButton(
        _ symbol: String, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ReadingPalette.ink(scheme))
                .frame(width: 32, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var nextChapterButton: some View {
        Button {
            chapterIndex += 1
        } label: {
            HStack(spacing: 6) {
                Text("Next Chapter")
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(ReadingPalette.brand(scheme))
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private var backdrop: some View {
        RadialGradient(
            colors: [ReadingPalette.paperGlow(scheme), ReadingPalette.paper(scheme)],
            center: .init(x: 0.5, y: 0.25),
            startRadius: 0,
            endRadius: 900
        )
        .ignoresSafeArea()
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

// MARK: - Discussion (ticket 08: select → Define/Explain → threaded modal)

extension ReadingView {
    private var sortedThreads: [DiscussionThread] {
        (book?.threads ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    var historyButton: some ToolbarContent {
        ToolbarItem {
            Button {
                showHistory.toggle()
            } label: {
                Label("Discussions", systemImage: "bubble.left.and.bubble.right")
            }
            .help("Past discussions")
            .popover(isPresented: $showHistory, arrowEdge: .bottom) {
                ThreadHistoryList(
                    threads: sortedThreads,
                    onOpen: { thread in
                        showHistory = false
                        reopen(thread)
                    },
                    onDelete: { thread in
                        modelContext.delete(thread)
                    }
                )
            }
        }
    }

    @ViewBuilder
    var discussionOverlay: some View {
        if let discussion {
            DiscussionModal(controller: discussion, onClose: closeDiscussion)
                .transition(.opacity)
        }
    }

    func clearSelection() {
        guard selection != nil || selectionMenuShown else { return }
        withAnimation(reduceMotion ? .default : ReadingMotion.controls) {
            selection = nil
            selectionMenuShown = false
        }
    }

    func handleSelectionAction(_ action: SelectionAction) {
        switch action {
        case .dismiss:
            clearSelection()
        case .define, .explain:
            openDiscussion(kind: action == .define ? "define" : "explain")
        case .note:
            openNoteComposer()
        }
    }

    /// Fresh thread from the current selection. The reading position is
    /// deliberately untouched — closing the modal reveals the page exactly
    /// as it was, cursor included.
    private func openDiscussion(kind: String) {
        guard let pag = displayedPagination, let selection else { return }
        let range = selection.clamped(to: 0..<pag.wordCount)
        let words = pag.words[range]
        guard let first = words.first else { return }
        let text = words.map(\.plain).joined(separator: " ")

        isPlaying = false
        let thread = DiscussionThread(selectedText: text, kind: kind)
        thread.chapterIndex = chapterIndex
        thread.sectionIndex = first.sectionIndex
        // ContextAssembler wants the word index *within the section*.
        let sectionStart = pag.words.firstIndex { $0.sectionIndex == first.sectionIndex } ?? 0
        thread.wordIndex = first.id - sectionStart

        let context: AssembledContext
        if let book {
            modelContext.insert(thread)
            thread.book = book
            context = ContextAssembler.assemble(
                book: book,
                chapterIndex: chapterIndex,
                sectionIndex: first.sectionIndex,
                wordIndex: thread.wordIndex,
                selection: text
            )
        } else {
            context = sampleContext(selection: text)
        }

        let controller = DiscussionController(
            thread: thread,
            context: context,
            modelContext: modelContext,
            persists: book != nil
        )
        clearSelection()
        withAnimation(reduceMotion ? .default : .smooth(duration: 0.2)) {
            discussion = controller
        }
        controller.begin()
    }

    /// Reopen a stored thread from the history list — follow-ups resume the
    /// persisted Claude session; context is re-assembled from the thread's
    /// stored position in case that session is lost.
    private func reopen(_ thread: DiscussionThread) {
        guard let book else { return }
        isPlaying = false
        let context = ContextAssembler.assemble(
            book: book,
            chapterIndex: thread.chapterIndex ?? chapterIndex,
            sectionIndex: thread.sectionIndex ?? 0,
            wordIndex: thread.wordIndex,
            selection: thread.selectedText
        )
        let controller = DiscussionController(
            thread: thread, context: context, modelContext: modelContext
        )
        withAnimation(reduceMotion ? .default : .smooth(duration: 0.2)) {
            discussion = controller
        }
        controller.begin() // no-ops on threads that already have messages
    }

    private func closeDiscussion() {
        discussion?.cancel()
        withAnimation(reduceMotion ? .default : .smooth(duration: 0.18)) {
            discussion = nil
        }
    }

    /// Context for the no-book sample chapter: excerpt only, nothing
    /// persisted, no wiki on disk.
    private func sampleContext(selection: String) -> AssembledContext {
        let text = SampleChapter.source.sections.first?.text ?? ""
        return AssembledContext(
            workingDirectory: nil,
            systemPrompt: ContextAssembler.companionRole,
            contextBlock: """
            You are helping a reader inside a sample chapter titled \
            “The Shape of Attention”.

            The passage around the reader's position:
            <excerpt>
            \(text)
            </excerpt>

            The reader selected this text:
            <selection>\(selection)</selection>
            """
        )
    }
}

// MARK: - Notes (ticket 10: anchored passages, compose, list, jump-back)

extension ReadingView {
    /// A note anchor being navigated to (possibly across a chapter switch).
    struct NoteJump: Equatable {
        let chapterIndex: Int
        let sectionIndex: Int
        /// Word offset within the section (layout-independent).
        let wordIndex: Int
    }

    private var sortedNotes: [Note] {
        (book?.notes ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    /// Cheap fingerprint of this chapter's note anchors + the displayed
    /// pagination — global ranges are recomputed only when it changes, so
    /// the per-word cursor ticks never pay for anchor resolution.
    private var noteAnchorKey: NoteAnchorKey {
        let anchors = (book?.notes ?? []).flatMap { note -> [Int] in
            guard note.chapterIndex == chapterIndex else { return [] }
            return [note.sectionIndex ?? 0, note.wordIndex ?? 0, note.wordLength ?? 1]
        }
        return NoteAnchorKey(chapterID: displayedPagination?.chapterID, anchors: anchors)
    }

    struct NoteAnchorKey: Equatable {
        let chapterID: String?
        let anchors: [Int]
    }

    private func recomputeNoteRanges() {
        guard let book, let pag = displayedPagination else {
            noteRanges = []
            return
        }
        // One scan for section start offsets, then O(1) per note.
        var sectionStart: [Int: Int] = [:]
        for (i, word) in pag.words.enumerated() where sectionStart[word.sectionIndex] == nil {
            sectionStart[word.sectionIndex] = i
        }
        noteRanges = book.notes.compactMap { note in
            guard note.chapterIndex == chapterIndex,
                  let start = sectionStart[note.sectionIndex ?? 0] else { return nil }
            let lo = start + max(note.wordIndex ?? 0, 0)
            guard lo < pag.wordCount else { return nil }
            let hi = min(lo + max(note.wordLength ?? 1, 1), pag.wordCount)
            return lo..<hi
        }
    }

    // MARK: Compose

    /// Capture the selection as a note anchor and float the composer. The
    /// selection wash stays lit underneath so the reader sees exactly what
    /// the note will hold.
    private func openNoteComposer() {
        guard book != nil, let pag = displayedPagination, let selection else { return }
        let range = selection.clamped(to: 0..<pag.wordCount)
        let words = pag.words[range]
        guard let first = words.first else { return }
        isPlaying = false
        let sectionStart = pag.words.firstIndex { $0.sectionIndex == first.sectionIndex } ?? 0
        let target = NoteDraftTarget(
            excerpt: words.map(\.plain).joined(separator: " "),
            chapterIndex: chapterIndex,
            sectionIndex: first.sectionIndex,
            wordIndex: first.id - sectionStart,
            wordLength: range.count
        )
        withAnimation(reduceMotion ? .default : ReadingMotion.controls) {
            selectionMenuShown = false
        }
        withAnimation(reduceMotion ? .default : .smooth(duration: 0.2)) {
            noteTarget = target
        }
    }

    @ViewBuilder
    var noteComposerOverlay: some View {
        if let noteTarget {
            NoteComposer(
                target: noteTarget,
                onSave: { saveNote($0) },
                onCancel: dismissNoteComposer
            )
            .transition(.opacity)
        }
    }

    private func saveNote(_ thought: String) {
        guard let book, let target = noteTarget else { return }
        let note = Note(
            anchoredText: target.excerpt,
            chapterIndex: target.chapterIndex,
            sectionIndex: target.sectionIndex,
            wordIndex: target.wordIndex,
            wordLength: target.wordLength,
            source: "selection",
            text: thought
        )
        modelContext.insert(note)
        note.book = book
        noteSaves += 1
        dismissNoteComposer()
        // The underline fades in as the composer leaves.
        recomputeNoteRanges()
    }

    private func dismissNoteComposer() {
        withAnimation(reduceMotion ? .default : .smooth(duration: 0.18)) {
            noteTarget = nil
        }
        clearSelection()
    }

    // MARK: List + jump-back

    var notesButton: some ToolbarContent {
        ToolbarItem {
            Button {
                showNotes.toggle()
            } label: {
                Label("Notes", systemImage: "bookmark")
            }
            .help("This book's notes")
            .popover(isPresented: $showNotes, arrowEdge: .bottom) {
                NotesList(
                    notes: sortedNotes,
                    chapterTitles: Dictionary(
                        uniqueKeysWithValues: sortedChapters.enumerated()
                            .map { ($0.offset, $0.element.title) }
                    ),
                    onOpen: { note in
                        showNotes = false
                        jump(to: note)
                    },
                    onDelete: { note in
                        modelContext.delete(note)
                        recomputeNoteRanges()
                    }
                )
            }
        }
    }

    /// Ride back to the note's passage: same chapter jumps immediately;
    /// another chapter switches and completes the jump when its pagination
    /// lands (see `present`).
    private func jump(to note: Note) {
        guard book != nil, let targetChapter = note.chapterIndex else { return }
        isPlaying = false
        let jump = NoteJump(
            chapterIndex: targetChapter,
            sectionIndex: note.sectionIndex ?? 0,
            wordIndex: note.wordIndex ?? 0
        )
        if targetChapter == chapterIndex, let pag = displayedPagination {
            apply(jump, in: pag)
        } else {
            pendingJump = jump
            chapterIndex = targetChapter
        }
    }

    /// Land the cursor on the note's first word — the amber cursor itself
    /// marks the spot, resting on the underlined passage.
    func apply(_ jump: NoteJump, in pag: PaginatedChapter) {
        guard pag.wordCount > 0 else { return }
        let sectionStart = pag.words.firstIndex { $0.sectionIndex == jump.sectionIndex } ?? 0
        let global = min(max(sectionStart + jump.wordIndex, 0), pag.wordCount - 1)
        let targetPage = pag.pageIndex(ofWord: global)
        turnDirection = targetPage >= pageIndex ? 1 : -1
        withAnimation(reduceMotion ? .default : ReadingMotion.pageTurn) {
            pageIndex = targetPage
            cursor = global
        }
        persistPosition()
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

#Preview {
    ReadingView()
}
