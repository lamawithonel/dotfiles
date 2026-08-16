---
name: delegate
description: >-
  Delegate work to another agent: whether to hand it off at all, which
  channel carries it, what brief the worker gets, and what it owes
  back.  Use before any Agent, Workflow, Task, or background dispatch,
  before shelling out to another agent CLI, when a task is big enough
  to split across workers, and when running delegations must be
  paused, resumed, or halted.  Reach for `model-router` from here to
  pick the model.
---

# Delegate

Delegation buys context isolation and parallelism.  It costs a fresh
context window, a round trip, and everything the worker cannot see
from inside it.  Decide the **channel** first; the brief, the
receipt, and the lifecycle all follow from that one branch.

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
| subagent | `Agent` | fan-out search, a bounded edit, a review -- and the result matters | yes: tool result or task notification |
| workflow | `Workflow` | deterministic fan-out over a known work list, or a run that must survive a pause | yes: the script's return value |
| teammate | `Agent` with `name`, teams enabled | workers must message each other and share a task list | **no: an idle notification, without the output** |
| external | `Bash` running another agent's CLI | a non-Claude model, or the other harness | yes: on stdout |
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
| Which model should this worker run? | the `model-router` skill |
| I want caveman-compressed worker output | the `cavecrew` skill |

Read one.  A single-channel task needs exactly one of these.
