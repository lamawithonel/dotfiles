---
name: model-router
description: >-
  Delegate work to another agent and pick the model that runs it.
  Covers spawning a subagent or child agent, forking a worker,
  fan-out and orchestrated pipelines, background or headless runs,
  and shell-outs to another agent harness.  Decides whether to hand
  off at all, which channel carries the work, which model scores best
  for the task's tier from the benchmark registry, what brief the
  worker gets, and what receipt it owes back.  Use before any such
  dispatch, whenever the question is "which model", and when running
  delegations must be paused, resumed, or halted.
argument-hint: "[test]"
---

# Model Router

Delegation buys context isolation and parallelism.  It costs a fresh
context window, a round trip, and everything the worker cannot see
from inside it.  Decide the **channel** first, then the **model**;
the brief, the receipt, and the lifecycle all follow from those two
branches.

## Do it inline instead

Do the work yourself when:

- The file, symbol, or value is already known, so the answer is one
  `Read` or one `Grep`.
- The context the worker would need is already in the window.
- The edit is a one-liner in a file already read.
- Briefing the worker costs more than doing the task.

Delegate when the work fans out across many files, buries its answer
under verbose streams, splits into independent pieces, or would
otherwise flood the coordinator with material it never needs again.

## Pick the channel

| Channel | Dispatch | Reach for it when | Result returns |
| --- | --- | --- | --- |
| inline | none | the target is known and bounded | n/a |
| subagent (spawn, fork, child agent) | `Agent` | fan-out search, a bounded edit, a review -- and the result matters | yes: tool result or task notification |
| workflow (orchestrate, pipeline, fan-out) | `Workflow` | deterministic fan-out over a known work list, or a run that must survive a pause | yes: the script's return value |
| teammate | `Agent` with `name`, teams enabled | workers must message each other and share a task list | **no: an idle notification, without the output** |
| external (shell-out, headless run) | `Bash` running another agent's CLI | a non-Claude model, or the other harness; the only row that starts another harness, and the task list cannot see it | yes: on stdout |
| pane | `herdr` skill | another coding agent driven in a terminal pane | yes: via read-back |

Probe before committing to a channel.  Availability is per-host and
never assumed: `command -v pi`, `command -v claude`.  A channel whose
CLI is missing is not a channel, and the work reroutes.

## The name trap

While `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, an `Agent` call that
passes a `name` launches a **teammate**, not a subagent -- and a
teammate's finish is reported as an idle notification that does not
carry its output.  Naming is the whole trigger; nothing else about the
call changes.  Any flow that waits on the result stalls.

So: with teams enabled, pass a `name` only when the result is allowed
not to come back.  When the result matters, omit the name, or ship
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0` and get plain subagent
semantics with names still usable as `SendMessage` addresses.

Details, limits, and the version this was measured against:
`references/channel-teams.md`.

## Pick the model

Never type a model id from memory.  The registry
(`~/.agents/model-benchmarks.json`) scores every model this host can
reach; `scripts/score.py` picks one and returns its dispatch block.
A user who names a model overrides this step; that is a directive,
not a tier.

Classify the task, then run one command:

| Tiering system | When                                                                    |
| -------------- | ----------------------------------------------------------------------- |
| `general`      | everything not below                                                    |
| `design`       | visual design, UI/UX layout, landing pages, anything judged by how it looks |

| Profile (general) | Task shapes                                          |
| ----------------- | ---------------------------------------------------- |
| `coding`          | bug fixes, refactors, multi-file edits, test writing |
| `reasoning`       | architecture, root-cause analysis, planning, math    |
| `style`           | copy, docs, formatting, naming, review prose         |

| Tier | General system                                                   | Design ladder                              |
| ---- | ---------------------------------------------------------------- | ------------------------------------------ |
| 1    | high-volume, low-context, single-file, deterministic transforms  | cheapest model on the Pareto frontier      |
| 2    | multi-file features, bounded refactors, localized API mapping    | second rung                                |
| 3    | zero-to-one design, race conditions, silent systemic failures    | third rung                                 |
| 4    | frontier: correctness above all, cost irrelevant                 | best-looking model on the frontier         |

```sh
python3 ~/.agents/skills/model-router/scripts/score.py --pick --system general --profile coding --tier 2
python3 ~/.agents/skills/model-router/scripts/score.py --pick --system design --tier 3
```

The JSON that comes back carries `id`, `Q`, `C`, and an `execution`
block keyed by harness.  Paste the block for the active harness into
the brief verbatim: `model_param` for the `Agent` tool, `model_ref`
for Pi native, `command` for an external shell-out.  `id: null` means
no model qualifies at that tier; drop one tier and say so.

Hard constraints:

- A model flagged `tier_4_only` in the registry's `overrides` is
  reachable only at Tier 4 or by user directive.
- A `track_only` model is benchmarked for comparison and never
  dispatchable.
- A `context_window` smaller than the task's estimated context
  disqualifies the model; null means unknown and the risk is yours.

If `score.py` refuses (host missing from the registry, schema
failure) or prints source warnings, read `references/scoring.md`; the
scoring math, weights, degradation rules, and registry layout live
there, and feed maintenance lives in `references/pipeline.md`.

## The four invariants

These bind every channel, every worker, every time.

**Swallow.**  The worker eats the verbose streams -- compilers, test
runners, package managers, renderers -- and they die inside its
context.  The coordinator never receives a raw tool-output dump.

**Ceiling.**  A worker gets at most 12 sequential turns to execute a
complex, multi-step assignment.

**Breaker.**  A worker self-terminates and yields control after 3
consecutive turns with zero state progress: the identical terminal
command re-run, a failing edit repeated, or the same error boundary
hit again.

**Boundary escape.**  If the worker discovers during its first
context-gathering turn that the assignment touches more than 3
decoupled subsystems, it halts immediately, emits an execution map,
and hands control back for finer partitioning.

Ceiling, breaker, and boundary escape are the worker's own
obligations, so state them in the brief.  Swallow binds both ends.

## The receipt

What comes back is a **receipt**: conclusions, decisions, and
`file:line` references.  Never a transcript, never a file dump, never
"here is the output of the test run".

State the receipt's shape in the brief before dispatch.  Unstructured
worker output is a briefing bug, not a worker quirk.  When the task
edits code, the brief names one runnable acceptance check the worker
must pass before returning, and the receipt reports its result.

## Where to go next

| Next question | Read |
| --- | --- |
| What exactly do I send the worker? | `references/brief.md` |
| Dispatching through `Agent`, `Workflow`, the task list, or a worktree | `references/channel-native.md` |
| Teammates, mailboxes, team hooks, and their limits | `references/channel-teams.md` |
| Shelling out to `pi` or `claude -p` | `references/channel-external.md` |
| Pausing, resuming, or halting work already running | `references/lifecycle.md` |
| How the model score is computed, weights, degradation | `references/scoring.md` |
| Refreshing benchmarks, adding a model, debugging a feed | `references/pipeline.md` |
| I want caveman-compressed worker output | the `cavecrew` skill |

Read one.  A single-channel task needs exactly one of these.

## `test` -- prove the external channel works

Invoked as `/delegate test`, or whenever an external dispatch fails and
the report is "the CLI doesn't work".  Run:

```sh
scripts/test-external.sh          # every case
scripts/test-external.sh pi       # only cases whose name contains "pi"
```

Output is TAP.  A case exits 0 (pass), 77 (skip, precondition unmet),
or nonzero (fail), and prints its own diagnostic.  Report the failing
case name and its diagnostic; do not re-derive the cause by hand.

Cases live in `scripts/tests/`, run in filename order.  **Add one by
dropping an executable file in that directory** -- there is no registry
to update and no runner to edit.

The highest-yield case is `20-pi-credentials`.  An external CLI's
credential can be denied by the host sandbox policy, and a sandbox that
fails open leaves the same command working in one context and failing
in another.  When a peer session reports a CLI broken and it works
here, compare contexts before comparing commands.

Environment: `DELEGATE_TEST_TIMEOUT` (seconds, default 90),
`DELEGATE_TEST_PI_MODEL`, `DELEGATE_TEST_LLAMA_URL`.
