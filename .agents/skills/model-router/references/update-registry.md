# Update Registry: Sync the Two-File Registry

The registry is split by sync domain:

- `~/.agents/benchmarks.json` -- GLOBAL benchmark and public-pricing
  facts.  Refreshed headlessly by `../scripts/refresh-benchmarks.py`
  (pitchfork cron daemon `benchmarks-refresh`, 6-hourly, notify-send
  on change).  Syncable via dotfiles; restricted hosts receive it by
  sync instead of fetching.
- `~/.agents/models.json` -- HOST-LOCAL roster: what THIS machine can
  reach, under this machine's ids.  Never sync it between machines;
  run this workflow on each host instead.

Run this workflow when a routing decision hits a missing model, the
Pi roster changed, the Claude CLI version changed (then start with
`discover-claude-models.md`), or the user asks.

Prime directive: **a number you did not fetch does not go in the
file**.  Unknown = `null` plus a `sources` note; never estimate.

## Step 0: Detect Host Capabilities

- `command -v pi` -> Pi channels exist; run Step 2 and price
  OpenRouter models via Step 1.
- No `pi` -> skip Step 2 entirely; the registry holds only models
  the local Claude Code deployment can dispatch.
- The Claude roster is deployment-specific and has no public
  enumeration endpoint for private hosting.  Detect it with the
  tiered workflow in `discover-claude-models.md` (seed ->
  `~/.claude.json` cache -> out-of-sandbox probe), and store the
  DEPLOYMENT's dispatch id (Bedrock/Enterprise ids differ from
  consumer ids, e.g. Bedrock `claude-5-sonnet[1m]` vs consumer
  `claude-sonnet-5`) in `execution` and `aliases`.
- Map each entry to its public identity via `public_id` (a key into
  `benchmarks.json`): a Bedrock snapshot that trails public release
  by weeks or months still maps to the same-named public model
  (e.g. `claude-opus-4-8[1m]` -> `claude-opus-4.8`).  Context-window
  variants of one model (`[1m]` vs 200K) get separate entries with
  the same `public_id`, differing in `context_window`.

## Step 1: Fetch OpenRouter Pricing (no auth)

```sh
S=${TMPDIR:-/tmp}/registry-sync; mkdir -p "$S"
curl -s --max-time 30 'https://openrouter.ai/api/v1/models' \
  -o "$S/or-models.json"
jq '.data | length' "$S/or-models.json"   # sanity: expect > 200
```

Per-token USD; multiply by 1e6 for per-M fields:

```sh
jq -r '.data[] | select(.id == "MODEL_ID")
  | {id, prompt_cost_per_m:  ((.pricing.prompt     | tonumber) * 1e6),
         completion_cost_per_m: ((.pricing.completion | tonumber) * 1e6),
         context_window: .context_length}' "$S/or-models.json"
```

Gotchas seen live:

- Variant suffixes exist (`:batch`, `-fast`); the registry stores the
  base id's standard pricing.  Do not average variants.
- Tilde-prefixed ids (`~vendor/model-latest`) are rolling aliases;
  skip them.
- Anthropic models ARE listed on OpenRouter; use those rows for
  Claude pricing so all pricing shares one source.

## Step 2: Sync the Pi Scoped Roster

Pi's scoped model list is `enabledModels` in
`~/.pi/agent/settings.json`:

```sh
jq -r '.enabledModels[]' ~/.pi/agent/settings.json
```

- `openrouter/<vendor>/<model>` entries: ensure a registry entry
  exists (id = the part after `openrouter/`); price via Step 1.
- Skip meta-router aliases (`openrouter/openrouter/auto*` and any
  future dynamic-routing ids): OpenRouter prices them with the
  sentinel `-1` per token, which is not a price.  Skip any id whose
  fetched pricing is negative.
- `llama-cpp/<name>` entries: local llama-swap models.  Keep the
  single `local/llama-cpp` class entry up to date (count, discovery
  command); do NOT enumerate every quant as its own entry.
- Registry entries whose id is no longer enabled and not an Anthropic
  native: mark `"enabled": false` rather than deleting (history and
  re-enable cheapness).

Context windows and catalog cross-check (offline, fast):

```sh
pi --offline --list-models | grep -iE 'PATTERN'
```

## Step 3: Benchmark Fetch Methods (reference)

`../scripts/refresh-benchmarks.py` implements everything in this
section against `benchmarks.json`; run it (or wait for the pitchfork
daemon) instead of doing this by hand.  The methods stay documented
here for debugging the script and for hosts where it cannot run.

Match models by the feed keys in each `benchmarks.json` entry's
`match` block, never by roster id.  A score for a different variant
(mini/flash/thinking-off/preview) does not count.  Record
disambiguation detail in `benchmark_notes`.  All fetch methods below
were live-verified on 2026-08-09.

### `terminal_bench_score` -- Terminal-Bench

```sh
curl -sL 'https://www.tbench.ai/leaderboard/terminal-bench/2.1' -o "$S/tb.html"
```

No JSON API.  Data is embedded Next.js flight data: join the
`self.__next_f.push([1,"..."])` chunks, unicode-unescape, then read
rows (`agent_display.label`, `model_display.label`,
`metrics.accuracy` in percent, `metadata.date`).  The 2.0 board uses
a different row shape (`accuracy` as 0-1 fraction).  Rules:

- Keep the registry's `sources.terminal_bench.primary_version`
  current (2.1 today; 3.0 lives at frontierbench.ai).
- A score from another version goes in with a
  `benchmark_versions` marker so the router excludes it.
- When a model has rows under multiple agent harnesses, store its
  BEST score (leaderboard convention) and record that agent in
  `benchmark_notes`, alongside the runner-up row for context.

### `deep_swe_score` -- Datacurve DeepSWE

```sh
curl -sL 'https://deepswe.datacurve.ai/' -o "$S/deepswe.html"
```

The v1.1 table is server-rendered HTML; strip tags to read model,
Pass@1 (percent), cost, tokens.  All rows use the mini-swe-agent
harness.  `/data/v1.1` is an HTML explorer, not JSON.  Beware the
name collision with the 2025 Agentica/Together "DeepSWE" RL agent--
different thing entirely.

### `artificial_analysis_index` -- Artificial Analysis

Preferred (keyed; free account, 1000 req/day):

```sh
curl -s 'https://artificialanalysis.ai/api/v2/data/llms/models' \
  -H "x-api-key: $AA_API_KEY" -o "$S/aa.json"
# field: .artificial_analysis_intelligence_index
```

No-key fallback: curl with a browser User-Agent; each per-model page
(`https://artificialanalysis.ai/models/<slug>`, slugs in
sitemap.xml) contains the literal sentence "<name> scores N on the
Artificial Analysis Intelligence Index".  Reasoning and non-reasoning
variants share display names on the leaderboard-- disambiguate via
the per-model page.  Record the index version (v4.1.1 today);
versions are NOT mutually comparable.

### `eq_bench_score` -- EQ-Bench

```sh
curl -sL 'https://eqbench.com/eqbench4/eqbench4_data.js' \
  | sed -e '1d' -e 's/^const EQBENCH4_DATA = //' -e 's/;\s*$//' \
  | jq '.models[] | {model, elo, ci_low, ci_high}'
```

ELO scale.  The flagship data file is whatever eqbench.com's index
page references in its `<script src=...>`; re-derive it from the
index HTML if the path 404s.

### `design_arena_score` -- Design Arena

```sh
curl -s -X POST 'https://www.designarena.ai/api/leaderboard' \
  -H 'Content-Type: application/json' \
  -d '{"arenaType":"models","category":"website"}' \
  | jq '.data[] | {modelId, elo, battles, winRate}'
```

GET returns 405; POST only.  `website` is the flagship UI/UX
category; there is no cross-category aggregate.  ELO recomputes
roughly every 2 hours, so scores drift-- record the snapshot's
`metadata.lastUpdateTime` as `as_of`.

## Step 4: Merge the Roster

`benchmarks.json` is written only by the refresh script; this step
builds the ROSTER file:

1. Start from the CURRENT `~/.agents/models.json` (keep every field
   the discovery steps do not touch: execution blocks, tags,
   constraints, notes).
2. Apply Step 0/2 roster changes.  Every non-class entry gets a
   `public_id` that exists in `benchmarks.json`; if the identity is
   missing there, add it with null values and a `match` block (the
   refresh daemon fills it).  Set `updated_at` with
   `date -u +%Y-%m-%dT%H:%M:%SZ` (never a hand-rounded or future
   time).
3. Stage on the DESTINATION filesystem so the final rename is atomic
   (staging in `$TMPDIR` makes `mv` a cross-filesystem copy):
   write to `~/.agents/.models.json.tmp`.

## Step 5: Validate, Then Install

Gates are chained: a failure aborts BEFORE the install, the old
roster stays in place, and you report which gate failed.  Local
`pricing` overrides may only carry source `"local"`, and no price
may be negative (OpenRouter uses `-1` as a routing-alias sentinel).

```sh
N=~/.agents/.models.json.tmp
jq . "$N" > /dev/null &&
jq -e '.schema_version and .updated_at and (.models | length > 0)' \
  "$N" > /dev/null &&
jq -e '[.models[] | select((.public_id == null)
  and (.is_class_entry != true))] | length == 0' "$N" > /dev/null &&
jq -e '[.models[] | select(.pricing != null
  and .pricing.source != "local")] | length == 0' "$N" > /dev/null &&
jq -e '[.models[] | .pricing // {}
  | select((.prompt_cost_per_m // 0) < 0
    or (.completion_cost_per_m // 0) < 0)] | length == 0' \
  "$N" > /dev/null &&
jq -e --slurpfile b ~/.agents/benchmarks.json \
  '[.models[] | select(.public_id != null)
    | select($b[0].models[.public_id] == null)] | length == 0' \
  "$N" > /dev/null &&
cp ~/.agents/models.json "$S/models.backup.json" &&
mv "$N" ~/.agents/models.json &&
echo "roster installed" || { echo "GATE FAILED: roster NOT \
installed; new file left at $N for inspection" >&2; false; }
```

Never hand-edit a benchmark score without a source URL to cite.

## Step 6: Report

Summarize to the user: models added/disabled, price changes > 20%,
benchmarks that went stale (feed unreachable), and fields still
`null` with the blocking reason.
