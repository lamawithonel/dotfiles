---
name: improve-prompt
description: Diagnoses and rewrites prompts or rough task briefs from any domain into clearer, better-scoped prompts.  Use when the user pastes a prompt to improve, says "improve this prompt", "make this prompt better", "rewrite this prompt", "fix/tighten/sharpen this prompt", asks "help me write a prompt for X", or hands over a rough task brief and asks for a ready-to-use prompt or spec before work begins.
license: Apache-2.0
---

# Improve Prompt

Turn any prompt or rough task brief into a clearer, better-scoped prompt.
Domain-agnostic: one genre router adapts technique to the subject, so the
same loop serves reasoning, code, creative, factual, classification,
agentic, planning, and conversational work.

The rubric maps to five prompt slots -- **PICCO**: Persona, Instructions,
Context, Constraints, Output.  Genre changes each slot's *weight*, never
the skeleton.

## Operating procedure

1. **Intake** -- capture the raw prompt/task verbatim; note any stated
   domain, audience, or constraints.
2. **Classify** -- pick the genre (S2, 7-way) and complexity level
   (single-step / multi-step / multi-deliverable).  Genre sets which
   techniques are eligible; complexity sets how much scaffold to deploy.
3. **Diagnose** -- score against the 10-dim rubric (S1).  Name concrete
   flaws in the subject's own vocabulary ("the tolerance is unstated", not
   "add detail").  If the subject has a playbook under
   `references/domains/`, load it for that vocabulary.
4. **Ambiguity pass** (separate, explicit) -- enumerate gaps, classify each
   type, apply the missing-AND-divergent filters, then decide ask-or-assume
   (S3).  Do this as its own step; do not fold it into the rewrite.
5. **If asking** -- emit 1-3 batched, instance-grounded questions and stop.
   Otherwise continue.
6. **Rewrite** -- apply the genre recipe plus universal fixes across the
   PICCO slots, weighted per genre.  Size the effort to complexity: for a
   single-step prompt, make one targeted rewrite (or a diff for a small
   edit); for a multi-step or multi-deliverable prompt, draft 2-3 diverse
   framings (constraint-first / example-anchored / terse-directive) and
   merge the strongest clauses of each.  Order any exemplars or priority
   lists worst-to-best, strongest LAST.
7. **Self-check** -- re-score the result against the rubric DoD; confirm no
   clause silently degraded.  If a fix did not land, switch strategy (add a
   constraint vs. restructure vs. add an example) instead of repeating "make
   it clearer".  Self-critique FORM only; route every TRUTH claim to an
   external-verification instruction inside the output.
8. **Emit** -- follow the output contract below.

## S1. Quality rubric (score and repair all ten)

Each maps to a PICCO slot.

1. **Deliverable named** [I] -- exact artifact and its form are stated, not
   implied.
2. **Success criteria / DoD** [O] -- a checkable "done and good" definition
   exists (what makes output pass or fail).
3. **Scope fence** [Co] -- explicit in-bounds/out-of-bounds; states what
   NOT to do.
4. **Context sufficiency** [C] -- required inputs are present; irrelevant
   context is stripped.
5. **Constraints explicit** [Co] -- hard limits (budget, length, format,
   materials, deadline, platform) are surfaced, not guessed.
6. **Output format specified** [O] -- form and structure declared at the
   rigidity the genre wants (see S2).
7. **Audience/register** [P] -- who it is for, at what depth and voice.
8. **Terms unambiguous** [Co] -- no scope or reference term two competent
   practitioners would read differently.
9. **Verification hook** [I] -- every checkable claim or number names an
   external check, never self-report.
10. **Right-sized** [O] -- scaffold depth matches complexity; no token the
    model does not need.

## S2. Genre router (ADD / AVOID)

Genre picks *eligible* techniques; complexity picks *how much* scaffold.
Full recipes and the transfer-evidence behind each cell live in
`references/genre-recipes.md`.

| Genre | ADD | AVOID |
|---|---|---|
| **Reasoning/analytical** (code author + trace, math, logic, calc) | step-by-step CoT; decomposition; N attempts then reconcile; reason in prose, format last; for code, tests are the DoD | rigid mid-derivation JSON; persona-for-accuracy; excess exemplars |
| **Generative/creative** (writing, ideation, voice) | few prioritized soft constraints (voice/theme/length); permission to diverge; ask for multiple varied drafts; persona for voice only | heavy constraint front-loading; CoT; majority-vote; "temperature = creativity" |
| **Extractive/factual** (lookup, QA, summarize-from-source) | external grounding + explicit verification step for high-stakes; conventional formatting; source anchoring | CoT (unless a symbolic cue); persona; speculative scaffolding |
| **Classification** (intent, label, triage) | strict front-loaded schema; 1-3 tight *balanced* exemplars; explicit label definitions | CoT on gestalt/exception-laden rules; too many or unbalanced shots; novel formatting |
| **Agentic/tool-use** | strict tool-call schema; low-freedom exact procedure for fragile/ordered/irreversible steps; per-stage pass/fail; explicit verify checkpoints | open improvisation on destructive/ordered ops; trusting self-reported success |
| **Planning/strategy** (roadmaps, tradeoffs) | decomposition into checkpointed stages; generate options + compare tradeoffs; sub-role lenses for multi-competency briefs | forced symbolic CoT with no verifiable substrate; over-rigid format; single-answer convergence |
| **Conversational** (dialogue, assistant) | persona/register for voice; audience-depth calibration; unaided self-critique for FORM | heavy scaffolding; CoT on quick/intuitive turns; rigid schema |

**Hybrid tasks** -- when form and substance pull apart (creative form +
factual or regulated substance: legal drafting, medical or safety
explainers, marketing copy with factual claims, technical docs), pick a
primary + secondary genre.  Union their ADD lists, but resolve any AVOID
conflict by the STRICTER genre: if a component is factual or high-stakes,
its AVOID wins.  Concretely -- keep the creative voice guidance, but do NOT
relax constraints or accuracy verification.

**Investment rule**: spend the heavy machinery (DoD checklists, staged
decomposition, exemplars, XML scaffolding) on reasoning, planning, and
creative prompts.  For factual, classification, and retrieval prompts,
apply only scope-fence + format + success-criteria; extra structure has
near-zero marginal return there.

**Persona is genre-conditional**: use it for style/register only, never as
a correctness lever.  When precision matters, pair any persona with a
plain-language-summary requirement (persona trades clarity for perceived
depth).

## S3. Clarify vs. infer

Run this as its own pass -- models recognize ambiguity yet default to
answering anyway.  Per gap, in order:

1. **Classify type**: SCOPE, REFERENCE, CRITERION, CONSTRAINT, or PREFERENCE.
2. **Two-filter gate** -- ask only if BOTH hold: (a) *missing*-- a canonical
   instance of this genre would specify it; (b) *divergent*-- the deliverable
   materially changes depending on the answer (simulate both readings and
   compare).
3. **Type default**: SCOPE / CONSTRAINT / CRITERION with a divergent outcome,
   or any irreversible or destructive action -> **ASK**.  PREFERENCE, or
   any reversible/easily-revised choice -> **ASSUME and state it**.
4. **Stakes override** -- if a wrong reading would be costly, unsafe, or
   hard to reverse *even when the two readings look similar* (a dosage, a
   compliance threshold, a legal term), **ASK**, or emit the assumption
   conspicuously flagged, not buried in the list.

**Cap**: 2-3 questions maximum, in ONE batched round, never serial.  The
first question is near-free; friction rises steeply after, so reserve slots
for the highest-value gaps.  A short, sharp round usually costs the user
less than a wrong assumption propagating through a whole deliverable.

**Bare-brief exception**: when the deliverable itself is unidentifiable (a
REFERENCE gap at the artifact level -- "help me write something"), one scoping
round to fix *what the artifact is* comes first; then apply the normal
single-round cap to the remaining gaps.  This is not license for serial nagging
on preferences.

**Phrasing**: ground each question in a concrete instance or edge case, not
an abstract category.  Ask "if a reader has never leveled a print bed, explain
it or assume it's done?", not "what's your audience?".

**Re-check trigger**: if retrieval or added context filled a gap, re-run
this pass -- more context suppresses asking even when ambiguity remains.

Templates and the ambiguity taxonomy live in `references/clarify-taxonomy.md`.

## Output contract

**Default (inference path)** -- return, in order:

1. **Improved prompt** -- the rewrite, ready to paste.  Primary deliverable.
2. **Assumptions** -- itemized, falsifiable, individually overridable lines
   ("Assuming: target = web, not native mobile"); omit entirely if nothing
   was inferred.
3. **Rationale** -- 2-5 bullets, each naming a concrete flaw fixed (flaw ->
   fix, tied to a rubric dimension).  For small edits, show a diff instead.

**Ask path** (S3 triggered) -- return the 1-3 batched, instance-grounded
questions FIRST and nothing else; no rewrite yet.  After answers, resume
at step 6 and return the default package.

**Honesty clause** -- if the user says "optimize", state that this is a
single-shot, evidence-directed rewrite (grounded critique + best-last ordering +
multi-candidate merge), NOT a data-driven optimizer run; APE/OPRO/ProTeGi
need a labeled dev set and an eval loop this skill lacks.

**Never-degrade guard** -- flag any merged or paraphrased rewrite as "verify
against your success criteria" rather than asserting it is strictly better;
a reasonable-sounding merge can score worse than either parent.

## Reference files (load on demand, one hop only)

- Diagnosed genre -> `references/genre-recipes.md` (per-genre recipes,
  technique-family lookup, transfer evidence, merge/ordering mechanics).
- Clarify step -> `references/clarify-taxonomy.md` (types, question templates,
  Assumptions-block format).
- Diagnosed subject has a playbook -> `references/domains/<subject>.md`
  (subject vocabulary and defaults).  None ship by default;
  `references/domains/README.md` is maintainer documentation for adding one,
  not loaded during a run.
- Target is itself a skill or agent prompt -> `references/skill-authoring.md`
  (frontmatter contract, DoD gate).
