# Genre Recipes

Long-form backing for the S2 router.  Two orthogonal inputs decide
technique: **genre** picks which technique families are *eligible*;
**complexity** (TELeR-style: single-step / multi-step / multi-deliverable)
picks *how much* scaffold to deploy.  Load this file once a genre is
diagnosed: read the matching section for the evidence and slot-weighting
that the compact S2 row does not carry, then apply the shared rewrite
mechanics at the end.  The ADD lists are in the S2 table; the sections below
add only the *why* (evidence) and the *how much* (slot weighting).

## The 6 technique families

- **Few-Shot** -- in-context exemplars of input->output.
- **Zero-Shot** -- instruction only, no exemplars.
- **Thought-Generation** -- elicit intermediate reasoning (CoT and kin).
- **Decomposition** -- split the task into ordered sub-tasks or stages.
- **Ensembling** -- multiple attempts reconciled (self-consistency,
  N-and-reconcile).
- **Self-Criticism** -- the model critiques and revises its own draft.

## Family x genre lookup (recommend / suppress)

| Family | Reason | Creative | Factual | Classify | Agentic | Planning | Conversational |
|---|---|---|---|---|---|---|---|
| Few-Shot | +/- | - | + | ++ (balanced) | + (schema) | +/- | - |
| Zero-Shot | + | ++ | ++ | + | + | + | ++ |
| Thought-Gen (CoT) | ++ | -- | -- | -- (gestalt) | +/- | + (checkpointed) | - |
| Decomposition | ++ | +/- | +/- | - | ++ | ++ | - |
| Ensembling | ++ | + (varied drafts) | + (verify) | +/- | + (verify) | + (options) | - |
| Self-Criticism | + | + (form) | + (verify) | +/- | ++ (per-stage) | + | ++ (form) |

`++` strong add, `+` add, `+/-` situational, `-` avoid, `--` strongly avoid.

## Reasoning / analytical (code author + trace, math, logic, calc)

**AVOID (evidence)**

- Rigid mid-derivation JSON or format restriction *during* reasoning --
  *Let Me Speak Freely* shows format restriction degrades reasoning
  accuracy.  Collect reasoning free-form, serialize at the end.
- Persona-for-accuracy -- *Basil/Kim* find role personas neutral-to-harmful
  for correctness.
- Excess exemplars -- diminishing-to-negative returns; a couple suffice.

**Code generation**: treat it as this genre, not creative.  Tests are the
DoD and the verification hook -- name the test(s) that must pass, and let
the model reason/decompose before writing.

**Slot weighting**: heavy Instructions and Output DoD; light Persona.

## Generative / creative (prose, ideation, naming, voice)

**AVOID (evidence)**

- Heavy constraint front-loading -- *CS4* shows dense constraints kill
  coherence.
- CoT -- dead weight, often distracting for generation.
- Majority-vote / self-consistency -- "best" is undefined for creative work.
- "Raise temperature = more creative" -- *Peeperkorn* shows temperature is a
  weak, noisy lever; steer with constraints and framing instead.

**Slot weighting**: Persona (voice) and light Constraints; minimal
Instructions scaffolding.

## Extractive / factual (lookup, QA, summarize-from-source)

**AVOID (evidence)**

- CoT -- *Sprague* shows near-zero recall gains unless a symbolic cue is
  present; it mostly adds cost and drift.
- Persona -- adds noise and risk with no recall benefit.
- Speculative scaffolding -- this is a robust genre; keep the touch light.

**High-stakes note**: legal-citation tasks hallucinate at ~13-21%, so name
the external check (cite the source passage, require a verification step).

**Slot weighting**: Context and verification-hook heavy; almost no Persona.

## Classification (intent, label, triage)

**AVOID (evidence)**

- CoT on exception-laden or gestalt rules -- *Liu* reports drops up to
  -36 points.
- Too many or unbalanced shots -- induces label bias.
- Novel formatting -- *FormatSpread* shows up to 76-point swings from format
  alone; keep it conventional.

**Slot weighting**: Output schema and Constraints heavy; no Persona, no CoT.

## Agentic / tool-use (tool-calling, multi-step automation)

**AVOID (evidence)**

- Open improvisation on destructive or ordered operations.
- Trusting self-reported success -- require an external check of the
  post-condition (*DSPy*-style per-stage assertions).

**Slot weighting**: Instructions (procedure) and verification-hook maximal.

## Planning / strategy (roadmaps, tradeoffs, multi-competency briefs)

**AVOID (evidence)**

- Forced symbolic CoT with no verifiable substrate.
- Over-rigid output format that flattens genuine tradeoffs.
- Single-answer convergence when the value is in the option set.

**Add note**: *Meta-Prompting* sub-role lenses (security lens, cost lens)
help briefs that span competencies.

**Slot weighting**: Decomposition and Output (options+tradeoffs) heavy.

## Conversational (dialogue, assistant turns, chat)

**AVOID**

- Heavy scaffolding on quick turns.
- CoT on intuitive/quick answers.
- Rigid schema that makes replies read like a form.

**Add note**: *Self-Refine* unaided self-critique improves FORM on a single
pass.

**Slot weighting**: Persona and Context; minimal everything else.

## Hybrid tasks (form and substance pull apart)

Common band the single-genre pick gets wrong: creative-in-form but
factual/regulated-in-substance (legal drafting, medical or safety
explainers, marketing copy with factual claims, technical documentation).

- Pick a **primary + secondary** genre (e.g. NDA = creative form + factual
  substance).
- **Union the ADD lists** across both.
- **Resolve AVOID by the stricter genre**: if any component is factual or
  high-stakes, its AVOID wins.  For the NDA, keep voice/register guidance but
  do NOT apply creative's "permission to diverge" or relax constraint
  front-loading -- the constraints ARE the deliverable, and accuracy
  verification stays on.

## Shared rewrite mechanics

**Complexity sizing (TELeR).**  single-step -> minimal scaffold and a
single targeted rewrite (or a diff); multi-step -> add decomposition and a
DoD; multi-deliverable -> add staged checkpoints and per-deliverable
success criteria.  Do not deploy the multi-candidate merge below on a
single-step prompt.

**Multi-candidate merge (OPRO + EvoPrompt).**  For multi-step or higher,
draft 2-3 diverse framings of the rewrite -- one constraint-first, one
example-anchored, one terse-directive -- then crossover-merge the strongest
clause of each into a single prompt.  Do not just pick one wholesale.

**Best-last ordering (OPRO recency bias).**  When the prompt contains
ordered exemplars or a priority list, place the strongest/most-preferred
item LAST; recency bias makes the final item carry the most weight.

**Strategy-switch on stall (Promptbreeder).**  If a self-check shows a fix
did not land, change the *kind* of fix (add a constraint vs. restructure
vs. add an exemplar).  Do not re-run the same "make it clearer" edit.

**Grounded critique (ProTeGi).**  Diagnose in the subject's vocabulary with
specific, falsifiable flaws.  "The success criterion is unstated" beats
"improve this".

**Optimizer honesty (APE / OPRO / ProTeGi).**  These methods need a labeled
dev set and an eval loop.  This skill has neither, so it is an
evidence-directed single-shot rewrite, not an optimizer run -- say so if
the user asked to "optimize".

**Ask-vs-assume economics (GATE).**  A sharp, well-placed question round
routinely costs the user less than a wrong assumption propagating through a
whole deliverable; asking is not pure overhead.

## Evidence key

| Tag | Claim used |
|---|---|
| Let Me Speak Freely | Format restriction during reasoning degrades accuracy. |
| Basil / Kim | Accuracy personas are neutral-to-harmful for correctness. |
| CS4 | Heavy constraint front-loading harms creative coherence. |
| Peeperkorn | Temperature is a weak lever for creativity. |
| Sprague | CoT gives near-zero recall gains without a symbolic cue. |
| Liu | CoT on gestalt/exception classification drops up to -36 pts. |
| FormatSpread | Unconventional formatting swings scores up to 76 pts. |
| DSPy | Per-stage assertions/checkable pass-fail for pipelines. |
| Meta-Prompting | Sub-role lenses for multi-competency briefs. |
| Self-Refine | Unaided self-critique improves FORM in one pass. |
| OPRO | Multi-candidate generation; recency bias (best-last). |
| EvoPrompt | Crossover-merge strongest clauses across candidates. |
| Promptbreeder | Switch revision strategy rather than repeat one edit. |
| ProTeGi | Specific grounded critique beats "make it better". |
| GATE | A sharp question round often beats a wrong assumption. |
| TELeR | Complexity level sets scaffold depth. |
| (legal-cite) | High-stakes factual hallucinates ~13-21%; verify. |
