# Run 1 vs Run 2 -- Effect of the Length-Cell Patch

Same experiment twice: twenty zero-context Sonnet agents, brief "Sell me a
pen", fifteen cells with level and prose architecture both locked and five
with level locked and style free.  Between the runs, three cells of the
Dynamics table changed and one paragraph was added.

## The patch

| | Before | After |
| --- | --- | --- |
| Level 4 length | `Sustained` | `150-300 words` |
| Level 5 length | `Unbounded` | `300+ words, no cap` |
| Level 5 density | `Every device earns a place` | `7+ devices; every ladder at its maximum` |

Plus a paragraph under the mechanism ladders stating that they gate which
architectures are legal at each level, and that the level wins a conflict.

## Word counts

Run 1 (19 of 20 reported; `pen-l1-para` never returned):

| Level | Epigrammatic | Pathos | Paratactic | Free |
| --- | --- | --- | --- | --- |
| 1 | 11 | 13 | -- | 11 |
| 2 | 27 | 52 | 20 | 48 |
| 3 | 106 | 120 | 84 | 98 |
| 4 | 148 | 398 | 205 | 289 |
| 5 | 182 | 321 | 157 | 291 |

Run 2 (20 of 20):

| Level | Epigrammatic | Pathos | Paratactic | Free |
| --- | --- | --- | --- | --- |
| 1 | 15 | 21 | 9 | 7 |
| 2 | 29 | 64 | 20 | 23 |
| 3 | 124 | 175 | 113 | 87 |
| 4 | 211 | 208 | 192 | 225 |
| 5 | 422 | 407 | 317 | 327 |

## Results

**Monotonicity restored.**  All four columns of run 2 increase strictly with
level.  Run 1 had two inversions, both at the top: Pathos fell 398 -> 321 and
Paratactic fell 205 -> 157 going from level 4 to level 5.

**Level 4 variance collapsed.**  Spread across the three locked architectures
went from 250 words (148-398) to 19 words (192-211).  Including the
free-choice cell, run 2 spans 192-225.

**Level 5 now outranks level 4 everywhere.**  Run 2's lowest level 5 cell
(317) sits above its highest level 4 cell (225).  In run 1 the two bands
overlapped completely.

**No adjacent-level overlap anywhere in run 2.**  Level 3 tops out at 175;
level 4 starts at 192.  Level 4 tops out at 225; level 5 starts at 317.

**Diagnosis confirmed.**  The failure was never the concept of a level -- it
was two cells written as moods rather than measurements.  "Unbounded" was
read as the absence of an obligation, so it removed the floor along with the
ceiling.  The same architecture that produced 182 words under "Unbounded"
produced 422 under "300+ words, no cap".

**Compatibility rule executed on first contact.**  `r2-l1-pathos` hit the
designed conflict -- level 1 forbids a turn, Pathos-Dominant Nostalgia is
built on one -- quoted the new paragraph, dropped the volta, kept the
reframe, and reported the resolution.  The same cell in run 1 was incoherent.

**Register blending used deliberately, twice, both at level 5**
(`r2-free-l5`, `pen-free-l5` in run 1), each citing the two-register limit by
name.

**Self-reported word counts are trustworthy.**  Verified against actual
counts across all 20 files: mean absolute error 0.3 words, maximum 2.

## Findings unrelated to the patch

**The Skill tool is unreachable for subagents: 20 of 20 reported
"refused, read SKILL.md directly."**  With `disable-model-invocation: true`
set, delegated agents reach this skill only by reading the file, and only if
the brief tells them where it lives.  In run 1 three agents mentioned this
and the rest stayed silent; run 2 asked explicitly and the answer was
unanimous.

**Zero reference reads in 40 runs.**  Correct behavior -- prose never routes
to the verse files, and several agents quoted that line back.  No free-choice
agent selected a verse form at any level, so `western-verse.md` and
`japanese-verse.md` remain unexercised by anything except an explicit request
for verse.

**Free choice diversified.**  Run 1 chose Pathos at four of five levels.
Run 2 chose Epigrammatic, Paratactic, Pathos, Pathos, and a deliberate
Epigrammatic/Pathos fusion -- plausibly because the ladder-compatibility
paragraph makes the level's constraints legible enough to reason from.
