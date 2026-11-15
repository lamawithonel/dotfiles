# Global Instructions

Pi loads this file on every run but does not follow imports, so read
these files yourself, with your read tool, before doing anything else:

- Read `~/.pi/agent/AGENTS.local.md` first if it is available.
- Read `~/.agents/AGENTS.md` second.  Also read each file that it
  names with an `@` prefix.

## Execution Channels (Pi)

The delegation guardrails in `~/.agents/AGENTS.md` apply in full.  Pi
specifics:

- Pi has no skill-load tool.  To load a skill, read its `SKILL.md` at
  the path in your skill catalog.  The `roles`, `delegation-mechanics`,
  and `model-selection` skills sit in `~/.agents/skills/`.
- Start a worker with `subagent`.  Name its `model` and its thinking
  level on every call.  Take the `model_ref` and `effort` from
  `model-selection`, or use the model the user named.
- Run a `mythos`-band model only when the user names it.
- Never run `pi` through a shell to start a worker.  Use `subagent`.
- Send one message to a Claude Code session with this command:
  ```sh
  claude --model claude-haiku-5-5 --effort low --name <sender-session-name> --allowedTools "SendMessage ListAgents" -p 'Use the SendMessage tool to send this exact text to the session named <target-session-name>, then print only the tool result: "<message>"'
  ```
- A Pi session may use this form to send ONE message to a Claude Code
  session.  Use it only to communicate, never to do work.  The class
  rules on who may message whom still apply.
- Set `--name` to your own session name so the receiver sees who sent it.
- Never add `--safe-mode` or `--bare`.  Reason: the failed test used
  `--safe-mode`.
- The route is one way: a reply goes to the `-p` session and is lost when
  it exits.  For an answer, use the Herdr route
  (`delegation-mechanics/references/consultant-questions.md`) or ask through your supervisor.
- A message that contains a single quote breaks the inline form.  Write
  the text to a file, add `Read` to `--allowedTools`, and tell the `-p`
  session to send the file's exact contents.  Verified form (use the
  same `--model`, `--effort`, and `--name` flags as above):
  ```sh
  claude --model claude-haiku-5-5 --effort low --name <sender-session-name> --allowedTools "Read SendMessage ListAgents" -p "Read the file \"<path>\".  Use the SendMessage tool to send its exact contents, unchanged, to the session named <target-session-name>.  Then print only the tool result."
  ```
- Put the worker rules in the PACT worker brief.  Reason: a Pi child
  does not see `~/.agents/AGENTS.md` unless the brief carries it or
  tells the child to read it.
