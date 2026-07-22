# Research: PDF text extraction & structure detection

Type: research (AFK)
Status: resolved

## Question

How do we reliably turn a text-based PDF into reflowable, chapter-structured text? Investigate PDFKit's extraction APIs (per-page text, attributed strings, reading order quirks), heuristics for detecting chapters/sections/paragraph boundaries (font size jumps, outline/TOC metadata, page headers/footers to strip), and where an LLM assist pays off in structure detection. Deliver a markdown summary (linked asset) with a recommended extraction pipeline and its known failure modes.

## Answer

Resolved 2026-07-22 by empirically probing PDFKit against `~/localdocs/books/swe/the-pragmatic-programmer.pdf` (352 pp). Full findings and the recommended 7-step pipeline: **[assets/pdf-extraction-research.md](../assets/pdf-extraction-research.md)**.

Headlines: `PDFPage.string` gives fast (0.7s/book), correctly ordered text; outline metadata is absent even in professional books, so structure comes from font-size heuristics (`attributedString` runs: 20.9pt headings vs 9pt body) confirmed by a single LLM structure pass over the printed TOC + heading candidates; running headers/footers/watermarks repeat per page and are strippable; hyphenation must be repaired on reflow. Scanned PDFs are gated out by chars-per-page; multi-column layouts are a known unhandled failure mode.
