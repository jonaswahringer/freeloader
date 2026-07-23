# Prototype: Define/Explain modal, threads & history

Type: prototype (HITL)
Status: resolved (agent, pending user review)
Blocked by: 04, 07

## Question

Build the select-text → Define/Explain flow: selection menu on the reading view, modal showing the Claude answer (wiki + surrounding text as context), expandable follow-up thread inside the modal, threads persisted to SwiftData with a history list, and close/back restoring the exact reading position. Iterate the modal design with the user.

## Resolution

Built the full select → Define/Explain → threaded-modal flow (commit 235ba5e). Note: a prior agent run on this ticket was interrupted mid-work — its uncommitted components (SelectionMenu, DiscussionModal, DiscussionController, ThreadHistory, model fields, PageView selection support) were reviewed, kept, and completed with the missing ReadingView glue.

**What was built**

- `Freeloader/Reading/PageView.swift` — word-range selection by drag over the paginated page: a drag that starts on a word sweeps out a word range (hit-testing against `PageWord` frames; line distance dominates so sweeping below a line still tracks it); drags starting on whitespace remain page-turn swipes. Selection renders as a per-line amber wash (`ReadingPalette.selectionHighlight`, quieter than the cursor). On release, a small `SelectionMenu` capsule (Define / Explain, room left for ticket 10's Note) floats above the selection. Tap-away clears.
- `Freeloader/Discussion/DiscussionController.swift` — @Observable state machine per open modal: creates/reopens a SwiftData `DiscussionThread`, fires the canned opening question, appends follow-ups, persists `sessionID` from each reply so follow-ups (even days later from history) `--resume` the same CLI session; a lost session auto-retries once as a fresh conversation with full context.
- `Freeloader/Discussion/DiscussionModal.swift` — warm parchment card over a warm-tinted scrim (page stays legible underneath): kind kicker + quoted selection header, transcript (answers in the reading serif; follow-ups as thin amber-barred asides), three-dot thinking pulse ("Consulting the book's notes…" when a wiki exists), quiet failure state with Try Again (hidden on iPad where Claude is unavailable), follow-up composer. Esc / scrim-tap / × closes.
- `Freeloader/Discussion/ThreadHistory.swift` — toolbar popover listing past threads (kind, selection, first answer, relative time); tap reopens the thread in the modal, right-click deletes.
- `Freeloader/Reading/ReadingView.swift` — glue: selection state, pause-on-select, context assembly via ticket 07's `ContextAssembler` convention (word-in-section index computed from pagination), modal open/close with position untouched (cursor/page state simply sits underneath the overlay), plain-key shortcuts (Space/arrows) disabled while the modal is open so typing works.
- `Freeloader/Models/Models.swift` — `DiscussionThread` gained `sessionID` + `chapterIndex`/`sectionIndex`/`wordIndex` (all optional, migration-safe).

**Key design decisions**

- Opening question is NOT stored as a message — the thread's kind + selected text encode it; transcripts start with the answer.
- Context is assembled once at open; follow-ups on a resumed session send only the question (CLI carries state per ticket 07's convention).
- Sample chapter (no book) works too: in-memory thread (`persists: false`), hand-built excerpt context, nothing saved.
- Selection language: wash is deliberately dimmer than the pacing cursor so the two amber intents read differently.
- No streaming: the CLI transport is one-shot JSON, so "streaming" is the thinking pulse; answers land whole. True token streaming would need `--output-format stream-json` (follow-up).

**Review in the morning**

- End-to-end with a live Claude call was NOT driven through the GUI (transport itself was live-verified in ticket 07); please select a passage in a real book and try Define, a follow-up, and reopening from history.
- Aesthetic open questions: modal max width 580pt / height 620pt; scrim strength; whether the menu should also offer Explain on a single word (currently both actions always shown); whether history deserves a richer surface than a popover.
- iPad: selection + modal all work; asking fails gracefully with the unavailability message (expected until an iPad LLM strategy exists).
- Build-environment note: neither `generic/platform=iOS Simulator` nor concrete simulator ids resolve as destinations right now (a passcode-locked iPhone on iOS 26.5 confuses destination matching); iOS build verified with `-sdk iphonesimulator -destination 'generic/platform=iOS Simulator'`.
