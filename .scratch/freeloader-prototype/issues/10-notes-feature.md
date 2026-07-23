# Notes: anchored passages & save-from-thread

Type: task (AFK)
Status: resolved (agent, pending user review)
Blocked by: 04, 08

## Question

Implement notes: 'Note' action beside Define/Explain in the selection menu, note anchored to the selected passage (subtle persistent highlight in the reading view), 'save to notes' on any definition/explanation in a thread, and a per-book notes list that jumps back to each note's passage.

## Resolution

Built the full notes loop: Note action in the selection pill → small parchment compose card (optional thought; a bare highlight is a valid note) → persistent faint amber underline on the passage → per-book Notes popover (bookmark toolbar icon) → tap a note to jump back to its passage, across chapters.

What was built:

- **Model** (`Freeloader/Models/Models.swift`): `Note` grew `wordIndex` (offset *within the section* — same convention as `DiscussionThread`/`ContextAssembler`), `wordLength`, and `source` ("selection" | "thread"). All optional, so existing stores migrate. Anchoring is chapterIndex + sectionIndex + wordIndex + wordLength — layout-independent (tokenization doesn't depend on font size/window), so it survives restarts, resizes, and font changes.
- **Selection menu** (`Discussion/SelectionMenu.swift`): third item "Note" (bookmark icon); hidden in the no-book sample chapter (nothing to persist to).
- **Composer** (`Freeloader/Notes/NoteComposer.swift`): small centered parchment card over the warm scrim (max 420 wide) — NOTE kicker, quoted excerpt, one optional serif field, Cancel/Save. Return saves, Esc cancels; the selection wash stays lit underneath so the reader sees what the note will hold. Chose a centered card over an anchored popover to avoid page-coordinate plumbing and match the Define/Explain modal language.
- **Underline render** (`Reading/PageView.swift` + `noteUnderline` in `ReadingPalette`): a 2pt amber capsule under each noted line, ~0.42 opacity dark / 0.5 light — deliberately the quietest amber on the page (pencil line, not highlighter), distinct from both the pacing cursor capsule and the selection wash.
- **Save-from-thread** (`Discussion/DiscussionModal.swift`): a whisper under every assistant answer — "Save to notes" in tertiary ink turning amber "Saved to notes". Anchors to the thread's stored selection, so the same passage gets underlined. Already-saved detection is by content match against the book's notes (survives modal reopen). Hidden for the sample chapter.
- **Notes list** (`Freeloader/Notes/NotesList.swift`): popover mirroring the discussions-history language — chapter-title kicker with a source glyph (bookmark = selection note, speech bubble = saved answer), quoted passage, the thought/answer, relative date. Right-click deletes.
- **Jump-back** (`Reading/ReadingView.swift` Notes extension): same-chapter jumps animate immediately (page-turn motion, cursor lands on the note's first word — the amber cursor marks the spot); cross-chapter jumps set a `pendingJump` that completes in `present()` once the target chapter's pagination lands.
- **Performance**: note ranges are resolved to global word ranges only when a fingerprint (`noteAnchorKey`: chapterID + this-chapter anchors) changes, via `.task(id:)` — the per-word cursor tick never pays for anchor resolution. Plain-key shortcuts (Space/arrows) are handed to the keyboard while the composer is open, same as the discussion modal.

Key decisions to review in the morning:

- **No pulse/flash on jump-back** — the cursor landing on the underlined passage seemed marker enough. If it's not obvious, a one-shot underline shimmer would be the fix.
- **Underline opacity/weight** is a one-line tunable in `ReadingPalette.noteUnderline`; verify it doesn't fight the bionic text on a real book at 25pt.
- **Notes list is a popover** (like discussions). With many notes a sidebar/sheet may serve better — same open question as thread history.
- **Overlapping notes** draw stacked identical underlines (indistinguishable). Fine for a prototype.
- **Anchors don't survive re-import** of the same PDF (word offsets would shift if extraction changes) — `anchoredText` is stored as a future re-anchoring fallback but no fuzzy re-anchor pass exists.
- **Environment note**: `platform=iOS Simulator,id=F0AAB6FA-…` destinations stopped resolving for xcodebuild this session (simctl still lists the device; xcodebuild sees no simulators, likely CoreSimulator/Xcode hiccup). Verified the iPad build with `-sdk iphonesimulator -arch arm64` instead, which compiles clean.

Both builds pass (macOS destination build; iOS via simulator SDK). Committed as fe5d4dd. Not driven end-to-end in a live GUI session — worth a morning pass: select → Note → save, check the underline, save an answer from a Define thread, and jump from the notes list across chapters.
