import SwiftUI

// 0.5s: a warm paper page — one serene serif column with rhythmic bold
// word-starts, floating on parchment; a single amber word marks the reader.
// User: an easily-pulled-away reader settling in for a focused session.
// Emotional intent: CALM / FOCUSED — zero chrome, the screen IS the page.

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

// MARK: - Bionic rendering

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

    static func attributed(
        _ paragraph: String,
        size: CGFloat,
        scheme: ColorScheme,
        highlightWordIndex: Int? = nil
    ) -> AttributedString {
        let ink = ReadingPalette.ink(scheme)
        let faded = ReadingPalette.inkFaded(scheme)
        var result = AttributedString()
        let words = paragraph.split(separator: " ", omittingEmptySubsequences: false)
        for (i, word) in words.enumerated() {
            if i > 0 {
                var gap = AttributedString(" ")
                gap.font = .system(size: size, design: .serif)
                gap.kern = size * 0.28
                result += gap
            }
            var rendered = bionicWord(String(word), size: size, ink: ink, faded: faded)
            if i == highlightWordIndex {
                rendered.backgroundColor = ReadingPalette.cursorHighlight(scheme)
            }
            result += rendered
        }
        return result
    }

    private static func bionicWord(
        _ word: String, size: CGFloat, ink: Color, faded: Color
    ) -> AttributedString {
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

        var head = AttributedString(String(word[word.startIndex..<boldEnd]))
        head.font = .system(size: size, weight: .bold, design: .serif)
        head.foregroundColor = ink

        var tail = AttributedString(String(word[boldEnd...]))
        tail.font = .system(size: size, weight: .regular, design: .serif)
        tail.foregroundColor = faded

        return head + tail
    }
}

// MARK: - Display content

struct DisplaySection {
    let title: String?
    let paragraphs: [String]
}

struct DisplayChapter {
    let kicker: String
    let title: String
    let sections: [DisplaySection]
}

// MARK: - Sample content

struct SampleChapter {
    let kicker = "Chapter 3"
    let title = "The Shape of Attention"
    let paragraphs: [String] = [
        "Attention is not a spotlight you aim; it is a current you enter. Every reader knows the feeling of the current catching — the page dissolves, the room goes quiet, and the words stop being ink and start being thought. The tragedy of most reading tools is that they interrupt precisely this moment, mistaking engagement for stimulation.",
        "The eye does not read letter by letter. It leaps in saccades, landing three or four characters into a word and inferring the rest from shape and context. A skilled reader recognizes whole word-forms the way a face is recognized: instantly, and without inspection. Anchoring the first few letters of each word gives the leaping eye a place to land — a stepping-stone path across the sentence.",
        "This is why pacing matters more than speed. A metronome does not make a pianist faster; it makes her steady. When the pace is steady, the mind stops negotiating with itself about whether to continue, and the decision to read the next word — a decision the distracted mind makes hundreds of times a minute — is quietly retired.",
        "What remains is comprehension, which has its own rhythm. Ideas arrive in paragraphs, not words. A reader who moves steadily through the text but pauses at its joints — the end of a section, the turn of an argument — retains more than one who sprints and rereads. The joints are where understanding is assembled.",
        "So the instrument we want is neither a speed-reader nor a teleprompter. It is closer to a quiet companion: one finger resting on the line, moving at your pace, patient at the joints, and silent the rest of the time."
    ]
}

// MARK: - Reading view

struct ReadingView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var fontSize: CGFloat = 25
    @State private var showTypeControls = false
    @State private var chapterIndex: Int = 0

    var book: Book?

    private var lineSpacing: CGFloat { fontSize * 0.58 }
    private var columnWidth: CGFloat { min(fontSize * 34, 720) }

    private var sortedChapters: [Chapter] {
        (book?.chapters ?? []).sorted { $0.index < $1.index }
    }

    private var chapter: DisplayChapter {
        guard let book else {
            let sample = SampleChapter()
            return DisplayChapter(
                kicker: sample.kicker,
                title: sample.title,
                sections: [DisplaySection(title: nil, paragraphs: sample.paragraphs)]
            )
        }
        let chapters = sortedChapters
        guard chapters.indices.contains(chapterIndex) else {
            return DisplayChapter(kicker: book.title, title: "Empty Book", sections: [])
        }
        let ch = chapters[chapterIndex]
        return DisplayChapter(
            kicker: book.title,
            title: ch.title,
            sections: ch.sections.sorted { $0.index < $1.index }.map {
                DisplaySection(
                    title: $0.title,
                    paragraphs: $0.text.components(separatedBy: "\n\n").filter { !$0.isEmpty }
                )
            }
        )
    }

    var body: some View {
        ZStack {
            backdrop

            ScrollView {
                VStack(alignment: .leading, spacing: lineSpacing * 1.6) {
                    header
                        .padding(.bottom, lineSpacing)

                    ForEach(Array(chapter.sections.enumerated()), id: \.offset) { _, section in
                        if let title = section.title {
                            Text(title)
                                .font(.system(size: fontSize * 1.25, weight: .semibold, design: .serif))
                                .foregroundStyle(ReadingPalette.ink(scheme))
                                .padding(.top, lineSpacing)
                        }
                        ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, para in
                            Text(Bionic.attributed(
                                para,
                                size: fontSize,
                                scheme: scheme
                            ))
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
                .frame(maxWidth: columnWidth, alignment: .leading)
                .padding(.horizontal, 48)
                .padding(.top, 64)
                .padding(.bottom, 120)
                .frame(maxWidth: .infinity)
                .animation(.smooth(duration: 0.35), value: fontSize)
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
            Text(chapter.kicker.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(3.2)
                .foregroundStyle(ReadingPalette.brand(scheme))
            Text(chapter.title)
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
