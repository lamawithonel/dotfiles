# Clarify Taxonomy

Backing for the S3 ambiguity pass.  Load when running the clarify step.
Goal: ask at most 2-3 high-value questions in ONE batch only when genuinely
blocked, and otherwise infer and state assumptions.

## Ambiguity types

| Type | It is missing... | Typical default |
|---|---|---|
| **SCOPE** | how much of the space is in vs. out of bounds | ASK if divergent |
| **REFERENCE** | which specific thing a term points to | ASK if divergent |
| **CRITERION** | what "good" or "done" means | ASK if divergent |
| **CONSTRAINT** | a hard limit (budget, length, platform, deadline) | ASK if divergent |
| **PREFERENCE** | a taste/style choice with no correctness impact | ASSUME + state |

## Two-filter gate

Ask about a gap only if BOTH filters pass.

1. **Missing filter** -- would a *canonical instance* of this genre specify
   it?  If a competent practitioner would always pin this down, it is
   genuinely missing.  If most instances leave it implicit, it is not.
2. **Divergent filter** (counterfactual test) -- simulate the two most
   likely readings and compare the resulting deliverables.  If they differ
   materially, the gap is divergent.  If both readings produce
   substantially the same output, it is not -- infer either.

## Decision table

| Situation | Action |
|---|---|
| SCOPE / CONSTRAINT / CRITERION, divergent | ASK |
| Any irreversible or destructive action | ASK |
| High-consequence content: unsafe, costly, or hard to reverse if wrong, even when the two readings look similar | ASK, or flag the assumption conspicuously |
| PREFERENCE | ASSUME + state |
| Reversible / easily-revised choice | ASSUME + state |
| Fails missing filter OR fails divergent filter | ASSUME (or ignore) |

The high-consequence row is a **stakes override**: cost-of-error is
orthogonal to output divergence.  A gap can produce near-identical readings
yet still be dangerous to get wrong (a dosage, a compliance threshold, a
legal term, a safety margin).  Those escalate even though the divergent
filter alone would pass them over.

## Batching and cap

- Maximum 2-3 questions, in ONE round.  Never serial (do not ask one, wait,
  ask another).
- The first question is near-free; each additional one adds friction
  sharply.  Spend the slots on the highest-divergence gaps only.
- If more than 3 gaps pass the gate, keep the top 2-3 by divergence (and
  any stakes-override gaps) and ASSUME the rest with stated assumptions.

## Bare-brief exception

When the deliverable *itself* is unidentifiable -- a REFERENCE gap at the
artifact level, e.g. "help me write something" -- one scoping round to
establish *what the artifact is* comes first, then the normal single-round
cap applies to the remaining gaps.  This is a deliberate, narrow exception
to never-serial; it is not license to nag serially about preferences once
the artifact is known.

## Instance-grounded phrasing

Ground each question in a concrete instance or edge case, not an abstract
category.  The reader answers a scenario faster and more accurately than a
taxonomy question.

- Good: "If a step assumes the print bed is already leveled, should the
  guide explain leveling or skip it?"
- Bad: "What is the audience's skill level?"
- Good: "For the 3 rows with a null timestamp, drop them or keep them with
  an empty date?"
- Bad: "How should edge cases be handled?"

## Question templates

- SCOPE: "Does this cover {narrow instance} only, or also {broader
  instance}?"
- REFERENCE: "By {term}, do you mean {reading A} or {reading B}?"
- CRITERION: "Is {output} done when {check A}, or must it also {check B}?"
- CONSTRAINT: "Is there a hard limit on {budget/length/platform/deadline},
  e.g. {concrete value}?"
- Irreversible: "This will {destructive effect on concrete target} --
  proceed, or {safer alternative}?"

## Re-check trigger

If retrieval or newly added context was used to fill a gap, re-run the whole
pass.  Added context tends to suppress asking even when real ambiguity
remains, so re-test the surviving gaps against the two filters.

## Assumptions-block format

When NOT asking, emit a visible, itemized Assumptions block.  Each line is a
single falsifiable statement the user can scan and override individually
without discarding the rewrite.

Rules:

- One assumption per line, phrased as a claim, not a question.
- Make it falsifiable: name the concrete choice, not a vague direction.
- Order by impact, highest first.
- Omit the block entirely if nothing was inferred.

Example:

```
Assumptions (override any line):
- Target = web app, not native mobile.
- Audience = practitioners, so no glossary of basic terms.
- Length budget = ~1 page; trimmed the background section to fit.
- Output format = Markdown with H2 sections.
```
