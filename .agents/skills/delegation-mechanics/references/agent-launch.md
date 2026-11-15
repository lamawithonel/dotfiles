# agent-launch

Use `agent-launch` to start an executive, a coordinator, or a
consultant.  It lives in `~/.local/bin/`.  Workers do not use it.

Start other harness sessions only through `agent-launch`.  Reason: it
adds the class file to the system prompt, names the tab and session,
and starts the harness in a visible pane.

## Syntax

```text
agent-launch <class> <domain> [--harness claude|pi] [--mux auto|herdr|tmux]
             [--model M] [--effort E] [--creator CLASS:BAND:EFFORT]
             [--first-prompt FILE] [--resume ID] -- <harness args>
agent-launch completions zsh
```

- `<class>`: `executive`, `coordinator`, or `consultant`.
- `<domain>`: the domain of the position.  A consultant takes its
  creator's domain.
- Everything after the trailing `--` goes to the harness CLI.
- `--model` and `--effort` default to `~/.agents/skills/model-selection/scripts/score.py --pick --role <class>`.
- `--creator` names the creator's class, band, and effort.  A
  consultant runs one band and one effort level above it.  The band
  stops at opus.  Effort may reach `max`.
- `--first-prompt FILE` is the first prompt.  A coordinator gets its
  charter there.  A consultant gets its consultation there.
- `--resume ID` resumes a session.  Use it to relaunch a coordinator
  after a class-file update.
- `agent-launch completions zsh` prints zsh completion code.

## What it does

1. Probe the level (`degradation.md`).  Use the highest level that
   works.  Print the level.
2. Append the class file to the system prompt.  Append the domain
   amendment file too, if one exists.
3. Give a consultant read-only tools.
4. Name the tab and session (`layout.md`).
5. Start the harness CLI in a visible interactive pane or window.  It
   never starts a harness headless (`-p`) or as a child of the
   caller's shell.

## How each class gets its rules

| Class | Claude Code | Pi |
| --- | --- | --- |
| Executive | `--append-system-prompt-file`; `/executive` for a running session | `--append-system-prompt`; `/skill:executive` |
| Coordinator | Herdr tab, appended class file, charter as first prompt | same, with Pi flags |
| Consultant | Herdr tab, appended class file, read-only tools, consultation as first prompt | same, with `--tools read,grep,find,ls` |
| Worker | PACT worker brief | PACT worker brief |

- After any MCP config change (`~/.pi/agent/mcp-adapter.json` or the
  imported `~/.claude.json` servers), run
  `env -C "$(mktemp -d)" pi --no-session -p 'Reply OK.'` once before you
  launch a Pi consultant.  Reason: the first start rebuilds Pi's MCP tool
  cache, and until then a consultant has none of its MCP tools.
- An appended system prompt survives compaction in Claude Code.  Pi
  rebuilds its system prompt after compaction.
- `/executive` loads a skill.  Re-attached skills are capped at 5,000
  tokens each and 25,000 in all, oldest dropped first.  Treat
  `/executive` as a bridge until the next launch through
  `agent-launch`.

## Examples

```sh
# A coordinator with its charter as first prompt.
agent-launch coordinator jiv-train --first-prompt "$CHARTER_FILE"

# A consultant one band above its creator.
agent-launch consultant jiv --creator coordinator:sonnet:high \
  --first-prompt "$CONSULT_FILE"
```

- Put harness-only flags after `--`.
- A user-made consultant (`/consultant`) defaults to the mythos band at
  `xhigh`.  An agent creates a consultant only as the `roles` skill
  allows.
