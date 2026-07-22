# PDF import pipeline & minimal library

Type: task (AFK)
Status: closed (2026-07-22)
Assignee: Jonas Wahringer
Blocked by: 01, 02

## Question

Implement the recommended extraction pipeline: file importer for PDFs, PDFKit extraction, chapter/section structuring into SwiftData Book/Chapter/Section models, and a minimal library list to open a book into the reading view. Verify against at least two real PDFs (ask the user to supply one they actually want to read — that supply is a small HITL sub-step). Record pipeline limitations discovered.

## Answer

Implemented and verified end-to-end. The user supplied `/Users/jonasw/localdocs/books` as the source library (9 PDFs).

**What was built**

- `Freeloader/Import/PDFExtraction.swift` — pure pipeline (no SwiftUI/SwiftData, so a CLI harness can compile it standalone): open/gate (locked + scanned PDFs rejected at median < 200 chars/page), per-page line model with dominant font size/weight/mono from `attributedString` runs, ligature normalization, furniture stripping (digit-normalized lines repeating across ≥ max(3, pages/8) pages, bare page numbers, small repeated artifacts), heading detection (≥1.4× body size, or bold ≥1.2×; mostly-symbol lines like display math excluded), multi-line heading merge with hyphen repair, bare "Chapter N" labels absorbing the following title heading, chapter tier via explicit Chapter/Part/Appendix regex else largest font tier, paragraph reflow (hyphenation repair; break on sentence-final short line vs median line length). Front matter kept as a skippable "Front Matter" chapter.
- `Freeloader/Import/PDFImporter.swift` — runs extraction off-main, populates `Book → Chapter → BookSection` (paragraphs joined with `\n\n` in `BookSection.text`), seeds `ReadingPosition` at the first non-front-matter chapter.
- `Freeloader/ContentView.swift` — minimal library: empty state with Import CTA, `.fileImporter` (PDF only), progress overlay, error alert, book rows (title, author, chapter count), swipe-delete, `NavigationLink` → reading view.
- `Freeloader/Reading/ReadingView.swift` — now takes an optional `Book`: renders real chapters (section titles + bionic paragraphs), chapter picker in the toolbar, Next Chapter button, chapter index persisted to `ReadingPosition`. Sample content remains the no-book preview.
- App root switched from bare `ReadingView` to `ContentView`.

**Verification** (CLI harness compiling the shared pipeline source + a SwiftData in-memory `PDFImporter` test; scratchpad `probe`/`importtest`)

- *The Pragmatic Programmer* (352 pp): 11 chapters ("Chapter 1 · A Pragmatic Philosophy" …), 237 sections, ~99K words, 3.3s total. Paragraphs read naturally.
- *Intro to Modeling and Analysis of Complex Systems* (Sayama, 498 pp): 20 chapters, 106 numbered sections (1.1, 1.2 …), ~116K words, 4.4s.
- *Designing Data-Intensive Applications* (613 pp): 16 chapters incl. PART headings, 233 sections, ~227K words, 7s.
- SwiftData population verified in-memory for two books; macOS build + launch OK; iOS simulator build OK.

**Limitations recorded**

- LLM structure pass deferred to ticket 07 (ClaudeService doesn't exist yet) — structuring is the research's heuristics-only fallback. Heading candidates and TOC text are available for the later upgrade.
- Epigraphs/quotes at section starts merge into the first paragraph; back-matter index pages fragment into one-letter sections; occasional large-font figure/diagram text becomes a spurious section title (all cosmetic, non-blocking).
- PART headings (DDIA) become chapters at the same level as CHAPTER headings — no Part→Chapter nesting in the model.
- Known-from-research gaps unchanged: multi-column PDFs interleave, figures/tables lost in reflow (already in fog).
- Environment quirk: this Xcode 26.6 install fails scheme-based destination resolution for iOS Simulator ("supported platforms … empty"); use `xcodebuild -target Freeloader -sdk iphonesimulator -arch arm64 build` instead.
