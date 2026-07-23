# Prototype: WPM highlight cursor & page-turn animations

Type: prototype (HITL)
Status: resolved (agent, pending user review)
Blocked by: 04

## Question

How should pacing feel? On top of the approved reading view, build: the highlight cursor sweeping word-by-word at a configurable WPM (word-length/punctuation-weighted timing?), the WPM control, line-transition animation, auto page-turn when the cursor reaches page end, plus manual page-turn scroll behavior. Pause/resume and scrub-back-to-cursor behavior included. Consult `/ios-animations`. Iterate with the user until the motion feels right.

User direction (from ticket 04 review, 2026-07-22): the cursor should **magnify words like the macOS Dock magnifies icons on hover** — as the cursor sweeps left to right, the current word scales up with neighbors swelling slightly in a falloff curve. The user called getting this right (together with word spacing) the biggest open issue.

## Resolution

Built (commit 1ac197c) on top of ticket 12's ChapterBuilder cache:

- **Pagination** (`Freeloader/Reading/Pagination.swift`): a `Paginator` actor (off-main, LRU cache) slices ticket 12's `BuiltParagraph`s into per-word attributed runs, measures each word with CoreText using the same New York serif SwiftUI draws (bold prefix + regular tail, width cache keyed by word), and lays out absolutely-positioned word frames into fixed pages sized to the window. Chapter header and section titles are measured blocks (a section title never strands at a page bottom). Invariant harness verified: no overlaps, ranges exact, all frames in bounds; 2,278 words paginate in 34 ms.
- **THE HEADLINE — Dock-style magnification**: every word is its own `Text` at a computed frame (`PageView.swift`), so the cursor magnifies purely via `scaleEffect` — zero reflow, zero layout jitter. Current word scales to 1.24; same-line neighbors swell with a raised-cosine falloff over 2.6 words; anchor at (0.5, 0.82) so words grow upward off the baseline like Dock icons off the shelf. All tunables in `MagnifierTunables`. `WordGlyph` is Equatable, so a cursor tick re-renders only the handful of words whose scale changed.
- **Cursor**: one amber capsule slides beneath the current word with a `.smooth(0.26)` spring (single `withAnimation` per tick, driven by one async loop sleeping per-word intervals — no timer storms). Pacing weight = 0.55 flat + 0.09/letter, +0.45 clause punctuation, +1.1 sentence end, +0.7 paragraph joint, clamped 0.6–3.6 (`PacingTunables`).
- **Controls**: bottom capsule bar — page back / play-pause (Space) / page forward (←/→), WPM popover slider 100–600, "page N of M", plus a 2pt amber chapter-progress hairline. Next Chapter appears in the bar on the last page. Click any word to move the cursor there; horizontal swipe turns pages (iPad). Chapter end auto-pauses; pressing play on a finished chapter restarts it.
- **Page turns**: auto when the cursor crosses the fold; 44pt drift + fade (`.smooth(0.32)`), direction-aware for back/forward. Reduce Motion: crossfade only, magnification off.
- **Persistence**: `ReadingPosition` (created lazily if missing) stores chapterIndex/sectionIndex/wordIndex/WPM; written on pause, page turn, chapter switch, disappear, and every 25 words while playing; restored on open.

Key decisions / for morning review:

1. **Word-per-Text render path** replaces the paragraph-Text scroll column — pagination + magnification need per-word frames. ChapterBuilder's cache and bionic pipeline are fully reused (pagination slices its output); but `.textSelection` was lost with the scroll column — Define/Explain selection (later tickets) should select via word hit-testing instead, which the frames make easy.
2. **Aesthetic knobs to taste-test**: `MagnifierTunables.maxScale` (1.24), `radius` (2.6 words), anchor y (0.82); pacing bonuses; page drift 44pt. Average pacing weight measures ~1.11, so effective speed runs ~10% under nominal WPM — normalize per-chapter if that bothers you.
3. Magnification swells only the cursor's own line (no vertical bulge) and never repositions neighbors — scale only, per your "no reflow" direction. If you want the Dock's *push-apart* feel, that would need animated x-offsets; deliberately skipped to keep lines rock-steady.
4. Window resize / font change repaginates off-main and keeps your word; the old layout stays visible until the new one lands (same stale policy as ticket 12).
5. Could not runtime-test against a real imported book from this session (no GUI); pagination verified by compiled invariant harness instead. First real-book run worth a morning glance: page density, magnification feel at 25pt, and WPM feel around 250.
