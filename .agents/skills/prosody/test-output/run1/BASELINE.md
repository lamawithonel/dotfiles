# Run 1 -- Baseline (pre-patch)

Twenty zero-context Sonnet agents, brief: "Sell me a pen."  Fifteen with
level and prose architecture both locked; five with level locked and style
free.  Run against SKILL.md as it stood before the length-cell patch, when
level 4 read "Sustained" and level 5 read "Unbounded".

## Word counts

| Level | Epigrammatic | Pathos | Paratactic | Free choice |
| --- | --- | --- | --- | --- |
| 1 -- Plain | 11 | 13 | *no report* | 11 *(epigrammatic)* |
| 2 -- Tempered | 27 | 52 | 20 | 48 *(pathos)* |
| 3 -- Full | 106 | 120 | 84 | 98 *(pathos)* |
| 4 -- Grand / Forte | 148 | 398 | 205 | 289 *(pathos)* |
| 5 -- Fortissimo | 182 | 321 | 157 | 291 *(pathos + paratactic blend)* |

19 of 20 reported.  `pen-l1-para` never returned.

## Findings

1. **Levels 1-3 separate cleanly and monotonically** across all three
   architectures.  No overlap between adjacent levels.

2. **Levels 4 and 5 overlap completely.**  Level 5 produced *shorter* copy
   than level 4 in two of three architectures (Pathos 398 -> 321, Paratactic
   205 -> 157).  Spread within level 4 alone ran 148 to 398 words.

3. **Cause: the length cells.**  Levels 1-3 carried countable budgets
   (1 sentence / 2-4 sentences / 1-3 paragraphs) and were obeyed.  Levels 4-5
   carried "Sustained" and "Unbounded", which are moods, not measurements.
   "Unbounded" read as the absence of a constraint rather than a floor, so
   removing the ceiling removed the floor with it.

4. **Where the budget is unspecified, the architecture sets the length.**
   Pathos-Dominant Nostalgia is the longest cell in both top rows regardless
   of the level it was given, because its own spec (open, pivot, anchor)
   implies a shape that "Unbounded" does not.

5. **Free choice collapses to one architecture.**  Pathos at levels 2, 3, 4,
   and blended at 5.  Level 1 chose Epigrammatic only because the mechanism
   ladders forbid a *volta* at that level, making Pathos structurally
   illegal -- an emergent compatibility filter the document did not document.

6. **The two-register blend clause was used correctly on first outing**
   (`pen-free-l5`), cited by name, and held to two registers.

7. **Zero reference reads in 19 runs**, all correct.  Several agents quoted
   the routing line back verbatim.  No free agent selected a verse form even
   at level 5, so the verse references stay dormant unless verse is asked
   for outright.

8. **`disable-model-invocation: true` blocks the Skill tool for subagents.**
   Three agents reported the refusal explicitly and recovered by reading
   SKILL.md from disk; the rest almost certainly did the same silently.

## Patch applied before run 2

* Level 4 length: "Sustained" -> `150-300 words`
* Level 5 length: "Unbounded" -> `300+ words, no cap`
* Level 5 device density: "Every device earns a place" -> `7+ devices;
  every ladder at its maximum`
* New paragraph under the ladders stating that they gate architecture
  availability, and that the level wins when the two conflict.
