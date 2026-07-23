# Final walkthrough: does the prototype reach the destination?

Type: grilling (HITL)
Status: prepared (awaiting user walkthrough)
Blocked by: 05, 06, 08, 09, 10

## Question

Walk the user through the full loop on a real PDF — import, paced bionic reading, define/explain, a retention prompt, a note — on macOS, and confirm the iPad build still runs for reading. Capture what delights, what grates, and what's missing; file follow-ups as fog or out-of-scope, then declare the destination reached (or chart what's left).

## Automated preparation (agent, 2026-07-23 overnight)

The human half of this grilling waits for the morning; the automated half is done.
Full checklist, tunables table, open aesthetic questions, and known gaps are in
[assets/walkthrough-2026-07-23.md](../assets/walkthrough-2026-07-23.md).

Verified without the user:

- Both builds clean (macOS destination; iPad via `-sdk iphonesimulator -arch arm64` +
  `simctl install/launch` — xcodebuild's simulator destination matching is still broken
  machine-wide, see the guide's environment notes).
- macOS app launched from DerivedData: 10+ min, zero stderr, no crash. iPad simulator
  app installed, launched, renders the library screen (screenshot taken).
- **First live ClaudeService run from the .app bundle**: retroactive wiki scan spawned
  the real CLI, no Keychain consent blocker, and generated real
  summary/glossary/key-ideas files for The Pragmatic Programmer (spot-checked: coherent).
- Import pipeline exercised headlessly on real ~/Downloads PDFs: small text PDF extracts
  correctly; scanned PDF gated with the friendly error.
- Code audit: import → paced reading → define/explain thread → note → jump-back fully
  wired. **Retention (ticket 09) is unbuilt — the fourth pillar is the one remaining
  gap between prototype and destination**; the ticket is still open and unblocked.

Not verified (needs the human): magnification/pacing *feel*, first GUI-driven
Define/Explain + follow-up + history reopen, notes end-to-end in the GUI, iPad on
real hardware. The walkthrough guide sequences exactly these.
