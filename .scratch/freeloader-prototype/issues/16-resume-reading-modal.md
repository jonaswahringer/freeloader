# Prototype: "Continue where you left off" resume modal

Type: prototype (HITL)
Status: open
Blocked by: 13

## Question

The cursor's last position in each book is already persisted (SwiftData, from ticket 05; the position representation is being redefined by ticket 13's infinite scroll). Build the resume UX on top of it: when the user opens a book that has a saved position past the very beginning, present a modal with two options:

- **Continue Where You Left Off** — the view scrolls to the saved position (animated, so the user sees where they're landing) and the pacing cursor is placed there, paused.
- **No, Thanks** — the book opens at the beginning; the saved position is kept (not erased) so pacing/scrubbing simply proceeds from the top.

Decisions to resolve in the prototype:

- Modal presentation: parchment-style card consistent with the Define/Explain modal language from ticket 08, shown over the reading view after the chapter renders.
- What "where you left off" shows — just the buttons, or a hint like chapter title / % progress so the choice is informed?
- When the saved position is trivial (first words of the book) or the book was finished, skip the modal entirely.
- Does declining reset the persisted position immediately, or only once the user starts pacing from the top? (Recommend: only overwrite once they actually read.)
