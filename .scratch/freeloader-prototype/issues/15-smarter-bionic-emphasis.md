# Research: smarter bionic emphasis (beyond first-syllable-of-every-word)

Type: research (AFK)
Status: open
Blocked by: (none)

## Question

The current bionic rendering bolds a fixed prefix of every word, which flattens emphasis — everything shouts equally. Research better emphasis strategies and recommend one (or a ranked shortlist) for Freeloader:

- What does the literature/practice say about bionic-style reading aids? Is there evidence on prefix-bolding effectiveness, and on selective emphasis (content words vs. function words)?
- Candidate strategies to evaluate: skip function words (articles, prepositions, pronouns) entirely; weight bold length by word importance/frequency (rare words get more emphasis); syllable-aware prefixes (bold whole first syllable rather than a character count); sentence-level salience (keywords per sentence, possibly precomputed per chapter — the wiki pipeline/ClaudeService could supply importance data offline, but must not add per-page LLM latency).
- Constraints: must render locally and instantly from cached data (ChapterBuilder actor precomputes off-main); must stay legible with the existing bold-prefix/62%-tail ink design from ticket 04; English-first but shouldn't hard-block other languages.

Deliverable: a markdown summary in assets/ comparing strategies (evidence, implementation cost, data dependencies) with a concrete recommendation, so a follow-up prototype ticket can implement it and let the user judge the feel.
