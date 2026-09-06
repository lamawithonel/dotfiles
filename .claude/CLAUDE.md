# Global Instructions

- Read @~/.claude/CLAUDE.local.md first if it is available.
- Read @~/.agents/AGENTS.md second.

## Code Repository Comprehension

When the user points you at a code repository or directory:

- Read `AGENTS.md` and `AGENTS.local.md` at the repo root first.
- If neither `AGENTS*.md` file exists, fall back to `README.md`.

## File Edits

- Never rewrite an entire file unless its entire contents are changing.
- Use the `Edit` tool to make small, precise changes.
- Prefer the `Edit` tool over the `Write` tool in all cases, except when
  creating an entirely new file.

## Execution Channels (Claude Code)

Claude Code coordinates long-horizon work.  The delegation rules in
`~/.agents/AGENTS.md` apply in full.  The following requirements apply
specifically to Claude Code:

- `Agent` performs delegation, `Workflow` performs orchestration, and a
  `Bash` shell-out to `pi` or `claude -p` executes an external harness that
  the task list cannot track.  Load the `model-router` skill before you use
  any of these three channels.  Do not make exceptions for small tasks;
  the skill determines whether to complete the work inline or delegate.
- Set `Agent.model` to the `model_param` value supplied by `score.py
  --pick`.  Do not supply a model identifier from memory, and do not use
  the tool default when the task tier is known.
- Dispatch a model flagged with `tier_4_only` in the registry `overrides`
  only at Tier 4 or when the user explicitly requests it.  Do not permit a
  workflow to default every agent to a `tier_4_only` model; abort the
  workflow if this occurs.
- When `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is enabled, passing `name`
  to `Agent` launches a teammate whose output does not return to the
  calling session.  Pass `name` only if the caller does not require the
  result.
- Prefer `Agent` or `Workflow` over a `Bash` shell-out when a native model
  is sufficient.  The native channels provide user tracking, attribution,
  and cancellation controls; shell-outs do not provide these capabilities.
