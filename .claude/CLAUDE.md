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

The delegation rules in `~/.agents/AGENTS.md` apply in full.  The
`model-router` skill MUST be loaded before invoking `Agent`, `Workflow`,
or shell-outs.  Claude Code specifics:

- Every `Agent` and `Workflow` agent call names `model` and `effort`.
  Set `model` to the `model_param` that `score.py --pick` returns, or to
  the model the user named.  Never omit it: an omitted model inherits
  the session's model.
- Never dispatch a `mythos`-band model unless the user names it.  Never
  let a workflow default its agents to one.
- When `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is enabled, passing `name`
  to `Agent` spawns a teammate whose output does not return to the caller.
  Omit `name` whenever the caller requires the tool result.
- `Agent` and `Workflow` support Anthropic models only.  When `score.py
  --pick` selects a non-Anthropic model (such as Gemini, GPT, DeepSeek,
  or Qwen), executing the returned `command` via `Bash` (shelling out to
  `pi`) is explicitly authorized.  Never use `Bash` to execute `claude`.
