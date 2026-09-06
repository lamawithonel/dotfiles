# Scoring: Registry Layout, Policy, and Degradation

This reference defines the mathematical scoring policy and selection
rules executed by `scripts/score.py --pick`.  All routing decisions must
read `~/.agents/model-benchmarks.json`; do not select models from memory.

---

## 1. Registry Architecture

The registry file `~/.agents/model-benchmarks.json` conforms to JSON Schema
Draft 2020-12 via `schema/model-benchmarks.schema.json`.

| Section | Managed By | Scope and Purpose |
| --- | --- | --- |
| `models` | Automated script | Benchmark indices, pricing, context window, and `last_seen` timestamps |
| `hosts.<h>` | Automated script | Host-local capabilities: enabled status, channel mappings, and CLI execution commands |
| `sources` | Automated script | Status (`ok`, `failed`, `skipped`), retrieval timestamp, and error logs per feed |
| `overrides` | User / Administrator | Manual overrides: `tier_4_only`, `track_only`, feed match patches, and custom constraints |

### Invariant Checks

1. **Schema compliance:** `score.py` validates the registry against
   `schema/model-benchmarks.schema.json`.
2. **Host registration:** The registry must contain an entry for the
   current short hostname under `hosts`.
3. **Data currency:** If a feed status is not `ok` or the `as_of` date is
   older than 14 days, `score.py` emits a warning but proceeds with
   routing.
4. **Benchmark age-out:** Benchmark values not refreshed within 90 days
   are treated as `null`.
5. **Channel eligibility:** If a channel is disabled in `hosts.<h>.channels`,
   models native to that channel cannot be selected automatically.

---

## 2. Classification Systems and Weight Profiles

### Task Classification

- **`general` system:** Default system for software development, technical
  reasoning, analysis, and documentation.
- **`design` system:** Specialized ladder for visual layout, styling,
  user interface (UI) and user experience (UX) aesthetics, and front-end
  design.

### General Benchmark Profiles

Select exactly one profile to determine the scoring weights:

| Profile | Target Tasks | Benchmark Weights |
| --- | --- | --- |
| `coding` | Defect fixes, refactoring, feature implementation, unit testing | `aa_coding` (0.35), `deep_swe` (0.25), `terminal_bench` (0.15), `aa_omniscience` (0.15), `aa_factuality` (0.10) |
| `reasoning` | Architecture, root-cause analysis, planning, mathematical logic | `aa_intelligence` (0.50), `aa_omniscience` (0.20), `aa_factuality` (0.15), `deep_swe` (0.15) |
| `style` | Technical writing, documentation, code naming, formatting | `design_arena` (0.45), `eq_bench` (0.25), `aa_factuality` (0.15), `aa_intelligence` (0.15) |

### Benchmark Fields and Metric Scales

All benchmark values evaluate such that higher numbers represent superior
performance:

| Metric Field | Source Feed | Units and Scaling |
| --- | --- | --- |
| `aa_intelligence` | `aa_api` | Index points |
| `aa_coding` | `aa_api` | Index points |
| `terminal_bench` | `aa_api` | Percentage (`terminalbench_v2_1 * 100`) |
| `aa_omniscience` | `aa_omniscience` | Index points |
| `aa_factuality` | `aa_omniscience` | Normalized scale 0.0 to 1.0 (`1 - hallucinationRate`) |
| `deep_swe` | `deep_swe` | Percentage |
| `eq_bench` | `eq_bench` | ELO rating |
| `design_arena` | `design_arena` | ELO rating |

---

## 3. Mathematical Scoring Model

The scoring engine calculates composite quality and cost metrics across
eligible candidates:

1. **Comparability verification:** If a model's benchmark version
   differs from the feed's `primary_version`, that benchmark is treated as
   `null`.
2. **Min-max normalization:** For each benchmark $b$ across candidates
   with valid scores:
   $$\text{norm}(m, b) = \frac{\text{value}(m, b) - \min(b)}{\max(b) - \min(b)}$$
3. **Quality composite ($Q$):** Computed as the weighted mean of non-null
   normalized scores:
   $$Q(m) = \frac{\sum w_b \cdot \text{norm}(m, b)}{\sum w_b}$$
4. **Blended cost ($C$):** Models a 3:1 input-to-output token ratio
   (expressed in USD per million tokens):
   $$C(m) = 0.75 \cdot \text{prompt\_cost} + 0.25 \cdot \text{completion\_cost}$$
5. **Value index ($V$):** Used for Tier 2 optimization:
   $$V(m) = \frac{Q(m)}{C(m) + 0.05}$$

---

## 4. Tier Selection Logic

### General System

- **Tier 1 (High-Volume / Low-Context):** Eligible if $Q \ge 0.40$.  Select
  the candidate with minimum cost $C$.  Ties resolve in favor of higher
  $Q$.
- **Tier 2 (Systems Integration):** Eligible if $Q \ge 0.60$.  Select the
  candidate with maximum value index $V$.
- **Tier 3 (High Abstraction):** Select the candidate with maximum
  quality $Q$.  Candidates within 0.02 of the top $Q$ favor lower cost
  $C$; candidates within 0.05 favor a higher count of non-null benchmarks.
- **Tier 4 (Frontier):** Select the candidate with maximum quality $Q$
  with `tier_4_only` models enabled.  Cost is not evaluated.

### Design System (Pareto Frontier)

The design system evaluates candidates with valid `design_arena` ELO scores
and blended cost $C$:

- Candidates are plotted along the Pareto frontier (minimizing cost,
  maximizing ELO) in ascending cost order.
- The frontier sequence is mapped across four rungs:
  - **Rung 1:** Most economical model on the Pareto frontier.
  - **Rungs 2 and 3:** Intermediate models balancing cost and visual
    performance.
  - **Rung 4:** Highest-performing model on the Pareto frontier.

---

## 5. Hard Constraints

- **`tier_4_only` constraint:** Models flagged with `tier_4_only` in
  `overrides` are excluded from Tiers 1 through 3 and the design ladder.
  They are eligible only at Tier 4 or via explicit user directive.
- **`track_only` constraint:** Models benchmarked for research comparison
  only; excluded from automatic dispatch.
- **Context window limits:** Models whose context window is smaller than
  the estimated task context are disqualified.

---

## 6. Maintenance Procedures

- **Model ingestion:** New models in Pi appear automatically on the next
  refresh.  To add a new Claude model, configure
  `overrides.<anthropic/id>.probe: true` or populate the CLI picker cache.
- **Feed match patching:** If a model is active but does not link to feed
  data, add an entry to `overrides.<id>.match.<feed>`.
- **Validation test suite:** Run unit tests after modifying scoring logic:
  `python3 -m unittest discover -s ~/.agents/skills/model-router/scripts/tests`
- **Schema versioning:** When changing registry layout, increment
  `schema_version` concurrently in `schema/model-benchmarks.schema.json`,
  `scripts/refresh-benchmarks.py`, and this document.
