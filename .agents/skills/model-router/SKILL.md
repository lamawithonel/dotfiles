---
name: model-router
description: >-
  Delegate work to another agent and select the optimal model.
  Covers spawning subagents, forking workers, orchestrating
  workflows, and executing external CLI fallbacks.  Evaluates
  in-process tools versus inline execution, queries benchmark
  indices from the host registry, formats distilled briefs, and
  governs task lifecycles.
argument-hint: "[test]"
---

# Model Router

Delegation provides context isolation and parallel execution at the cost
of an additional context window and round-trip latency.  First, select
between **inline execution** and **delegation**.  Second, select the
appropriate **execution channel**.  Third, select the **model** via
benchmark scoring.

---

## 1. Inline Execution vs. Delegation

Complete the work directly in the current session when:

- The target file, symbol, or value is known and requires minimal tool
  invocations (`read` or `grep`).
- The relevant context already resides in the conversation window.
- The modification is a localized, single-file edit in an examined file.
- The token overhead of preparing a brief exceeds the cost of executing
  the task directly.

Delegate to a child worker when:

- Work fans out across multiple directories or decoupled subsystems.
- Compiler, test suite, or package manager outputs would flood the
  session context with verbose text.
- Independent tasks can execute concurrently in parallel lanes.

---

## 2. Channel Selection

Always prioritize in-process harness tools over command-line interface
(CLI) shell-outs.

| Capability | Claude Code Tool | Pi Tool | Accountability |
| --- | --- | --- | --- |
| Single child delegation | `Agent` | `subagent` | In-process, tracked, bounded |
| Multi-step orchestration | `Workflow` | `subagent` (`workflowScript`, `lanes`) | In-process, deterministic, scripted |
| Supervise active child | `SendMessage` | `subagent_supervisor` | In-process backchannel |
| Await detached work | Native task notification | `bg_wait` | Passive completion coordination |
| Terminal workspace pane | `herdr` skill | `herdr` skill | Interactive terminal pane, read-back result |
| External CLI fallback | `Bash` (`pi -p ...`) | `bash` (`claude -p ...`) | Out-of-band, untracked process |

### Hard Directives

- **Never invoke the host agent's own CLI binary via `Bash`.**  Do not
  execute `claude` from Claude Code, or `pi` from Pi.  Use in-process
  tools exclusively.
- **Treat CLI shell-outs as untracked processes, not child agents.**
  External shell-outs do not register in the task list and do not track
  token usage.  If an external shell-out is strictly necessary, disclose
  the execution and rationale in your response.

For complete channel mechanics, see `references/channels.md`.

---

## 3. Model Selection

Do not select model identifiers from memory.  Query the host registry
(`~/.agents/model-benchmarks.json`) using `scripts/score.py --pick`.  An
explicit user directive naming a model overrides automatic scoring.

Classify the assignment by system, profile, and tier:

| System | Application Domain |
| --- | --- |
| `general` | Software engineering, systems analysis, reasoning, and technical copy |
| `design` | Visual styling, layout aesthetics, UI/UX components, and landing pages |

| Profile (`general` system) | Target Task Shapes |
| --- | --- |
| `coding` | Defect fixes, refactoring, feature implementation, and unit testing |
| `reasoning` | Architectural design, root-cause analysis, planning, and math |
| `style` | Technical writing, documentation, code conventions, and naming |

| Tier | `general` System Criteria | `design` System (Pareto Frontier) |
| --- | --- | --- |
| 1 | High-volume, single-file transforms, low context | Rung 1: Most economical model on the Pareto frontier |
| 2 | Multi-file features, bounded refactoring, API integration | Rung 2: Balanced cost and visual performance |
| 3 | Sub-system architecture, race conditions, complex debugging | Rung 3: Advanced visual styling and layout fidelity |
| 4 | Frontier models: maximum correctness, full-system architecture, cost unconstrained | Rung 4: Highest-performing model on the Pareto frontier |

### Query Command

```sh
# General software engineering task
python3 ~/.agents/skills/model-router/scripts/score.py --pick --system general --profile coding --tier 2

# Visual design task
python3 ~/.agents/skills/model-router/scripts/score.py --pick --system design --tier 3
```

Extract the `execution` block returned in the JSON payload and paste its
properties verbatim into the worker brief:

- Claude Code in-process: Supply `model_param` as the `model` argument.
- Pi in-process: Supply `model_ref` as the `model` argument.
- External CLI fallback: Execute `command` verbatim using a payload file.

For scoring formulas, normalization, and weights, see
`references/scoring.md`.  For feed updates, see `references/pipeline.md`.

---

## 4. Binding Invariants

The following constraints are binding on every delegation:

<constraints priority="BINDING">
1. TURN CEILING: The coordinator MUST abort worker execution if cumulative turns reach 12.
2. CIRCUIT BREAKER: The worker MUST terminate if 3 consecutive turns yield zero state progress.
3. BOUNDARY ESCAPE: The worker MUST halt and return an execution map if changes span >3 decoupled subsystems.
4. RECEIPT CONTRACT: The worker MUST suppress verbose streams and return only actionable conclusions with file:line references.
</constraints>

State these invariants in the worker brief.  For XML templates and brief
contracts, see `references/brief.md`.

---

## 5. Reference Directory

| Operational Need | Document Reference |
| --- | --- |
| In-process tools, team traps, and external CLI fallbacks | `references/channels.md` |
| Brief formatting, XML schemas, and receipt structure | `references/brief.md` |
| Execution lifecycle: pause, halt, run cache, and handoffs | `references/lifecycle.md` |
| Mathematical scoring formulas, weights, and constraints | `references/scoring.md` |
| Ingesting benchmark feeds and registry maintenance | `references/pipeline.md` |

---

## 6. Verification Test Suite

Verify local CLI availability and credential integrity:

```sh
scripts/test-external.sh          # Execute all test cases
scripts/test-external.sh pi       # Execute test cases filtering for "pi"
```

Output adheres to the Test Anything Protocol (TAP).  Test scripts exit
with code `0` for success, code `77` when preconditions are unmet (skip),
or non-zero on failure.

- Test cases reside in `scripts/tests/` and execute in alphabetical order.
  Add a new case by creating an executable file in that directory.
- `20-pi-credentials.sh` is the highest-yield diagnostic: sandbox policies
  can deny external credentials while standard shell execution succeeds.
  Compare sandbox policies before troubleshooting commands.
- Configuration variables: `DELEGATE_TEST_TIMEOUT` (seconds, default 90),
  `DELEGATE_TEST_PI_MODEL`, and `DELEGATE_TEST_LLAMA_URL`.
