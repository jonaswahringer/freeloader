# ClaudeService & background wiki generation

Type: task (AFK)
Status: resolved (agent, pending user review)
Blocked by: 03, 06

## Question

Implement the ClaudeService per the research recommendation, then the background analysis job: on book import, generate per-chapter summaries, glossary, and key-ideas markdown files under the book's wiki directory, with progress surfaced unobtrusively in the UI and graceful behavior while generation is incomplete. Define the wiki file layout and the context-assembly convention (how later features pull wiki + surrounding text into prompts) — record both in the answer.

## Resolution

Built (all under `Freeloader/Claude/`, auto-synced into the target):

- **`ClaudeService.swift`** — headless CLI transport per the ticket-03 research: `claude -p --output-format json --permission-mode dontAsk --allowedTools Read --max-turns 12 --model sonnet`, prompt via stdin, explicit binary lookup (`/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, `~/.claude/local`, plus a `ClaudeBinaryPath` UserDefaults override), `--resume` threading, `--append-system-prompt` role injection, `--json-schema` structured output, watchdog timeout, full error taxonomy (binary missing / not logged in / max-turns / malformed / timeout). Process spawning is `#if os(macOS)`; on iPad `availability == .unavailableOnPlatform` and calls throw gracefully. A 2-slot `AsyncGate` caps global concurrency so the serial wiki drip never starves interactive calls.
- **`BookWiki.swift`** — the wiki file layout (see below) + manifest read/write + queries.
- **`WikiGenerator.swift`** — `@MainActor @Observable` background job. On import and retroactively on library appearance (`scan(books:)`), books queue serially; each eligible chapter gets ONE structured-output call producing `{summary, glossary, keyIdeas}` which is split into three markdown files. Chapters < 120 words are skipped (blank/divider pages); chapter text over 9000 words is bounded head-70%/tail-30% with an elision marker (tunables in `WikiTuning`). Failed chapters retry once then are skipped; unavailable/logged-out aborts the book quietly and retries next launch. Completion state is derived from files on disk, so quitting mid-generation resumes exactly where it left off.
- **UI (`ContentView.swift`)** — a 14pt amber progress ring (ReadingPalette.brand) trailing the book row while notes generate, with tooltip + accessibility label; a quiet `exclamationmark.circle` on partial failure; nothing at all when done or when Claude is unavailable. Book deletion removes the wiki directory.
- **`Models.swift`** — `Book.wikiID: UUID?` (optional so pre-existing stores migrate; assigned lazily on first generation).

### (a) Wiki file layout

```
~/Library/Application Support/Freeloader/Wiki/<Book.wikiID>/
  manifest.json            # { version, bookTitle, model, chapters: [{index, title, status, generatedAt}] }
  chapters/
    03-summary.md          # "# <Chapter Title> — Summary"   + 2–4 paragraphs
    03-glossary.md         # "# <Chapter Title> — Glossary"  + "**Term** — definition" lines
    03-key-ideas.md        # "# <Chapter Title> — Key Ideas" + numbered list
```

Files are zero-padded by `Chapter.index` (2 digits). The wiki directory doubles as the Claude working directory, so prompts reference files by relative path (`chapters/03-glossary.md`) and Claude's cwd-scoped session storage lands there too. `BookWiki.isChapterComplete/availableFiles/read/remove` are the query surface.

### (b) Context-assembly convention (for ticket 08 + retention)

`ContextAssembler.assemble(book:chapterIndex:sectionIndex:wordIndex:selection:radiusWords:)` → `AssembledContext { workingDirectory, systemPrompt, contextBlock }`, consumed by `ClaudeService.ask(_:context:resume:jsonSchema:model:maxTurns:)`. The convention:

1. **cwd = wiki dir; wiki stays on disk.** The context block lists available wiki files (relative paths) and instructs Claude to `Read` the relevant ones — nothing bulky is inlined.
2. **Only the immediate passage is inlined**: a ±350-word window (word-split on `" "`, matching ReadingView tokenization) around the reader's position in the current section, in `<excerpt>` tags; the user's selection in `<selection>` tags.
3. **Shared role** (`ContextAssembler.companionRole`): grounded, concise (2–5 sentences), no markdown headings.
4. **Threads**: persist `reply.sessionID` on `DiscussionThread`; follow-ups call `ask(question, context: ctx, resume: sessionID)` — the CLI carries state, so follow-up prompts are just the new question (context block skipped automatically).

### Verified for real (this machine, 2026-07-23)

Compiled a harness from the actual `ClaudeService.swift` source (`scratchpad/harness/`) and ran it against the live CLI on subscription auth:
- structured wiki-style call → valid `{summary, glossary, keyIdeas}` JSON, session id, ~$0.04–0.33/call;
- `ask()` with a planted wiki file: Claude `Read` the glossary via relative path and answered from it (canary-term grounding check PASSED);
- `--resume` follow-up recalled the session (PASSED).

### Review in the morning / open questions

- **One transient bad generation observed**: a single structured call returned `summary: "test"` (schema-valid junk); an identical rerun was fine. The retry-once logic only catches thrown errors, not schema-valid nonsense — if junk wiki files appear, delete the chapter files and relaunch, or we add a plausibility check (min length) later.
- **Keychain consent corner still unverified from the .app bundle**: the harness is a CLI process. First launch of the real app with a book imported will kick off generation — if a Keychain consent dialog appears once, that's the known corner from ticket 03.
- **Retroactive scan runs on app launch** and will spend subscription quota (~1 call/chapter, sonnet). Your 3 imported test books will start generating on next launch.
- Aesthetic defaults chosen without you: progress ring disappears silently on completion (no celebratory moment); unavailable state shows nothing at all; failure is a quiet secondary-color icon with a tooltip. Happy to add a subtle "notes ready" sparkle if you want one.
- `generic/platform=iOS Simulator` destination fails on this Mac (iOS 26.5 device platform not installed in Xcode); iPad build verified against a concrete simulator (`id=75F98D5D…`, iPad Pro 13-inch M5) instead — passes clean.
