# Task: reading-view performance (chapter switch lag)

Type: task (AFK)
Status: resolved (agent, pending user review)
Blocked by: 04

## Question

Chapter navigation is visibly laggy: clicking a chapter in the toolbar takes too long to render (reported by the user 2026-07-22 while using the prototype). Profile and fix so chapter switches feel instant.

Suspects to investigate:

- The bionic `AttributedString` builder runs per paragraph per render and is recomputed wholesale on every font-size change and view refresh — no caching, and each word allocates multiple `AttributedString`s. Cache built paragraphs keyed by (text, size, scheme), or precompute per chapter off the main thread.
- Whole-chapter rendering in a plain `VStack` inside `ScrollView` lays out every paragraph eagerly — switch to `LazyVStack`, or paginate (which ticket 05's page model may do anyway).
- The `.animation(value: fontSize)` on the whole column may force full re-layout animations on content swaps.

Acceptance: switching chapters on a real imported book (352-page reference PDF) renders in under ~100ms perceived; text-size changes stay smooth. Coordinate with tickets 05 (pagination/cursor may change the layout model) and 06 (real chapter data) rather than optimizing throwaway structure twice.

## Resolution

Built (new file `Freeloader/Reading/ChapterBuilder.swift`, rewrite of `Freeloader/Reading/ReadingView.swift`):

- **Off-main bionic build with caching.** `ChapterBuilder` (actor, `.shared`) builds a chapter's bionic `AttributedString` paragraphs on a background task, cached in an LRU (capacity 24) keyed by `(chapter persistentModelID, fontSize, dark/light)`. In-flight builds are deduplicated. Input is `ChapterSource`, a Sendable value snapshot taken from SwiftData on the main thread only once per build request — SwiftData string fetches are out of the render path entirely (the view's per-body-eval accessor `currentMeta` reads only titles).
- **Neighbor prefetch.** After the current chapter is built, chapters `index±1` are prefetched at the same size/scheme, so Next Chapter and most menu jumps are cache hits (instant). Cold jumps show the chapter header immediately and the text fades in (`easeOut 0.15s`) after the background build (~200ms for a synthetic 10K-word chapter, measured with an -O benchmark; runs off-main so the UI never stalls).
- **Lazy layout.** The column is now a `LazyVStack`, so only visible paragraphs are laid out.
- **Removed the whole-column `.animation(value: fontSize)`** — it forced an animated full re-layout of every paragraph on resize. Text-size changes now keep the old-size text on screen until the new prebuilt column swaps in (no blank flash, no layout animation). Slider steps are 1pt in 15…27, and each step is cached, so scrubbing back and forth is instant after first touch.
- **Pagination-ready (ticket 05).** `BuiltParagraph` carries `wordRanges` (character offsets per word) and a `highlighting(wordIndex:color:)` helper that sets the amber cursor background on one word without rebuilding the paragraph. The `ChapterSource → ChapterBuilder → BuiltChapter` pipeline is the durable part; ticket 05 can replace the LazyVStack scroll column with pages while keeping the cache and word ranges.

Design decisions / for morning review:

- Font-size changes no longer animate the text re-layout (that animation was a main suspect for jank). If the animated "breathing" resize is missed aesthetically, a cheap option is a brief crossfade between old and new built columns; full layout animation is what caused the lag.
- Stale-content policy: on chapter switch, old paragraphs are never shown under the new header (blank + fade instead); on font-size or scheme change within a chapter, the old rendering stays visible until the new one is ready.
- Dark/light scheme is part of the cache key; toggling scheme shows old colors for one build (~cache-hit fast after first toggle).
- Cache capacity 24 entries (a chapter at a given size/scheme each); tune in `ChapterBuilder.capacity`.
- Not done (possible follow-ups): per-word run-merging to cut AttributedString allocations further (~200ms → less for huge chapters); persisting built text across app launches (probably unnecessary once pagination builds per-page).
- Verified: macOS build clean; iPad build clean (had to create an iPad Pro 11 (M4) iOS 26.3 simulator — none existed; the target is iPad+Mac only, iPhone destinations don't match). Could not runtime-test against the 352-page reference book because no imported library store was accessible from this session; benchmark used a synthetic 10K-word chapter.
