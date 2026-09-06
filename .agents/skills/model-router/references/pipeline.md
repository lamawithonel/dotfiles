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
   benchmark numbers and records an error status.
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

---

## 3. Feed Troubleshooting

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
