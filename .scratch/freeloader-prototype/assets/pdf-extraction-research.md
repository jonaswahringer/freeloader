# Research: PDF text extraction & structure detection

Asset for [02-pdf-extraction-research](../issues/02-pdf-extraction-research.md). Empirical findings from probing `the-pragmatic-programmer.pdf` (352 pp, Pragmatic Bookshelf, 2012) with PDFKit on macOS 26.2 / Xcode 26.6; probe script: scratchpad `probe_pdf.swift`.

## Empirical findings

- **Extraction is fast and correctly ordered.** `PDFPage.string` returned clean, reading-ordered text on every sampled page. Full 352-page extraction (617K chars) took **0.72s** — import-time extraction can run in one background task, no incremental machinery needed.
- **Do not count on outline metadata.** This professionally produced book has **no PDF outline** (`outlineRoot == nil`). Document attributes (Title, Author) were present — use them to prefill Book metadata, with filename fallback.
- **Font runs make headings detectable.** `PDFPage.attributedString` exposes `.font` per run. Body text is 9–10pt; the section heading "Stone Soup and Boiled Frogs" is a **20.9pt** run. Rule: body size = mode of run sizes across the book; heading candidate = line whose dominant run is ≥ ~1.5× body size (or bold + larger).
- **Running headers/footers are real and must be stripped.** Every page starts with a header line ("6 CHAPTER 1 A PRAGMATIC PHILOSOPHY" / "STONE SOUP AND BOILED FROGS 7"). Headers use fake small caps — alternating 9pt/7.2pt runs — so font-run analysis also flags them. This PDF adds a per-page 7pt watermark line ("Prepared exclusively for Zach").
- **Hyphenation survives extraction** ("envi-\nronment") and must be repaired when reflowing.
- **Chapter headers give free structure confirmation:** the running header encodes the current chapter ("CHAPTER 1 A PRAGMATIC PHILOSOPHY"), and the book's printed TOC pages are plain extractable text — both are ideal LLM-assist inputs.

## Recommended pipeline (for ticket 06)

1. **Open & gate.** `PDFDocument(url:)`; reject locked docs. Compute chars/page; if median page yields < ~200 chars, treat as scanned → unsupported (clear user message; OCR is out of scope).
2. **Per-page line model.** From `attributedString`, build lines annotated with dominant font size/weight (split page text on newlines; attribute each line from its runs).
3. **Strip furniture.** Drop lines that repeat across many pages modulo digits (running headers, watermarks, bare page numbers); tiny-font (< ~0.8× body) repeated lines are furniture too. Fake-small-caps alternating-size runs are a corroborating signal.
4. **Reflow paragraphs.** Merge consecutive lines into paragraphs; repair hyphenated breaks (`-\n` + lowercase continuation → join); paragraph break on short trailing line, terminal punctuation + next-line indent shift, or blank line.
5. **Detect heading candidates.** Font-size/weight outliers vs body mode, plus numbering patterns (`^\d+\s+Title`, `Chapter \d+`). Keep page index + text for each candidate.
6. **LLM structure pass (one call).** Send Claude: document attributes, printed-TOC page text (find via "Contents" heading early in the book), candidate heading list with page numbers, and running-header samples. Ask for the confirmed Chapter → Section hierarchy as JSON (titles + start pages/heading ids). This resolves ambiguity (front matter, part pages, sidebar titles) far more robustly than pure heuristics. Heuristics-only fallback: accept candidates as flat sections when the LLM is unavailable.
7. **Populate models.** Slice paragraph stream at confirmed headings → `Book → Chapter → BookSection` (SwiftData), storing cleaned text per section. Keep front matter (title page, TOC, preface) as a skippable "Front matter" chapter rather than dropping it.

## Known failure modes

- **Multi-column layouts** (academic papers): PDFKit emits content-stream order, which can interleave columns. Not detected/repaired in this pipeline — v1 targets book-like single-column PDFs; note in import UI copy.
- **Footnotes/sidebars/code blocks** get inlined into the paragraph stream at their layout position. Mostly tolerable in books; code blocks lose indentation subtleties (paragraph-merge should skip lines whose font is monospace — check font name for `Mono`/`Courier`).
- **Fake small caps** produce case-mangled text if a *heading* (not just furniture) uses them — titles may need case repair via the LLM pass.
- **Scanned/image PDFs** yield no text → gated out at step 1 (out of scope).
- **Ligatures/unicode oddities** (fi/fl) occasionally extract as private-use glyphs in older PDFs — normalize with a small replacement table.
- `attributedString` has no geometry; if a future need requires line positions (e.g. figure regions), `PDFSelection` bounds or Core Graphics parsing would be needed — deliberately avoided for v1.

## Performance note

Extraction + heuristics will be well under a few seconds per book; the LLM structure pass dominates wall time. Run the whole import as one background task with progress UI, and let reading start before the LLM pass lands (flat sections upgraded in place when structure arrives).
