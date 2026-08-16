# Global Instructions

- Read @~/.claude/CLAUDE.local.md first if it is available.
- Read @~/.agents/AGENTS.md second.

## Code Repository Comprehension

When the user points you at a code repository or directory:

- Read `AGENTS.md` and `AGENTS.local.md` at the repo root first.
- If neither `AGENTS*.md` file exists, fall back to `README.md`.

## Execution Channels (Claude Code)

Claude Code is the primary coordinator for long-horizon work.  Load
the `delegate` skill before any `Agent`, `Workflow`, `Task`, or
background dispatch, and before shelling out to another agent CLI: it
owns channel choice, the worker's brief, and the pause/halt order.
Reach `model-router` from there to pick the model.

Two rules bind even when no skill loads:

- Never delegate to a model whose registry `constraints.tier_4_only`
  is true unless the user explicitly orders it (a Tier 4 directive).
- While `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, passing `name` to
  `Agent` launches a teammate, and a teammate reports idle without
  returning its output.  Name an agent only when the result is allowed
  not to come back.
