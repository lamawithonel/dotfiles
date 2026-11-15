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

The delegation guardrails in `~/.agents/AGENTS.md` apply in full.
Claude Code specifics:

- Name `model` and `effort` in every `Agent` call and in every
  `agent()` call of a `Workflow`.  Take `model` from the `model_param`
  that `model-selection` returns, or use the model the user named.
  Reason: an omitted model inherits the session's model.
- Run a `mythos`-band model only when the user names it.  Set each
  workflow agent's model yourself, from `model-selection`.
- Omit `name` on an `Agent` call when the caller needs the tool result.
  Reason: with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, `name` spawns
  a teammate whose output does not return to the caller.
- Use `Agent` and `Workflow` for Anthropic models only.  For a
  non-Anthropic model (such as Gemini, GPT, DeepSeek, or Qwen), run the
  `command` that `model-selection` returns through `Bash` (a shell-out
  to `pi`).  The user explicitly authorizes this.  Never use `Bash` to
  execute `claude`.
- **Standing Workflow opt-in:** I opt in, for all coordinators, to
  multi-agent orchestration with the `Workflow` tool: a coordinator
  may run `Workflow` for short-lived Claude workers without asking me
  first.  Use `Agent` for long-lived Claude workers you will message
  again.  The session's workflow size guideline still applies.
