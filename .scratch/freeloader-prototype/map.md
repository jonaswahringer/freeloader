# Wayfinder map: Freeloader prototype

Label: wayfinder:map

## Destination

A working prototype of **Freeloader** — a SwiftUI multiplatform (macOS-first, iPadOS-compatible) reading & learning app — proving all four pillars end-to-end on macOS: bionic paced reading of imported PDFs, Claude-powered wiki/define/explain, retention testing, and anchored notes.

## Notes

- **Execution override:** the destination is a working prototype, so this map *carries execution* — tickets build the thing, not just decide it.
- Domain: ADHD-friendly reading/learning tool ("An ADHD-Reader and Learning Tool for GEN-Z hyperactivists", see README).
- Skills to consult per ticket: `/prototype`, `/frontend-design`, `/ios-taste`, `/ios-animations` for UI tickets; `/grilling` + `/domain-modeling` when a decision resurfaces; `/research` for research tickets.
- Tracker: local markdown (this directory). Tickets in `issues/NN-<slug>.md`; `Blocked by:` lines are the dependency edges; frontier = open, unblocked, unclaimed, lowest number first.
- Dev environment: user's Mac, Xcode; Claude CLI available and authenticated via subscription.

## Decisions so far

- Destination is a **working prototype**, full-featured: core reading + PDF import + Define/Explain/LLM wiki + retention & notes (grilling, 2026-07-22).
- **Platform:** SwiftUI multiplatform, macOS-first; iPad layouts kept working along the way.
- **LLM backend:** Claude Code CLI headless (`claude -p`) on macOS via user's subscription; no API key, no server. iPad LLM deferred (fog).
- **Reading mode:** full bionic page (bold prefixes) with a highlight cursor sweeping word-by-word at the user's WPM, auto page-turns; pacing guides, doesn't force.
- **PDF import:** text-based PDFs via PDFKit, reflowed into our renderer; chapter/section detection heuristic + LLM assist. No OCR.
- **Wiki:** internal context only — background analysis writes per-chapter summaries/glossary/key ideas as markdown files feeding Define/Explain and retention grading. No wiki UI.
- **Define/Explain UX:** modal over the reading view; expandable follow-up thread inside the modal; threads saved to history; back/close returns to exact reading position.
- **Retention:** prompt at section/chapter boundaries when the cursor crosses them; skippable; Claude grades against the wiki.
- **Notes:** anchored to selected passages ('Note' beside Define/Explain), save-to-notes from threads, per-book notes list with jump-back.
- **Storage:** SwiftData for books/positions/threads/notes; wiki as markdown files per book. Local only.
- [Scaffold the Freeloader Xcode project](issues/01-scaffold-xcode-project.md) — done: multiplatform target (bundle id `com.wahringer.freeloader`, macOS 15+/iPadOS 18+, unsandboxed for CLI spawning), SwiftData stub models, builds & launches on macOS and iPad simulator.
- [Research: PDF text extraction & structure detection](issues/02-pdf-extraction-research.md) — PDFKit extraction is fast & ordered; no outline metadata in real books, so structure = font-size heuristics + one LLM pass over printed TOC; strip repeating headers/footers, repair hyphenation; scanned PDFs gated out. Pipeline in [assets/pdf-extraction-research.md](assets/pdf-extraction-research.md).
- [Prototype: bionic reading view (static)](issues/04-bionic-reading-view-prototype.md) — approved: dark-by-default warm-paper page (amber seed 38°), serif bionic rendering (bold prefix full ink / tail 62%), extra-wide word gaps (kern 0.28×size), 25pt default with animated resize, amber cursor-highlight language. View code in `Freeloader/Reading/ReadingView.swift`.
- [Research: invoking the Claude CLI headless from a macOS app](issues/03-claude-cli-integration-research.md) — verified: `claude -p --output-format json` works on subscription auth from GUI-spawned processes (Keychain-based; must locate binary explicitly); threads via `--resume` session ids (cwd-scoped); constrain with `dontAsk` + `--allowedTools Read`, `--max-turns ≥ 8`. ClaudeService design in [assets/claude-cli-research.md](assets/claude-cli-research.md).

- [PDF import pipeline & minimal library](issues/06-pdf-import-pipeline.md) — done: PDFKit pipeline (gate → furniture strip → reflow → heading heuristics) into Book/Chapter/BookSection, minimal library with file importer, reading view wired to real chapters. Verified on 3 real books (99K–227K words, 3–7s); LLM structure pass deferred to ticket 07; heuristics-only limitations recorded in the ticket.

## Not yet specified

- iPad LLM strategy — direct Anthropic API with pasted key, or on-device models; sharpens once ClaudeService exists and its prompt surface is known.
- App Sandbox / distribution story — spawning the `claude` CLI likely conflicts with the App Sandbox; fine unsandboxed for a dev prototype, but signing/notarization/App Store needs a real answer later.
- iCloud sync of positions/notes/threads across devices.
- Handling figures, tables, and images lost in reflow (possible original-PDF side view); multi-column PDFs (reading order interleaves) likewise unhandled.
- Library/onboarding polish beyond a minimal book list.

## Out of scope

- **Browsable wiki UI** — ruled a future nice-to-have during grilling; wiki stays internal machinery in this effort.
- **OCR for scanned/image PDFs** — text-based PDFs only.
- **Backend service / BYO API key paths** — Claude CLI only for this prototype.
