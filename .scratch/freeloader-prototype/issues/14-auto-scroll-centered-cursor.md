# Prototype: auto-scroll keeping the cursor centered

Type: prototype (HITL)
Status: open
Blocked by: 13

## Question

With infinite scroll in place (ticket 13), make the view auto-scroll while pacing plays so the amber cursor stays vertically centered in the viewport — the text moves past a fixed reading focus, teleprompter-style — except:

- **Initial start:** at the top of a chapter, the text starts at its natural top position; the cursor walks down until it reaches center, and only then does centering lock in.
- **Definitive end (chapter):** near the chapter's end, the view stops scrolling at the natural bottom; the cursor walks down the remaining lines to the last word.

Decisions to resolve in the prototype:

- Scroll motion feel: continuous glide per word vs. per-line steps — which reads better at typical WPM without inducing motion sickness? (Consult /ios-animations; respect Reduce Motion.)
- Interaction handoff: what happens when the user manually scrolls during playback — pause pacing, or let the cursor keep going and re-capture the scroll on resume?
- Does centering interact with the Dock magnification and click-to-scrub from ticket 05?
