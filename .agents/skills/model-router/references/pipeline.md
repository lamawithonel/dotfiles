# Refresh Pipeline: Benchmark Ingestion and Feed Resilience

The script `scripts/refresh-benchmarks.py` is the single authoritative
writer of `~/.agents/model-benchmarks.json`.  It can be executed manually
or invoked as a scheduled service (such as a 6-hourly pitchfork daemon).

```sh
S=~/.agents/skills/model-router/scripts
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
2. **Schema validation gate:** New registry output is validated against
   `schema/model-benchmarks.schema.json` before writing.  If validation
   fails, the current file is left untouched.
3. **Atomic persistence:** Updates write to a temporary file before an
   atomic rename operation, maintaining a `.bak` copy of the previous
   generation.

---

## 2. Ingestion Phases

| Phase | Target | Source | Fallback on Failure |
| --- | --- | --- | --- |
| 1. Pi Roster | Host capabilities | `~/.pi/agent/settings.json` | Marks `channels.pi=false` if missing; retains known models with `enabled: false` |
| 2. Claude Probe | Host capabilities | `claude -p --model <alias>` candidate probes | Marks `channels.claude-code=false` if missing; retains previous probe results |
| 3. OpenRouter API | Global models | `GET /api/v1/models` | Retains prior pricing and context limits; sets feed `status: "failed"` |
| 4. AA API v2 | Benchmark indices | `GET /api/v2/data/llms/models` (`AA_API_KEY`) | Retains prior indices; logs authentication or network error |
| 5. AA Omniscience | Hallucination rates | Next.js flight payload from evaluations page | Retains prior metrics; zero matched entries triggers failure status |
| 6. Public Leaderboards | Coding and design ELO | DeepSWE, EQ-Bench, and Design Arena endpoints | Preserves historical scores on parse failure or schema change |
| 7. Overrides | Custom settings | `overrides` section of registry | Applied to match keys, notes, and constraints |
| 8. Validation | Integrity check | JSON schema verification and structural invariant validation | Exits with error code if invalid; registry remains untouched |
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
| `deepswe` | `[tail, dashed]` |
| `eqbench` | `[vendor/tail, tail, dashed]` |
| `designarena` | `[tail, dashed]` |

Feeds match case-insensitively against these candidate lists; the first
match wins.  The log line per feed emits matched counts, and
`sources.<feed>.matched` stores the count to ensure silent match misses
remain visible.

---

## 4. Feed Implementation Notes

- **OpenRouter:** Pricing values are expressed in USD per token.  The
  script scales these values by $10^6$ to compute pricing per million
  tokens.  The sentinel value `-1` marks routing aliases (such as
  `openrouter/auto`) and is skipped.  Variant suffixes (`:batch`, `-fast`)
  represent distinct model IDs and are never averaged.
- **Artificial Analysis API v2:** Requires `AA_API_KEY` (free tier allows
  1,000 requests daily).  Provides `artificial_analysis_intelligence_index`,
  `artificial_analysis_coding_index`, and `terminalbench_v2_1` (fraction,
  stored multiplied by 100 as `terminal_bench`).  Variants with `-low`,
  `-high`, or `-non-reasoning` represent separate slugs and match only
  when explicitly named in overrides.
- **AA Omniscience:** Ingested from Next.js flight data on the evaluations
  page.  Stored as `aa_omniscience = N` and `aa_factuality = 1 - r` (where
  $r$ is the hallucination rate) so all metrics remain higher-is-better.
- **DeepSWE v1.1:** Parsed from server-rendered HTML tables.  Each cell
  evaluates across lines: `model`, `[`, `effort`, `]`, `pct`, `%`.  The
  "Best" table precedes all-efforts listings, and the first match is
  selected.
- **EQ-Bench 4:** Extracted from JavaScript data payloads by stripping the
  `const EQBENCH4_DATA = ` declaration and trailing semicolons to parse
  ELO rankings.
- **Design Arena:** Queried via `POST /api/leaderboard` with payload
  `{"arenaType":"models","category":"website"}` (HTTP GET returns status
  405).  Score changes under 10 points are ignored to prevent ELO churn.

---

## 5. Multi-Host Dotfile Synchronization

The registry file is designed for seamless synchronization across multiple
hosts.  Each host updates only its own `hosts.<hostname>` block and
populates global `models` fields retrieved during refresh.  Sorted keys
and fixed indentation minimize version control diffs.

A host without external network egress refreshes local rosters and CLI
probes while utilizing synced benchmark indices.  Use the environment
variable `MODEL_ROUTER_HOST` to override the hostname and
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
