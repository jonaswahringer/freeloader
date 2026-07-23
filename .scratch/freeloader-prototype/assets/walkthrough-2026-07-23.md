# Freeloader morning walkthrough — 2026-07-23

Prepared overnight by the walkthrough agent (ticket 11). This is your checklist for
walking the full loop yourself. Everything below marked **verified** was exercised
automatically last night; everything marked **try** needs your hands and eyes.

## What was verified automatically last night

- **macOS build**: clean (`platform=macOS`).
- **iPad build**: clean (built via `-sdk iphonesimulator -arch arm64`; xcodebuild's
  simulator destination matching is still broken on this machine — see Environment notes).
- **macOS app launch**: launched from DerivedData, ran for 10+ minutes, zero stderr output, no crash.
- **iPad simulator launch**: installed and launched on the "iPad Pro 11 (build)" iOS 26.3
  simulator; empty-library screen renders correctly (screenshot in the session scratchpad).
- **ClaudeService live from the .app bundle**: on launch, the retroactive wiki scan
  spawned the real `claude -p` CLI (no Keychain consent blocker — the corner from
  ticket 03 did NOT bite). Real wiki files were generated for *The Pragmatic Programmer*
  (your one imported book): `~/Library/Application Support/Freeloader/Wiki/<id>/chapters/NN-{summary,glossary,key-ideas}.md`.
  Spot-checked the Front Matter summary — coherent and faithful. Generation was still
  in flight when the agent finished; whatever is incomplete resumes on next launch.
  Note: this spent some subscription quota overnight (~1 sonnet call/chapter).
- **Import pipeline headlessly**: compiled `PDFExtraction.swift` into a harness and ran it
  on real PDFs from ~/Downloads. A 4-page text PDF (SCRUM.pdf) extracted correctly
  (1 chapter, 281 words); a scanned PDF (rhetorische Figuren Übersicht.pdf) was properly
  gated with the friendly "no extractable text" error.
- **Code audit of the full loop**: import → paced bionic reading → select →
  Define/Explain/Note → thread history / notes list → jump-back is fully wired in code
  (ReadingView glue confirmed). SwiftData store currently holds 1 book, 11 chapters,
  0 threads, 0 notes — the interactive half is untouched and waiting for you.

## The walkthrough (30–40 min)

### 1. Library & import (5 min)
- Launch the app. *The Pragmatic Programmer* should be listed; if its wiki is still
  generating you'll see a small amber progress ring on the row (tooltip shows N of M).
- Import a second PDF (any text-based one; SCRUM.pdf in ~/Downloads works).
  Watch for: import speed, chapter count sanity, the wiki ring appearing.
- Try a scanned/image PDF and confirm the friendly rejection alert.

### 2. Paced bionic reading (10 min) — ticket 05's headline
- Open the book. Press Space to start the cursor.
- **The big question**: does the Dock-style magnification feel right at 25pt?
  Current word scales to 1.24, neighbors swell in a raised-cosine falloff over 2.6 words,
  growing upward off the baseline. Scale-only, no reflow — lines stay rock-steady.
- WPM slider (100–600, popover in the bottom bar): does ~250 feel like "guided, not forced"?
  Note: punctuation/word-length weighting means effective speed runs ~10% under nominal.
- Click a word to move the cursor; arrow keys / swipe to turn pages; auto page-turn at
  the fold (44pt drift + fade); chapter-end auto-pause; Next Chapter button on last page.
- Resize the window and change font size — repagination keeps your word, off-main.
- Quit and relaunch — position and WPM should restore exactly.

### 3. Define / Explain (10 min) — first live GUI run
- Drag across a passage (drag must start on a word; whitespace drags turn pages).
  The amber selection wash should read quieter than the pacing cursor.
- Try **Define** on a term the glossary knows — the answer should be grounded in the
  wiki ("Consulting the book's notes…" pulse while thinking).
- Ask a follow-up in the thread. Close, reopen from the Discussions toolbar popover,
  ask another follow-up — it should resume the same CLI session (days-later resume works too).
- Check: reading position untouched under the modal; Esc/scrim-tap closes.

### 4. Notes (8 min)
- Select a passage → **Note** → add a thought (or none — bare highlight is valid) → Save.
- Look for the faint 2pt amber underline — the "pencil line". Does it fight the bionic text?
- Inside a Define thread, tap "Save to notes" under an answer.
- Open the Notes popover (bookmark icon) → tap a note in a *different* chapter →
  it should page over and land the cursor on the passage. No flash/pulse on arrival —
  judge whether the cursor landing is marker enough.

### 5. iPad (5 min)
- Run on the iPad simulator (or your iPad): reading, paging, selection, notes all work;
  Define/Explain fails gracefully with the unavailability message (expected — no iPad
  LLM strategy yet).

## Known gaps (recorded, not bugs)

- **Retention tests (ticket 09) were NOT built** — deliberately out of tonight's scope.
  The prompt-at-section-boundary piece of the destination loop is missing; the wiki
  it would grade against exists. This is the main remaining pillar.
- No token streaming in the modal — answers land whole (CLI transport is one-shot JSON;
  `--output-format stream-json` is the follow-up if wanted).
- Note anchors don't survive re-import of the same PDF (word offsets shift);
  `anchoredText` is stored as a future re-anchoring fallback.
- Overlapping notes draw indistinguishable stacked underlines.
- Schema-valid junk wiki generations (seen once: `summary: "test"`) aren't caught by
  retry logic — if a wiki file looks like nonsense, delete it and relaunch.
- Figures/tables/images are lost in reflow; multi-column PDFs interleave.
- Heuristic chapter detection is coarse on some books — Pragmatic Programmer came out
  as 11 chapters with only 5 wiki-eligible; the LLM structure pass from ticket 02's
  research is still unbuilt.
- iPad LLM strategy still fog (map: "Not yet specified").

## Tunable knobs (all one-liners)

| What | Where | Current |
|---|---|---|
| Magnification max scale | `MagnifierTunables.maxScale` (PageView/Pagination area) | 1.24 |
| Magnification falloff radius | `MagnifierTunables.radius` | 2.6 words |
| Magnification anchor (grow-upward) | anchor y | 0.82 |
| Pacing weights (punctuation, length) | `PacingTunables` (ReadingView.swift) | 0.55 + 0.09/letter, +0.45 clause, +1.1 sentence |
| Page-turn drift | ReadingView page transition | 44pt |
| Note underline opacity/weight | `ReadingPalette.noteUnderline` | 0.42 dark / 0.5 light, 2pt |
| Selection wash | `ReadingPalette.selectionHighlight` | quieter than cursor |
| Modal size | DiscussionModal | 580×620 max |
| Wiki chapter eligibility / bounding | `WikiTuning` (WikiGenerator.swift) | min 120 words; >9000 words head-70/tail-30 |
| Chapter cache capacity | `ChapterBuilder.capacity` | 24 |
| Claude binary override | UserDefaults `ClaudeBinaryPath` | auto-lookup |

## Open aesthetic questions (collected from tickets 05/07/08/10/12)

1. Magnification feel: maxScale/radius/anchor — the user called this + word spacing
   "the biggest open issue". Want the Dock's *push-apart* feel? That needs animated
   x-offsets (deliberately skipped to keep lines steady).
2. Effective WPM runs ~10% under nominal — normalize per-chapter?
3. Font-size changes no longer animate the re-layout (that animation caused the lag).
   Miss the "breathing" resize? A crossfade between built columns is the cheap option.
4. Wiki completion is silent (ring just disappears) — want a subtle "notes ready" moment?
5. Should Explain be offered on single words too (currently both actions always shown)?
6. Thread history and Notes are popovers — with volume, do they deserve a sidebar/sheet?
7. Jump-to-note has no arrival pulse — is the cursor landing enough?
8. Modal scrim strength, max width/height.

## Environment notes

- xcodebuild cannot resolve *any* iOS Simulator destination right now (simctl sees the
  devices fine; likely the passcode-locked iPhone on iOS 26.5 confusing destination
  matching, as ticket 08 diagnosed). Workaround used throughout: build with
  `-sdk iphonesimulator -arch arm64`, then `simctl install/launch`. A restart of
  CoreSimulator/Xcode may clear it.
- The macOS app was left running after verification; if wiki generation didn't finish,
  it resumes next launch (state is on disk).

## Verdict prep (for you to declare)

Three of four pillars are live end-to-end: paced bionic reading of imported PDFs,
Claude-powered define/explain grounded in the auto-generated wiki, and anchored notes.
The fourth pillar — retention testing (ticket 09) — is unbuilt. Destination is
therefore *not yet* reached by the map's own definition; ticket 09 is the remaining
chart. Everything else on this list is polish or recorded fog.
