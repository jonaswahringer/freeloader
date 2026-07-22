# Research: PDF text extraction & structure detection

Type: research (AFK)
Status: open

## Question

How do we reliably turn a text-based PDF into reflowable, chapter-structured text? Investigate PDFKit's extraction APIs (per-page text, attributed strings, reading order quirks), heuristics for detecting chapters/sections/paragraph boundaries (font size jumps, outline/TOC metadata, page headers/footers to strip), and where an LLM assist pays off in structure detection. Deliver a markdown summary (linked asset) with a recommended extraction pipeline and its known failure modes.
