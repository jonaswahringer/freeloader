# Research: invoking the Claude CLI headless from a macOS app

Asset for [03-claude-cli-integration-research](../issues/03-claude-cli-integration-research.md). Combination of official docs (headless, sessions, permissions, auth, CLI reference at code.claude.com/docs) and empirical probes run 2026-07-22 on this Mac (claude 2.1.206, Homebrew cask at `/opt/homebrew/bin/claude`).

## Empirical findings (this machine)

- **One-shot works on subscription auth.** `claude -p "…" --output-format json` returned a JSON envelope with `result`, `session_id`, `is_error`, `num_turns`, `total_cost_usd`, `usage`, `duration_ms`. Trivial prompt: ~1.7s API / ~3s wall.
- **Multi-turn works.** Captured `session_id` from call 1, then `claude -p "…" --resume <id>` recalled state ("ZANZIBAR" test). Sessions are **cwd-scoped** — resume from the same working directory.
- **Auth is Keychain-based and GUI-safe.** Credentials live in the macOS Keychain item **"Claude Code-credentials"**. `env -i HOME=… PATH=/usr/bin:/bin` → "Not logged in"; adding `USER`/`LOGNAME`/`TMPDIR` → works. GUI apps inherit all of these from launchd, so **subscription auth works from a GUI-spawned process** — no API key needed. (Docs/agent guidance claiming OAuth can't work headless is wrong for our same-user local case.) One unverified corner: whether the *first* Keychain access from an app-spawned claude shows a Keychain consent dialog — verify in ticket 07.
- **PATH gotcha:** GUI apps get `/usr/bin:/bin:/usr/sbin:/sbin` — no `/opt/homebrew/bin`. The app must locate the binary itself (probe `/opt/homebrew/bin/claude`, `~/.local/bin/claude`, `/usr/local/bin/claude`; make it a settings override).
- **Constrained tool use works headless:** `--allowedTools Read --permission-mode dontAsk` read a local markdown file with no interactive prompt. **`--max-turns` counts every assistant turn including tool calls** — 3 was too few for a single read-then-answer task (hit `subtype: "error_max_turns"`, which also *drops the `result` field*); budget ≥8 for tool-using calls and always guard JSON parsing on `subtype`/`is_error`.
- **Cost visibility:** subscription runs still report `total_cost_usd` (informational). A trivial call showed ~$0.17 equivalent — mostly fixed system-prompt overhead; wiki-generation calls will dominate usage. Rate limiting = subscription usage limits; app should queue (serialize or ≤2 concurrent) rather than fan out.

## Recommended ClaudeService design (for ticket 07)

- **Transport:** `Foundation.Process` spawning the located binary. Feed the prompt via **stdin** (avoids ARG_MAX and quoting issues; stdin limit 10MB), read stdout to completion, decode with `Codable`. Set `currentDirectoryURL` to the **book's wiki directory** — that makes relative `Read`s natural and scopes session storage per book.
- **Canonical invocation:**
  `claude -p --output-format json --permission-mode dontAsk --allowedTools Read --max-turns 12 --model sonnet --append-system-prompt <role>` (+ `--resume <id>` for threads). Consider `--bare` (skips auto-discovery; docs recommend for scripts) and `--max-budget-usd` as a safety cap.
- **Context strategy:** wiki files on disk + cwd + allowed `Read` beats inlining everything into the prompt; inline only the immediate passage. `--add-dir` if book text lives outside cwd.
- **Threads (Define/Explain):** persist `session_id` on `DiscussionThread`; follow-ups use `--resume`. Store our own message copies in SwiftData regardless (display + survives session GC).
- **System prompts:** use `--append-system-prompt` (keeps tool competence) rather than `--system-prompt` (full replacement).
- **Model:** default `sonnet` for define/explain/grading latency; `--model` per call. Wiki generation can use the session default.
- **Error taxonomy to handle:** binary not found; `is_error: true` with "Not logged in" (→ tell user to run `claude` once in Terminal and log in); `subtype: error_max_turns` (missing `result`); non-zero exit / malformed JSON; timeout (kill process after e.g. 120s one-shot, more for wiki jobs).
- **Concurrency:** one serial queue for interactive calls, wiki generation as a background chain of sequential per-chapter calls; both share a small global cap.
- **Streaming (later):** `--output-format stream-json --include-partial-messages` emits NDJSON events for progressive display in the modal — worth adding for ticket 08's UX polish, not needed for v1 plumbing.

## Sandbox / distribution implications

Spawning an arbitrary user binary + Keychain-shared auth is incompatible with the App Sandbox — confirms the scaffold's unsandboxed choice (ticket 01) and keeps App Store distribution in the fog: a store build would need its own auth (API key or backend) and an XPC/embedded approach. Fine for the prototype.

## Flag reference (verified relevant subset)

| Flag | Use |
|---|---|
| `-p` / `--print` | headless one-shot |
| `--output-format json\|stream-json` | machine-readable result / NDJSON stream |
| `--resume <session_id>` / `--continue` | multi-turn from a prior `-p` call (cwd-scoped) |
| `--permission-mode dontAsk` | never prompt; deny anything not pre-approved |
| `--allowedTools "Read"` | pre-approve tools (empty ⇒ pure text generation) |
| `--max-turns N` | hard turn cap — counts tool turns; ≥8 for read-then-answer |
| `--max-budget-usd X` | spend cap |
| `--model sonnet\|opus\|haiku\|<id>` | per-call model |
| `--append-system-prompt "…"` | role injection without losing defaults |
| `--add-dir <path>` | extra readable directory |
| `--json-schema '<schema>'` | structured output (`structured_output` field; validation strict since 2.1.205) |
