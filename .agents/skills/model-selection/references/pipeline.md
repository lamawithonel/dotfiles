# Refresh Pipeline: Benchmark Ingestion and Feed Resilience

The script `scripts/refresh-benchmarks.py` is the single authoritative
writer of `~/.agents/model-benchmarks.json`.  It can be executed manually
or invoked as a scheduled service (such as a 6-hourly pitchfork daemon).

```sh
S=~/.agents/skills/model-selection/scripts
# Preview pending changes without modifying the registry
python3 $S/refresh-benchmarks.py --dry-run

# Execute full ingestion and atomic write
python3 $S/refresh-benchmarks.py

# Force re-probing of Claude CLI models
python3 $S/refresh-benchmarks.py --probe
```

---

## 1. Core Operating Principles

1. **Non-destructive updates:** Unfetched data must never overwrite
   existing values.  A transient feed failure preserves previous
   benchmark numbers and records an error status.  A null value is
   written only where data was never present.
2. **Validation gate:** New registry output passes `registry.validate`
   before writing; it is the gate (the JSON Schema file is
   documentation).  If validation fails, the current file is left
   untouched.
3. **Atomic persistence:** Updates write to a temporary file before an
   atomic rename operation, maintaining a `.bak` copy of the previous
   generation.

---

## 2. Ingestion Phases

| Phase | Target | Source | Fallback on Failure |
| --- | --- | --- | --- |
| 1. Pi Roster | Host capabilities | `~/.pi/agent/settings.json` | Marks `hosts.<h>.harnesses.pi.healthy` false if missing; retains known models with `enabled: false` |
| 2. Claude Probe | Host capabilities | `claude -p --model <alias>` candidate probes | Marks `hosts.<h>.harnesses.claude-code.healthy` false if missing; retains previous probe results |
| 3. OpenRouter API | Global models | `GET /api/v1/models` | Retains prior pricing and context limits; sets feed `status: "failed"` |
| 3a. Key prices | Prices this key pays | `~/.pi/agent/models-store.json` `openrouter.models[].cost` (local read, no network) | Retains prior prices; row minimum 72 |
| 4. AA free API v2 | AAI, index cost, domains | `GET /api/v2/language/models/free?page=N` (`x-api-key` header from `AA_API_KEY`; never in a URL or log) | Retains prior indices; row minimum 600 |
| 5. AA pages | Narrow fields | One GET per evaluation page: `tb4`, `lcr`, Cyber Index, HealthBench, AA-3D Elo with interval.  Nothing else is kept | Retains prior values; per-page row minimum |
| 6. Boards | Arena (Hugging Face datasets-server `/rows`), Design Arena, EQ-Bench | `scripts/boards.py` parsers | Preserves scores on parse failure; per-board row minimum |
| 7. Overrides | Custom settings | `overrides` section of registry | Applied before phase 1 (not after the feeds), to match keys, notes, and constraints |
| 8. Validation | Integrity check | `registry.validate` (structure, unknown keys, invariants) | Exits with error code if invalid; registry remains untouched |
| 9. Write | Registry update | Atomic filesystem replace | Writes new file and updates `.bak` backup |

Candidates for the Claude probe represent the union of the host's existing
`anthropic/*` roster IDs, `~/.claude.json` `additionalModelOptionsCache`
entries, and `overrides.<anthropic/id>.probe: true`.  The probe executes
only when `claude --version` differs from `hosts.<h>.probed_with.claude`
or when a candidate is newly introduced; `--probe` forces the probe, while
`--no-probe` skips it.

---

## 3. Match Keys and Derivation Rules

`models.<id>.match` is derived automatically from the roster ID and can be
patched per key in `overrides.<id>.match`:

| Key | Derivation Rule from `vendor/tail` (context suffixes stripped) |
| --- | --- |
| `openrouter` | `vendor/tail` |
| `aa_slug` | `tail` with periods (`.`) replaced by hyphens (`-`) |
| `board` | `[vendor/tail, tail, dashed]` |

Board feeds (Arena, Design Arena, EQ-Bench) match case-insensitively
against the `board` list; when several rows match, the highest score
wins.  The log line per feed emits matched counts, and
`sources.<feed>.matched` stores the count to ensure silent match misses
remain visible.

---

## 4. Feed Implementation Notes

- **OpenRouter:** Pricing values are expressed in USD per token.  The
  script scales these values by $10^6$ to compute pricing per million
  tokens.  The sentinel value `-1` marks routing aliases (such as
  `openrouter/auto`) and is skipped.  Variant suffixes (`:batch`, `-fast`)
  represent distinct model IDs and are never averaged.
- **Key prices and source rank:** The `openrouter_key` feed rereads
  Pi's models store, which holds the price this OpenRouter key pays
  (`source: "openrouter-key"`).  A price source overwrites only a source
  of equal or lower rank: `openrouter-key` beats `openrouter`, which
  beats every other feed, whichever feed runs last.  A change line shows
  both prices and sources, and numbers compare numerically.
- **HTTP retry:** Every fetch retries HTTP 5xx, timeouts, and connection
  errors after 2, 4, and 8 seconds.  HTTP 429 is also retried, up to 5
  times.  It waits exactly the `Retry-After` value (integer seconds or
  an HTTP date), or else backs off 5, 10, 20, 40, and 80 seconds, each
  times a random 0.5 to 1.5.  A wait that would end past the deadline
  is never taken, and with no deadline a `Retry-After` over 120 seconds
  raises.  No other 4xx is retried.
- **AA free API v2:** Writes per-variant `aai`, `index_cost_usd`,
  `domains`, and `aa_pricing`.  Effort comes from the slug or name
  suffix (`-high`, `(Xhigh)`).  The old `aa_api` feed is `retired`.
- **AA pages and Omniscience:** Narrow field reads only; drop page
  bytes after parsing.
- **Boards:** Pure parsers in `scripts/boards.py`, each with a row
  minimum.  Arena pages datasets-server `/rows` 100 rows at a time, in
  order, 1 second apart, with one fetch per config per run (`text` and
  `webdev`); the parsers filter by category.  A board feed that runs
  past 600 seconds fails and keeps its old values.  Before paging, one
  GET of the Hub dataset API
  (`https://huggingface.co/api/datasets/lmarena-ai/leaderboard-dataset`)
  reads the `sha`.  A config is cached in
  `${XDG_CACHE_HOME:-~/.cache}/agents/model-selection/arena-<config>.json`
  as `{"sha": ..., "pages": [...]}`, written atomically and only after a
  full paging.  When the Hub `sha` equals the cached one, the cached
  pages are used, nothing is paged, and one log line names the
  unchanged revision.  A failed Hub check, or a missing or corrupt
  cache, pages as usual.  An optional `HF_TOKEN` environment variable
  is sent as `Authorization: Bearer` to `huggingface.co` and its
  subdomains only, never follows a redirect, and is skipped with a
  warning if it holds control characters.  `redact()` scrubs it from
  feed errors.  Arena language boards feed `arena_lang_mean` and
  `arena_european_mean`.  A missing board stays null.
- **Row minimums:** Every parser raises `FeedMinRowsError`
  (`MinRowsError` in `boards.py`) below its row minimum, set near 60%
  of today's row count.  `apply_feed` then records
  `status: failed` and keeps old values.
- **DeepSWE:** Retired.  Values are kept and never used.
- **Fable:** An override matches `anthropic/claude-fable-5-1[1m]` to
  OpenRouter `anthropic/claude-fable-5.1`.
- **Pi roster:** `pi-zdr` is `enabledModels` intersected with
  `~/.pi/agent/models-store.json` `openrouter.models[].id`; a store
  older than 7 days warns.  Strip a `:<thinking>` suffix; skip
  `openrouter/auto`.

---

## 5. Multi-Host Dotfile Synchronization

The registry file is designed for seamless synchronization across multiple
hosts.  Each host updates only its own `hosts.<hostname>` block and
populates global `models` fields retrieved during refresh.  Sorted keys
and fixed indentation minimize version control diffs.

A host without external network egress refreshes local rosters and CLI
probes while utilizing synced benchmark indices.  Use the environment
variable `MODEL_SELECTION_HOST` to override the hostname and
`MODEL_BENCHMARKS` to override the registry file path.

---

## 6. Feed Troubleshooting

When a benchmark feed reports an error during refresh:

1. **Network or egress failure:** If HTTP requests time out or fail to
   connect, registry values remain intact.  No manual intervention is
   required.
2. **Parser schema mismatch:** If a scraping target alters its response
   structure, inspect the raw HTML or JSON payload and update the
   corresponding parser function in `scripts/refresh-benchmarks.py`.
   Parser unit tests are located in `scripts/tests/test_refresh.py`.
3. **Missing model mapping:** If a model is active but fails to link to
   feed benchmarks, add an explicit match pattern to `overrides.<id>.match`
   in `~/.agents/model-benchmarks.json`.
