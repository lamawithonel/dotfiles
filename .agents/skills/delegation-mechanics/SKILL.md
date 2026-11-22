---
name: delegation-mechanics
description: >-
  Start agents and talk to them: channels per harness, Herdr and tmux
  layout, `agent-launch`, the degradation ladder, consultant questions,
  and PACT use.  Use before any Agent, Workflow, subagent, Herdr pane,
  tmux window, or `agent-launch` start; before a question to a
  consultant; before a PACT charter, brief, freeze, ruling, or
  escalation; and before a final or milestone report.
license: Apache-2.0
compatibility: >-
  Claude Code and Pi.  Herdr (`HERDR_ENV=1`) is the first choice.  tmux
  is the fallback.  Works with no multiplexer at a lower level.
metadata:
  owner: agents-config-executive
  design: delegation-revamp
  status: staged
allowed-tools: Bash(herdr agent list:*) Bash(herdr agent read:*) Bash(herdr pane read:*) Bash(herdr tab list:*) Bash(herdr pane list:*) Bash(tmux list-windows:*) Bash(tmux capture-pane:*)
---

# Delegation Mechanics

This skill tells you how to start each kind of agent and how to reach
it.  It does not tell you when to delegate.  The `roles` skill
(`~/.agents/skills/roles/`) holds the class duties.  The
`model-selection` skill holds `score.py` (`~/.agents/skills/model-selection/scripts/score.py`).

## Always

- Name `model` and `effort` on every dispatch.  Take both from the
  output of `~/.agents/skills/model-selection/scripts/score.py --pick`, or from the model the user
  named.
- Start executives, coordinators, and consultants only through
  `agent-launch`.  Start other harness sessions only through
  `agent-launch`,
  except a `claude -p` that sends one message (see
  `references/channels.md`, "One-way message to a Claude Code session").
- Start workers with the channel in `references/channels.md`.  Workers
  are not started by `agent-launch`.
- Use the in-process tool for a worker on the host's own harness.
  Never run the host's own CLI through Bash.
- Send agent-to-agent instructions as PACT.  Write final reports and
  milestone reports as plain text with fixed fields.
- Probe your level before you start an agent (below).  Use the highest
  level that works.
- Report a drop in level to your supervisor.

## Level probe

```sh
test "${HERDR_ENV:-}" = 1 && herdr agent list >/dev/null   # level 1
test -n "${TMUX:-}" && tmux list-windows >/dev/null        # level 2
```

- Exit 0 on the first line: use Herdr.
- Exit 0 on the second line: use tmux.
- Both fail: work at level 3.  Read `references/degradation.md`.

## Pointers

| Need | Read |
| --- | --- |
| Start a worker: Agent, Workflow, `subagent`, other harness | `references/channels.md` |
| Start an executive, coordinator, or consultant | `references/agent-launch.md` |
| Place and name tabs, panes, and windows | `references/layout.md` |
| Work without Herdr or without a multiplexer | `references/degradation.md` |
| Ask a consultant a question | `references/consultant-questions.md` |
| Write or read a charter, brief, freeze, ruling, or report | `references/pact-use.md` |
