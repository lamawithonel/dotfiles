---
name: model-router
description: >-
  Score and select a model for already-scoped delegated work.  Use
  when the question is "which model", when a dispatch names no model,
  and whenever `delegate` reaches the model-choice step.  Reads the
  two-file registry (host-local ~/.agents/models.json roster +
  syncable ~/.agents/benchmarks.json) and ranks candidates on real
  benchmark metrics (Terminal-Bench, agentic SWE, Artificial Analysis,
  EQ-Bench, Design Arena) and live OpenRouter pricing.  Returns the
  model and its dispatch parameters; `delegate` owns the channel.
---

# Model Router

Data-driven replacement for hardcoded model rankings.  Every routing
decision reads the two-file registry and computes a score; no model is
ever chosen from memory.

- `~/.agents/models.json` -- HOST-LOCAL roster: which models this
  host reaches, their ids, execution channels, and constraints.
- `~/.agents/benchmarks.json` -- SYNCABLE global facts: benchmark
  scores and public pricing keyed by public model identity; roster
  entries point into it via `public_id`.

## Step 0: Load and Validate the Registry

1. Read `~/.agents/models.json` and `~/.agents/benchmarks.json`.
2. Check `benchmarks.json` `updated_at`.  A pitchfork cron daemon
   (`benchmarks-refresh`, 6-hourly) keeps it fresh where it runs; on
   hosts without it the file arrives via dotfile sync.  If older than
   14 days, tell the user and offer to run
   `scripts/refresh-benchmarks.py` (needs open egress) before
   routing.  Route with stale data only if the user declines or the
   refresh fails.
3. If the roster looks wrong (a model errors on dispatch, or the
   Claude CLI version changed since `models.json` was built), run the
   discovery workflow at `references/discover-claude-models.md`.
4. Benchmark fields may be `null` (never fabricated).  The scoring
   rules below define how nulls degrade.

Harness detection and channel availability are the `delegate` skill's
job (`references/channel-external.md`).  They never change the
candidate set-- every registry model is a candidate in every harness--
but a model whose only channel's CLI is missing on this host is
ineligible, so run that probe before scoring.

## Step 1: Classify the Task

### Benchmark Profile

Pick exactly one profile; it selects the benchmark weights:

| Profile     | Task shapes                                          | Weights                                     |
| ----------- | ---------------------------------------------------- | ------------------------------------------- |
| `coding`    | bug fixes, refactors, multi-file edits, test writing | terminal_bench .45, deep_swe .35, aa_index .20 |
| `reasoning` | architecture, root-cause analysis, planning, math    | aa_index .70, terminal_bench .15, deep_swe .15 |
| `style`     | UI/UX, copy, docs, formatting, naming, review prose  | design_arena .50, eq_bench .30, aa_index .20   |

Field name mapping: `terminal_bench` -> `terminal_bench_score`,
`deep_swe` -> `deep_swe_score`, `aa_index` ->
`artificial_analysis_index`, `eq_bench` -> `eq_bench_score`,
`design_arena` -> `design_arena_score`.  Values come from
`benchmarks.json` `models[<public_id>].benchmarks`; its `sources`
block says what feed currently backs each field.

### Complexity Tier

| Tier | Name                      | Characteristics                                                        |
| ---- | ------------------------- | ---------------------------------------------------------------------- |
| 1    | High-Volume / Low-Context | predictable, linear, single-file, deterministic transforms, searches   |
| 2    | Systems Integration       | multi-file features, bounded refactors, localized API mapping          |
| 3    | High Abstraction          | zero-to-one design, race conditions, silent systemic failures          |
| 4    | User Directive            | the user explicitly named a model                                      |

## Step 2: Score

All benchmarks in the registry are higher-is-better (percentages,
index points, or ELO alike).

0. **Comparability gate:** a score whose version differs from the
   source's `primary_version` (see the model's `benchmark_versions`
   and the registry `sources` block) is treated as null for scoring.
   Example: a Terminal-Bench 2.0 score never competes against 2.1
   rows.

1. **Normalize** each benchmark `b` per model `m` with min-max across
   all registry models where the value is non-null and comparable:

       norm(m, b) = (value(m, b) - min_b) / (max_b - min_b)

   Min-max (not divide-by-max) because ELO scales (EQ-Bench, Design
   Arena) have no meaningful zero; ratio normalization would flatter
   the worst model.  Degenerate case: with only one scored model,
   `norm = 1`; treat that benchmark as weak evidence, since it cannot
   differentiate candidates.

2. **Quality** is the weight-renormalized sum over the profile's
   benchmarks that are non-null for the model:

       Q(m) = sum(w_b * norm(m, b)) / sum(w_b)   for non-null b

   If ALL profile benchmarks are null, the model is ineligible for
   automatic selection; it can still be chosen by Tier 4 directive--
   this is how unbenchmarked local `llama-cpp` quants are used.

   More-benchmarks preference: when a selection compares candidates
   on Q DIRECTLY (the Tier 1 floor, Tier 3 ranking) and two sit
   within 0.05, prefer the one with more non-null benchmarks-- a Q
   built on one benchmark is noisier than a Q built on three.  It
   never reorders Tier 2's V ranking, and a tier's own tie rule
   (e.g. Tier 3's within-0.02-favor-cheaper) takes precedence when
   both fire.

3. **Blended cost** models the ~3:1 input:output shape of agentic work:

       C(m) = 0.75 * prompt_cost_per_m + 0.25 * completion_cost_per_m

   Pricing comes from `benchmarks.json` via `public_id`; a `pricing`
   block directly on the roster entry overrides it (that is how the
   local `llama-cpp` class entry gets `C = 0`).  A roster entry with
   `public_id: null` has no benchmarks by construction and follows
   the all-null rule above.

4. **Select by tier** (policy constants are tunable policy, not data;
   they live only here):

   | Tier | Rule                                                              |
   | ---- | ----------------------------------------------------------------- |
   | 1    | eligible if `Q >= 0.40`; pick minimum `C`; ties favor local       |
   | 2    | pick maximum `V = Q / (C + 0.05)` (epsilon = host-compute floor)  |
   | 3    | pick maximum `Q`; ties within 0.02 favor lower `C`                |
   | 4    | obey the user verbatim; no scoring                                |

### Hard Constraints

- `constraints.tier_4_only` makes a model ineligible for automatic
  selection; Tier 4 is its only path in.  Instances are flagged in the
  host-local registry, never named in shared files.
- A model whose `context_window` is smaller than the estimated task
  context is ineligible regardless of score.  A null `context_window`
  means unknown; the constraint does not apply, and the Tier 4 issuer
  owns the risk.

## Step 3: Hand Back

Return the selected model together with its `execution.<harness>`
block from the registry.  Native when the model's `native_harness`
includes the active harness, external otherwise; the block is
authoritative either way and is used verbatim-- `model_param` for a
native dispatch, `command` for an external one.

`delegate` owns everything downstream: which channel carries the work
(`references/channel-native.md`, `references/channel-external.md`),
and the brief the worker receives (`references/brief.md`).

## Worked Example (illustration only)

Snapshot of one host's registry, 2026-08-09; model names here are
teaching material, not routing truth-- your host's registry is the
only candidate source.

Task: "fix the failing test in `./foo.rs`"-- profile `coding`,
Tier 2, running in Claude Code with Pi installed.

Registry ranges (comparable values only): terminal_bench 2.1
[65.84, 83.82], deep_swe [12, 74], aa_index [30, 63].  Rows shown:
top three by V, plus gpt-5.6-luna (highest external Q) and
claude-sonnet-5 (best-V native model) for contrast.

| Candidate                | tb    | swe   | aa    | Q     | C ($/M) | V = Q/(C+.05) |
| ------------------------ | ----- | ----- | ----- | ----- | ------- | ------------- |
| deepseek-v4-flash-0731   | null  | null  | 0.667 | 0.667 | 0.113   | 4.10          |
| z-ai/glm-5.2             | null  | 0.516 | 0.697 | 0.582 | 0.108   | 3.69          |
| deepseek-v4-flash        | null  | 0.661 | null  | 0.661 | 0.175   | 2.94          |
| openai/gpt-5.6-luna      | 0.550 | 0.887 | 0.667 | 0.691 | 0.225   | 2.51          |
| claude-sonnet-5          | 0.488 | 0.677 | 0.758 | 0.608 | 4.00    | 0.150         |

Tier 2 selects on V, so `deepseek-v4-flash-0731` wins outright.  Note
what does NOT happen: luna holds the highest Q (0.691, three
benchmarks) with 0731 and v4-flash inside its 0.05 band on
one-benchmark Qs, but the more-benchmarks preference governs Q-based
selection (Tiers 1 and 3) and never reorders a V ranking.  Hand back
that model with its external `command`.

Had the task been Tier 3 architecture work (profile `reasoning`),
max-Q would instead select `claude-opus-5` (aa norm = 1.0)-- a native
entry, handed back as `model_param: opus`.

## Maintenance

- Benchmarks and pricing (`benchmarks.json`): refreshed headlessly by
  `scripts/refresh-benchmarks.py` -- pitchfork cron daemon
  `benchmarks-refresh`, 6-hourly, notify-send on change; the user
  pushes to dotfiles when they choose.  Manual fetch methods:
  `references/update-registry.md`.
- Host roster (`models.json`): Pi roster via
  `references/update-registry.md`; Claude roster via
  `references/discover-claude-models.md` (seed -> cache -> probe;
  probe runs OUTSIDE sandboxed tool calls).
- Schema changes: bump the touched file's `schema_version` and update
  this file plus the reference workflows in the same change.
