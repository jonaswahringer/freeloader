# Prototype: WPM highlight cursor & page-turn animations

Type: prototype (HITL)
Status: open
Blocked by: 04

## Question

How should pacing feel? On top of the approved reading view, build: the highlight cursor sweeping word-by-word at a configurable WPM (word-length/punctuation-weighted timing?), the WPM control, line-transition animation, auto page-turn when the cursor reaches page end, plus manual page-turn scroll behavior. Pause/resume and scrub-back-to-cursor behavior included. Consult `/ios-animations`. Iterate with the user until the motion feels right.

User direction (from ticket 04 review, 2026-07-22): the cursor should **magnify words like the macOS Dock magnifies icons on hover** — as the cursor sweeps left to right, the current word scales up with neighbors swelling slightly in a falloff curve. The user called getting this right (together with word spacing) the biggest open issue.
