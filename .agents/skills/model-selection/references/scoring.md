# Scoring: Bands, Value, Tags, and Profiles

`scripts/score.py --pick` reads `~/.agents/model-benchmarks.json`
(registry schema 4).  Never select a model from memory.

## 1. Registry sections

| Section | Owner | Content |
| --- | --- | --- |
| `policy` | Hand | Band floors and anchors, `mythos` list, tags, roles, mix, harnesses, profiles |
| `overrides` | Hand | `match`, `placements`, `pi_thinking`, `vendor`, `track_only`, `notes` |
| `models` | Refresh | Variants with AAI (Artificial Analysis Intelligence Index v5), index cost, boards, pricing |
| `hosts.<h>` | Refresh | Harness health, Pi roster, Bedrock aliases, `default_profile` |
| `sources` | Refresh | Per-feed status, `as_of`, row counts, floors |

An unknown host uses `hosts["*"]` (Claude Code only, Claude models only)
and warns.  Source warnings cover the core feeds (`aa_free`,
`openrouter`, `pi_roster`, `claude_roster`) and the feeds behind the
requested tag, language, or role.  A source that is neither `ok` nor
`retired` warns, as does one older than `stale_days` (14) or missing
from `sources` while a requested board needs it.  Values from a source
older than `age_out_days` (90) are ignored, with a warning.

## 2. Bands

A variant is a (model, effort) pair.  Each variant is banded on its own
AAI at the `high`-effort floors: `bulk` 20.9, `haiku` 28.4, `sonnet`
39.4, `opus` 49.2.  Below 20.9 is unbanded.  `mythos` is a named list,
not a floor, and its models never enter an automatic pick.  An entry is
an exact ID or a family that ends in `*`: `anthropic/claude-fable-*`
makes every Fable version `mythos` with no edit per release.  Estimated
placements carry a confidence level; low or medium confidence on a pick
warns.

## 3. Ranking

The feasible set is the profile's variants that meet the band floor;
every pick is the best value within it.

Cost per variant: a harness billed on a `subscription` costs 0 (zero
marginal cost).  A metered
harness costs the index cost, repriced to the channel's price:
`index_cost x C(channel) / C(aa_pricing)`, with
`C = 0.75 x input + 0.25 x output`.  The tag cost ceiling below
compares on one basis: AA's index cost for a subscription variant, and
the repriced cost for a metered one.

A subscription variant with no AA index cost gets an estimate, marked
as estimated, instead of ranking last.  Let `tokens(m, e) =
index_cost(m, e) / C(m)`, with `C` from the model's `aa_pricing`, else
its `pricing`.  If the model has a measured effort, take the nearest
one as `e_ref` (the lower effort on a tie) and scale
`tokens(m, e_ref)` by the median of `tokens(e) / tokens(e_ref)` over
the registry models that have both efforts.  Otherwise, or when no model
has both, use the median `tokens(e)` over models.  The estimate is
tokens x `C(m)`.  Metered variants are never estimated.  With nothing
to estimate from, the variant ranks last as before.  A pick whose cost
is estimated warns, as does an estimated untagged pick behind a ceiling.

- **Untagged:** rank the band by value `V = AAI / cost`.  Zero-cost
  subscription variants rank first, lowest index cost first among
  them.  A variant with no index cost ranks after valued ones, with a
  warning.
- **Tagged:** first apply the cost ceiling (below), then take the
  competitive set: every variant whose tag score is within the tag's
  margin of the best of the capped pool (`ci`: intervals overlap;
  number: score >= best - margin; `multilingual` and `european` use the
  number 10, because their mean boards have no interval).  Equal values
  go to the higher score on the tag's `tiebreak` board.  Rank that set
  by `V`.  If the untagged pick has no score on the board, return it
  and warn that the tag was not applied.
- **Tag cost ceiling:** `TAG_COST_CEILING` in `score.py` is 1.5.  Before
  any tag narrows the pool, drop every variant costing more than 1.5
  times the untagged pick (the first variant by rank).  It covers the
  whole chain: the role's `rank_on` tag, `--tag`, and `--lang`.  An
  untagged pick with no cost sets no ceiling and warns.  A cost of 0
  admits only cost-0 variants.  A variant with no cost does not pass
  the ceiling.  When the ceiling changes the pick, a warning names the
  tag, the variant that would have won, and its cost multiple, as in
  "tag writing would pick anthropic/claude-opus-5.5 low at 8.1x the
  untagged pick's cost; capped at 1.5x".  The constant lives in code,
  not in registry policy, because `swap.sh update` never writes policy.
- **Language group:** applied after the specialty tag, the same way,
  on the language board.
- **`--role`:** sets the band from `policy.roles` and takes the
  competitive set on `long-horizon` before ranking by `V`.

## 4. Empty band

Step up one band at a time with a warning.  Never step into `mythos`.
If nothing is left and the profile's `empty_band` is `degrade`, `pick`
is null and `degrade` holds the best variant of the highest non-empty band
below the request (today in `pi-zdr`: GLM 5.3 at `max`).

## 5. Profiles

Fixed at session start, so a session's profile never changes (strong
tranquility, in the Bell-LaPadula sense).  First hit wins: `--profile`,
`MODEL_SELECTION_PROFILE`, `MODEL_SELECTION_HARNESS=pi` or `PI_CODING_AGENT`
(`pi-zdr`), `CLAUDE_CODE_USE_BEDROCK=1`, `CLAUDECODE`, the host's
default.  The innermost harness wins: Pi under Claude Code inherits
both markers.  Each profile names its `primary` harness, which decides
the in-process channel and `fallback`.

| Profile | Runs |
| --- | --- |
| `claude-code` | Subscription Claude at zero marginal cost, plus the zero-data-retention (ZDR) set through Pi |
| `claude-code-bedrock` | Metered Claude; aliases resolve through `bedrock_aliases` |
| `pi-zdr` | Pi `enabledModels` cut to the key's list; empty band degrades |
| `pi-permissive` | Placeholder: `pi-zdr` without the key filter |

## 6. Effort and channel in the output

`banded_effort` is the variant's measured effort.  `effort` is what to
dispatch: `--effort` if given (`off` through `max`; else exit 2); for a
Claude Code pick, the role effort (workers `medium`), capped to stay in
the band with a warning; for a Pi pick, the exact `--thinking` level
sent, after the `overrides.pi_thinking` remap (DeepSeek V4.1 Flash 0910:
`max` sends `high`) and the `single` rule.  A Pi thinking level absent
from the model's `pi_levels` skips the variant.  `mix_band` is the
pick's band (the degrade's band for a degrade), not the band of the
dispatched effort.  `score.py --mix` measures the target mix from the
log-dispatch hook's log: each logged dispatch counts in its variant's
band at the higher of the effort sent and `high`.  The Pi `command`
quotes every value and reads the brief from `--payload PATH` (default
`payload.md`).  Exit codes: 0 pick or degrade, 2 usage or registry
error, 3 neither.

### Inline work: token-share.py

`--mix` counts dispatches from the hook log.  A line holds the alias
that was requested (`model`).  When a fallback model answered, the
hook's `served_model` (or the worker transcript in `agent_transcript`,
which `--mix` reads at report time) names it, and `--mix` counts that
model.  The report's `served` field is the number of lines counted this
way.  `scripts/token-share.py`
shows tokens spent inline by each session, including Workflow agents
and work the log cannot see.  It reads usage fields only (model,
timestamp, token counts, session names), never message content.

    token-share.py [--days N] [--session PREFIX] [--json]

Transcripts under `~/.claude/projects` are grouped by role (from the
session name: executive, coordinator, pane-worker, else
standalone; plus subagent and scheduled) and by model family.  The
table gives messages, output tokens, input plus cache tokens, and the
percent of output.

## 7. Maintenance

- `score.py` runs `registry.validate` on load; a registry content error
  exits 2 with one line.  `validate` is the gate; it rejects unknown
  keys in `page`, `domains`, and board entries.  The JSON Schema file
  is documentation.

- Tests: `python3 -m unittest discover -s
  ~/.agents/skills/model-selection/scripts/tests`
- A model that fails to link to a feed: add
  `overrides.<id>.match.<feed>`.
- Layout change: raise `schema_version` in the schema, in
  `refresh-benchmarks.py`, and here together.
