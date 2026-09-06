# Scoring: Registry Layout, Policy, and Degradation

The policy behind `scripts/score.py --pick`.  `SKILL.md` carries only
what an agent needs to run the command; everything the command does
is explained here.  No model is ever chosen from memory.

One file: `~/.agents/model-benchmarks.json`, validated by
`schema/model-benchmarks.schema.json` (JSON Schema 2020-12,
`schema_version` 3).  Written only by
`scripts/refresh-benchmarks.py`; humans and agents edit the
`overrides` block and nothing else.

| Section     | Owner    | Scope                                                        |
| ----------- | -------- | ------------------------------------------------------------ |
| `models`    | script   | global facts keyed by roster id: match keys, benchmarks, pricing, `last_seen` |
| `hosts.<h>` | script   | this host's roster: enabled, channels, execution blocks, probe stamps |
| `sources`   | script   | per-feed `status` (`ok`/`failed`/`skipped`/`never`), `as_of`, `error` |
| `overrides` | human    | `tier_4_only`, `tags`, `match` patches, `track_only`, `probe`, notes |

## Registry Checks (what `score.py` enforces)

1. `check-jsonschema --schemafile ~/.agents/skills/model-router/schema/model-benchmarks.schema.json ~/.agents/model-benchmarks.json`.
   A schema failure means a hand edit broke the file; fix `overrides`
   or rerun the refresh script, which restores from `.bak` semantics
   (it never writes an invalid file).
2. `hosts` must contain this host's short hostname.  If not, the
   registry has never been refreshed here: run
   `scripts/refresh-benchmarks.py` (needs egress for feeds; roster
   phases work offline) and stop routing until it succeeds.
3. `score.py` prints a warning per source whose `status` is not `ok`
   or whose `as_of` is older than 14 days.  Relay the warning; route
   anyway.  A pitchfork cron daemon (`benchmarks-refresh`, 6-hourly)
   keeps the file fresh where it runs.
4. Null is never fabricated.  A null benchmark drops out of the
   weighted sum (weights renormalize); an all-null model is
   ineligible for automatic selection and reachable only by user
   directive.  A feed value not re-seen for 90 days scores as null
   (`last_seen` age-out), so models that fall off a leaderboard age
   out without a human nulling them.
5. `channels.pi` or `channels.claude-code` false on this host makes
   every entry native to that harness ineligible here, even if listed.

Harness detection and channel availability are dispatch concerns
(`channel-external.md`); the registry records what the refresh script
observed, and the dispatch step confirms it.

## Classification Detail

### Tiering System

| System    | When                                                   |
| --------- | ------------------------------------------------------ |
| `general` | everything not below                                   |
| `design`  | visual design, UI/UX layout, front-end aesthetics, landing pages, anything judged by how it looks |

### Benchmark Profile (general system only)

Pick exactly one; it selects the weights in `score.py` `PROFILES`:

| Profile     | Task shapes                                          | Weights                                                                   |
| ----------- | ---------------------------------------------------- | ------------------------------------------------------------------------- |
| `coding`    | bug fixes, refactors, multi-file edits, test writing | aa_coding .35, deep_swe .25, terminal_bench .15, aa_omniscience .15, aa_factuality .10 |
| `reasoning` | architecture, root-cause analysis, planning, math    | aa_intelligence .50, aa_omniscience .20, aa_factuality .15, deep_swe .15  |
| `style`     | copy, docs, formatting, naming, review prose         | design_arena .45, eq_bench .25, aa_factuality .15, aa_intelligence .15    |

Benchmark fields (all higher-is-better; `aa_factuality` is
`1 - AA Omniscience hallucination rate`, `terminal_bench` is AA's
`terminalbench_v2_1` in percent):

| Field             | Feed             | Scale        |
| ----------------- | ---------------- | ------------ |
| `aa_intelligence` | `aa_api`         | index points |
| `aa_coding`       | `aa_api`         | index points |
| `terminal_bench`  | `aa_api`         | percent      |
| `aa_omniscience`  | `aa_omniscience` | index points |
| `aa_factuality`   | `aa_omniscience` | 0..1         |
| `deep_swe`        | `deep_swe`       | percent      |
| `eq_bench`        | `eq_bench`       | ELO          |
| `design_arena`    | `design_arena`   | ELO          |

### Complexity Tier (general system)

| Tier | Name                      | Characteristics                                                        |
| ---- | ------------------------- | ---------------------------------------------------------------------- |
| 1    | High-Volume / Low-Context | predictable, linear, single-file, deterministic transforms, searches   |
| 2    | Systems Integration       | multi-file features, bounded refactors, localized API mapping          |
| 3    | High Abstraction          | zero-to-one design, race conditions, silent systemic failures          |
| 4    | Frontier                  | correctness above all, cost irrelevant; the best model this host can reach |

A user who names a model overrides every tier; that is a directive,
not a tier, and needs no scoring.

### Rung (design system)

The design ladder has four rungs read the same way a user reads the
Design Arena "preference vs price" chart: 1 = cheapest model on the
Pareto frontier, 4 = best-looking model on it, 2 and 3 spread evenly
between.  Pick the rung by how much the visual result matters
relative to spend; a user directive still overrides.

## Scoring

Run it, do not hand-compute:

```sh
python3 ~/.agents/skills/model-router/scripts/score.py --system general --profile coding --tier 2
python3 ~/.agents/skills/model-router/scripts/score.py --system general --profile reasoning --tier 4
python3 ~/.agents/skills/model-router/scripts/score.py --system design
python3 ~/.agents/skills/model-router/scripts/score.py --json            # everything, machine-readable
python3 ~/.agents/skills/model-router/scripts/score.py --include-track-only   # also show overrides.*.track_only models (comparison only, never dispatchable)
```

What the script does (policy constants live in `score.py` and here,
never in the registry):

0. **Comparability gate:** a score whose `benchmark_versions[field]`
   differs from the feed's `primary_version` is treated as null.
1. **Normalize** each field with min-max across candidates where the
   value is non-null and comparable.  Min-max because ELO scales have
   no meaningful zero.  With one scored model, `norm = 1` (weak
   evidence).
2. **Quality** `Q = sum(w_b * norm_b) / sum(w_b)` over non-null fields.
3. **Blended cost** `C = 0.75 * prompt + 0.25 * completion` ($/M),
   from the model's `pricing` unless the roster entry carries a local
   `pricing` override (that is how the local class entry gets `C = 0`).
4. **Select by tier** (general):

   | Tier | Rule                                                                       |
   | ---- | -------------------------------------------------------------------------- |
   | 1    | eligible if `Q >= 0.40`; pick minimum `C`; ties favor higher `Q`           |
   | 2    | eligible if `Q >= 0.60`; pick maximum `V = Q / (C + 0.05)`                 |
   | 3    | pick maximum `Q`; within 0.02 favor lower `C`; within 0.05 favor more non-null benchmarks |
   | 4    | pick maximum `Q` with `tier_4_only` models eligible; cost ignored; within 0.05 favor more non-null benchmarks |

   The Tier 2 floor exists because raw `V` lets a very cheap, weak
   model beat a far better one; integration work needs a quality bar
   before cost is allowed to decide.

5. **Design ladder:** candidates with both `design_arena` and `C`;
   Pareto frontier of (lower `C`, higher ELO) walked cost-ascending;
   frontier index `i` of `n` maps to rung `1 + round(3 i / (n - 1))`.
   A rung can be empty when the frontier is short; say so and offer
   the nearest lower rung.

### Hard Constraints

- `overrides.<id>.constraints.tier_4_only` makes a model ineligible
  for Tiers 1 to 3 and for the design ladder; Tier 4 and a user
  directive are its only paths in.  Instances are flagged in
  `overrides`, never named in this file.
- `track_only` models (benchmarked for comparison, in no roster) are
  never dispatchable; they appear only with `--include-track-only`.
- A `context_window` smaller than the estimated task context makes
  a model ineligible.  Null means unknown; the Tier 4 issuer owns
  the risk.

## Hand Back

Return the selected id with its `hosts.<h>.roster.<id>.execution.<harness>`
block verbatim: `model_param` for a native dispatch (Claude Code
`Agent` tool), `model_ref` for Pi native, `command` for an external
channel.  Mention the tier/rung, `Q`, `C`, and any source warnings.

Everything downstream is dispatch: which channel carries the work
(`channel-native.md`, `channel-external.md`) and the brief the worker
receives (`brief.md`).

## Maintenance

- Everything is regenerated by `scripts/refresh-benchmarks.py`
  (`references/pipeline.md` explains each phase, its failure mode, and
  how to debug a feed).  Pitchfork daemon `benchmarks-refresh` runs it
  6-hourly with `AA_API_KEY` from fnox; `--dry-run` previews.
- New model in Pi: appears on the next run.  New Claude model: add
  `overrides.<anthropic/id>.probe: true` or let the `~/.claude.json`
  picker cache propose it; the probe decides.
- Feed match miss: add `overrides.<id>.match.<feed>`; the script logs
  `matched` counts per feed so a miss is visible.
- Unit tests: `python3 -m unittest discover -s ~/.agents/skills/model-router/scripts/tests`.
- Schema changes: bump `schema_version` in the schema (`const`), the
  script's `empty_registry`, this file, and `references/pipeline.md`
  in one change.
