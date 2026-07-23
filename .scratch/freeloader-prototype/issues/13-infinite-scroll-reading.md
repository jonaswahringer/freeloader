# Prototype: infinite scroll instead of page turns

Type: prototype (HITL)
Status: open
Blocked by: 05

## Question

Replace the paginated reading model (Paginator + auto page-turns from ticket 05) with a continuous "infinite scroll" column: the chapter (or book) flows as one scrollable text surface, and the pacing cursor advances through it without discrete page boundaries.

Decisions to resolve in the prototype:

- What is the scroll unit — chapter-as-one-column, or the whole book stitched with chapter headers inline?
- What happens to the CoreText-measured word frames the cursor/magnifier/selection all rely on — can the existing per-page frame model become a per-viewport or per-paragraph frame model without regressing Dock magnification, click-to-scrub, drag selection, and note underlines?
- Performance: chapters run to hundreds of thousands of words (ticket 12 fixed chapter-switch lag via off-main builds) — lazy layout/windowing is likely mandatory; keep the ChapterBuilder cache strategy compatible.
- Page-turn animation and page-position persistence go away — what replaces "position" (scroll offset? word index?) in SwiftData persistence?

Auto-scroll behavior (keeping the cursor centered) is ticket 14, blocked on this one — here, get the scrolling surface itself right and user-approved.
