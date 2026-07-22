# Research: invoking the Claude CLI headless from a macOS app

Type: research (AFK)
Status: resolved

## Question

What's the right way for a macOS SwiftUI app to drive `claude -p` headless? Investigate: locating the binary (PATH vs hardcoded), Process/NSTask invocation, `--output-format json` / `stream-json` parsing, session continuation (`--resume`/`--continue`) for threads, passing book context (files vs stdin), auth behavior when launched outside a terminal, App Sandbox implications (expect: prototype must run unsandboxed), latency and concurrency limits for background wiki generation. Deliver a markdown summary (linked asset) with a recommended ClaudeService design.

## Answer

Resolved 2026-07-22 via official docs plus empirical probes on this Mac (claude 2.1.206). Full findings, ClaudeService design, and flag reference: **[assets/claude-cli-research.md](../assets/claude-cli-research.md)**.

Headlines: headless `claude -p --output-format json` **works on subscription auth from a GUI-spawned process** — credentials are in the Keychain ("Claude Code-credentials"), and launchd-provided env (`HOME`, `USER`) suffices; the one real gotcha is locating the binary (`/opt/homebrew/bin` not on GUI PATH). Multi-turn threads via persisted `session_id` + `--resume` (cwd-scoped — run from the book's wiki dir). Constrain with `--permission-mode dontAsk --allowedTools Read`, budget `--max-turns ≥ 8` (tool turns count; `error_max_turns` drops the `result` field). Prompt via stdin, decode with Codable, serialize interactive calls. Confirms the unsandboxed-app choice; App Store distribution stays fogged.
