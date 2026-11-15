# Degradation Ladder

Use the highest level that works.  Probe before each start (the probe
is in `SKILL.md`).  `agent-launch` probes for you and prints the level.

| Level | Needs | Result |
| --- | --- | --- |
| 1 Herdr | `HERDR_ENV=1` and a read-only Herdr call succeeds | the full design |
| 2 tmux | `TMUX` set and `tmux list-windows` works | one tmux window per session |
| 3 no multiplexer | nothing | two levels of agents, all in-process |

## Level 1: Herdr

- Run executives, coordinators, and consultants in Herdr tabs
  (`layout.md`).
- Ask consultants with `herdr agent prompt` (`consultant-questions.md`).

## Level 2: tmux

- Run each session in its own tmux window (`layout.md`).
- Ask consultants with `tmux send-keys` and `tmux capture-pane`
  (`consultant-questions.md`).
- Read a worker or a session with `tmux capture-pane -p -t <target>`.
- Never use zellij.

## Level 3: no multiplexer

- The executive works as its own coordinator.  It dispatches in-process
  workers with the channels in `channels.md`.  There is no coordinator
  tier.
- A consultant becomes an in-process background agent with read-only
  tools.
  - Claude Code: start it with `Agent` and `run_in_background: true`.
    Keep the agent ID.  Ask it with `SendMessage` to that ID.
  - Pi: start it as a `pi-subagents` child.  Ask it with
    `subagent_supervisor`.
- A worker that has a question asks its dispatcher.  The dispatcher
  asks the consultant for it.
- Workers on another harness run as shell-outs (`channels.md`, rule 3).

## When the level drops

- Report the drop to your supervisor in one short message: the level
  you left, the level you use now, the reason, and what changes.  An
  executive reports to the user.
- If Herdr fails during a run:
  - Running sessions continue.
  - New starts through Herdr fail.  Herdr questions fail.
  - A Claude Code asker falls back to `SendMessage`.
  - A Pi asker asks through its coordinator.
  - Restart missing sessions through `agent-launch` at the new level
    when work needs them.
- Return to a higher level only when its probe passes, and report that
  too.
