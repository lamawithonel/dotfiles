# Native channel

The harness dispatches to its own models through its own tools: no
CLI, no payload file, no stdout parsing.

| Harness | Native models | Dispatch |
| --- | --- | --- |
| Claude Code | Anthropic Claude | `Agent`, `Workflow` |
| Pi | OpenRouter and `llama-cpp` | Pi sub-agents (`pi-subagents` extension) |

Take the dispatch parameters verbatim from the chosen model's
`execution.<harness>` block in `~/.agents/models.json`.  For Claude
Code that block is shaped:

```json
{ "channel": "native", "tool": "Agent", "model_param": "opus" }
```

Pass `model_param` as the `Agent` tool's `model`.  Never type a model
id from memory; `model-router` reads the registry and returns the
parameter.

## Agent

One worker, one context window, a result that returns to the caller.

- `subagent_type` selects a preset.  `general-purpose` is the
  catch-all; `Explore` is the read-only fan-out searcher; `Plan`
  designs without editing.  Caveman-compressed presets live in the
  `cavecrew` skill.
- `model` and `effort` override the inherited tier per call.  Omit
  both unless the task clearly warrants a different one.
- `isolation: "worktree"` gives the worker its own git worktree.  It
  costs setup time and disk, so use it only when parallel workers
  would otherwise write the same files.
- `run_in_background` detaches the worker so it outlives the turn.
- `name` is the trap.  See `channel-teams.md` before passing one.

Continue a worker with `SendMessage` addressed by name or id; a send
resumes it from its transcript.  `ListAgents` enumerates what is
reachable: live subagents, other local sessions, and cloud sessions.

## Workflow

A script that orchestrates many workers deterministically -- loops,
conditionals, fan-out -- instead of leaving control flow to the model.

Reach for it when the work is a known list of items and the shape of
the pass over them matters.  `pipeline()` is the default: items flow
through stages independently, with no barrier between them.  Use
`parallel()` only when a stage genuinely needs every prior result at
once, such as a dedup across the whole set.

`resumeFromRunId` is the run cache: on relaunch, the longest unchanged
prefix of `agent()` calls returns cached results instantly and only
the first changed call onward re-runs.  This is the mechanism behind
"interrupted workflows resume later" in `lifecycle.md`.

Workflows spawn many workers and spend accordingly, so they run on
explicit opt-in only.

## Task list

`TaskCreate`, `TaskUpdate`, `TaskList`, `TaskGet`, `TaskOutput`, and
`TaskStop` manage shared work items that workers can read and write.

`TaskStop` is the concrete verb behind "pause the running
delegations" in `lifecycle.md`.

The task list is local, is never uploaded, and survives a resumed
session.  Its retention follows `cleanupPeriodDays`, the same setting
that governs session transcripts.

## Host-side work

`Bash(run_in_background)` and `Monitor` drive work that outlives the
turn and, for detached processes, the session: builds, renders, test
suites, container jobs.  These are the "detached background jobs" the
halt order in `lifecycle.md` deliberately leaves running.

Heavy host-side work delegated this way still obeys the host's
resource-control rules -- memory caps bind the worker's builds exactly
as they bind the coordinator's.  Those caps are host-local; read them
from the host's own instructions, not from here.
