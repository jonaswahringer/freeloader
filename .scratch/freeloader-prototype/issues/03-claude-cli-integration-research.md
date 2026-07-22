# Research: invoking the Claude CLI headless from a macOS app

Type: research (AFK)
Status: open

## Question

What's the right way for a macOS SwiftUI app to drive `claude -p` headless? Investigate: locating the binary (PATH vs hardcoded), Process/NSTask invocation, `--output-format json` / `stream-json` parsing, session continuation (`--resume`/`--continue`) for threads, passing book context (files vs stdin), auth behavior when launched outside a terminal, App Sandbox implications (expect: prototype must run unsandboxed), latency and concurrency limits for background wiki generation. Deliver a markdown summary (linked asset) with a recommended ClaudeService design.
