# Refresh Pipeline: How the Registry Is Built and Degrades

`scripts/refresh-benchmarks.py` is the only writer of
`~/.agents/model-benchmarks.json`.  Run it by hand, or let the
pitchfork daemon `benchmarks-refresh` run it 6-hourly.  This page
explains each phase, what "unavailable" does to it, and how to debug
a feed.  The scoring policy lives in `SKILL.md` and `scripts/score.py`.

```sh
S=~/.agents/skills/model-router/scripts
fnox exec --non-interactive -- python3 $S/refresh-benchmarks.py --dry-run   # preview changes
fnox exec --non-interactive -- python3 $S/refresh-benchmarks.py             # write
python3 $S/refresh-benchmarks.py --skip aa_api --skip aa_omniscience        # no AA key on this host
python3 $S/refresh-benchmarks.py --probe                                    # force the Claude probe
python3 $S/refresh-benchmarks.py --registry /tmp/x.json --host lab-01        # elsewhere
```

Prime directive: **a number you did not fetch does not go in the
file.**  Corollary: a fetch that fails changes nothing.  Null is
written only where there was never a value.

## Phases

| # | Phase            | Source                                   | Unavailable how                       | Behaviour                                                                 |
| - | ---------------- | ---------------------------------------- | ------------------------------------- | ------------------------------------------------------------------------- |
| 1 | Pi roster        | `~/.pi/agent/settings.json` `enabledModels` | `pi` not on PATH or file missing   | `hosts.<h>.channels.pi=false`; existing Pi entries kept, `enabled:false`, `note: pi-missing` |
| 2 | Claude probe     | `claude -p --model <alias>` per candidate | `claude` not on PATH                 | `channels.claude-code=false`; entries kept, disabled, `note: claude-missing` |
|   |                  |                                          | CLI present, every probe errors       | prior roster kept; `sources.claude_roster.status=failed`                  |
| 3 | OpenRouter       | `GET /api/v1/models`                     | egress blocked                        | pricing + context windows keep old values; `status=failed`, `error` stored |
| 4 | AA API           | `GET /api/v2/data/llms/models` + `AA_API_KEY` | key unset or blocked            | same                                                                      |
| 5 | AA Omniscience   | evaluations page, Next.js flight data    | blocked or page shape changed         | same; **zero matched rows counts as failure**, never as "everyone left"   |
| 6 | DeepSWE, EQ-Bench, Design Arena | leaderboards              | blocked or shape changed              | same                                                                      |
| 7 | Overrides        | `overrides` block in the file            | n/a                                   | applied before feeds (match keys) and after (notes, `track_only`)         |
| 8 | Validate         | `schema/model-benchmarks.schema.json` + invariants | schema lib missing          | schema gate skipped with a log line; invariants still checked             |
| 9 | Write            | atomic rename, one `.bak` generation     | gate failed                           | exit 3 (schema) or 2 (no enabled roster entry); file untouched            |

Candidates for the Claude probe are the union of the host's existing
`anthropic/*` roster ids, `~/.claude.json` `additionalModelOptionsCache`
values, and `overrides.<anthropic/id>.probe: true`.  The probe runs
only when `claude --version` differs from `hosts.<h>.probed_with.claude`
or a candidate is new; `--probe` forces it, `--no-probe` skips it.
The probe needs the CLI's network, so it fails inside sandboxed tool
calls; the daemon and a plain terminal are fine.

## Model presence vs. feed presence

A model absent from a feed that DID fetch keeps its old value; only
`last_seen.<feed>` stops advancing.  `score.py` treats a value not
re-seen for 90 days as null.  That is how a model that falls off a
leaderboard ages out without a human nulling it, and how a transient
scrape miss does not nuke a score.

## Match keys

`models.<id>.match` is derived from the roster id by rule and can be
patched per key from `overrides.<id>.match`:

| Key           | Derived from `vendor/tail` (context suffix like `[1m]` stripped) |
| ------------- | ---------------------------------------------------------------- |
| `openrouter`  | `vendor/tail`                                                    |
| `aa_slug`     | `tail` with `.` -> `-`                                           |
| `deepswe`     | `[tail, dashed]`                                                 |
| `eqbench`     | `[vendor/tail, tail, dashed]`                                    |
| `designarena` | `[tail, dashed]`                                                 |

Feeds are matched case-insensitively against these lists; first hit
wins.  The log line per feed reports `matched` counts, and
`sources.<feed>.matched` stores the last count, so a silent miss is
visible.  Typical patches: AA aliases a dated snapshot to the base
slug (`deepseek-v4-flash-0731` -> `deepseek-v4-flash`); EQ-Bench uses
a dated Claude id (`claude-haiku-4-5-20251001`).

## Feed notes (live-verified 2026-09-06)

- **OpenRouter** prices are USD per token; the script multiplies by
  1e6.  `-1` is a routing-alias sentinel (`openrouter/auto`), skipped.
  Variant suffixes (`:batch`, `-fast`) are separate ids and never
  averaged.  Anthropic models are listed, so Claude pricing shares the
  source; the AA API supplies a fallback when OpenRouter lacks a row.
- **AA API v2** (`x-api-key`, free account, 1000 req/day) carries
  `artificial_analysis_intelligence_index`,
  `artificial_analysis_coding_index`, `terminalbench_v2_1` (fraction,
  stored x100 as `terminal_bench`), and blended pricing.  Slugs are
  base models; `-low/-high/-non-reasoning` variants are separate slugs
  and only match when an override names one.  The API does NOT carry
  Omniscience.
- **AA Omniscience** lives only on the evaluations page as Next.js
  flight data: per slug, `"omniscience": N` and
  `"omniscienceBreakdown": {"hallucinationRate": r}`.  Stored as
  `aa_omniscience = N` and `aa_factuality = 1 - r` so every field
  stays higher-is-better.  The page renders the chart-selected subset
  (about 30 models), so coverage is partial by design.
- **DeepSWE v1.1** is a server-rendered table; after tag stripping
  each cell is a line: `model`, `[`, `effort`, `]`, `pct`, `%`.  The
  "Best" table precedes the all-efforts table, and first hit wins.
  Not the 2025 Agentica/Together "DeepSWE" RL agent.
- **EQ-Bench 4** is a JS data file: drop the comment line, strip
  `const EQBENCH4_DATA = ` and the trailing `;`.  ELO.
- **Design Arena** is `POST /api/leaderboard` with
  `{"arenaType":"models","category":"website"}`; GET returns 405.
  ELO recomputes roughly 2-hourly; changes under 10 points are
  ignored to damp churn.

## Multi-host use

The file is meant to be synced.  Each host writes only its own
`hosts.<hostname>` block plus whatever global `models` fields it
could fetch; sorted keys and fixed indentation keep dotfile merges
small.  A host with no egress still refreshes its roster and probes,
and scores with whatever benchmark data arrived by sync.
`MODEL_ROUTER_HOST` overrides the hostname; `MODEL_BENCHMARKS`
overrides the file path.

## Debugging a feed

1. Run with `--dry-run`; read the per-feed log line
   (`ok, N matched` / `failed (reason)`).
2. `failed` with an HTTP or timeout error: egress.  Nothing to fix in
   the registry; values stay.
3. `failed (zero rows matched ...)`: the page shape changed.  Save the
   page to the scratchpad and adjust the parser in the script; the
   parser functions are pure (`parse_*`) and unit-tested with small
   fixtures in `scripts/tests/test_refresh.py`.
4. `ok` but a model you expect is missing: compare the feed's name for
   it with `models.<id>.match.<feed>` and patch via `overrides`.
