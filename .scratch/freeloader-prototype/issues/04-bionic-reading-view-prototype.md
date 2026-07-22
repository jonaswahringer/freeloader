# Prototype: bionic reading view (static)

Type: prototype (HITL)
Status: resolved
Blocked by: 01

## Question

What should a Freeloader page look and feel like? Build the static reading view with sample text: bionic bold-prefix rendering (prefix-length rule per word length), page layout/margins/typography, light & dark, adjustable text size with smooth resize animation. React-and-iterate with the user until the look is approved. Consult `/frontend-design`, `/ios-taste`. The approved visual language is the answer; the view code is the asset.

## Answer

Resolved 2026-07-22 after two review rounds; the user called the final view "perfect". Asset: **`Freeloader/Reading/ReadingView.swift`** (palette, bionic renderer, sample chapter, view).

The approved visual language:

- **Dark "reading lamp" is the default appearance** (`.preferredColorScheme(.dark)`): warm near-black paper (amber seed 38°) with a soft radial glow centered high on the page; warm off-white serif ink.
- **Bionic rendering:** serif (New York) throughout; bold prefix at full ink, word tail regular at ~62% opacity. Prefix rule: 1 letter (≤3-letter words), 2 (4–5), 3 (6–8), then ceil(40%) of longer words.
- **Wide word gaps are load-bearing:** inter-word spaces carry `kern = 0.28 × fontSize` so words read as separated stepping stones at speed — and leave room for the Dock-style word magnification coming in ticket 05.
- **Default text size 25pt**, adjustable 15–27 via a floating ultra-thin-material "Aa" button (bottom-right) with a slider popover; resize animates smoothly (`.smooth`, 0.35s) and column width breathes with the type (`min(34 × fontSize, 720)`; line spacing 0.58 × fontSize).
- **Chrome:** tracked small-caps amber chapter kicker over a large serif title; three amber dots as the section-end mark (future retention-prompt anchor); no other UI on the page.
- **Cursor preview:** the amber word-highlight (statically shown) is the approved cursor color language for ticket 05.

Note: `FreeloaderApp` temporarily launches straight into `ReadingView` (library bypassed) — keep this while tickets 05/06 iterate; the import pipeline ticket rewires the library.
