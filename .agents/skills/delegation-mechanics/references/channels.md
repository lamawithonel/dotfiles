# Worker Channels

Use this file to start a worker.  A worker holds no position and ends at
its final report.  Pick the model and effort first
(`model-selection` skill, `~/.agents/skills/model-selection/scripts/score.py --pick`).  Every
dispatch names both.

## Channel rules

1. Same harness: use the in-process tool.
   - Claude Code: `Workflow` for short-lived workers.  `Agent` for
     long-lived workers you will message again.
   - Pi: `subagent`.
   - Reason: in-process work is tracked, attributed, and returns
     structured results.
2. Other harness, `HERDR_ENV=1`: run the worker in a pane in a worker
   tab in the dispatcher's workspace.  See `layout.md` and "Worker in a
   Herdr pane" below.
3. Other harness, no Herdr: shell out with the `command` from the
   output of `~/.agents/skills/model-selection/scripts/score.py --pick`.  Copy it as it stands.  It
   ends in `< /dev/null`.  Tell your supervisor in your next report that
   you used an untracked shell-out, and why.
4. Bedrock-only host: use `Agent` only.  Assume no Pi and no Herdr.
5. Pi workers do not edit repositories.  Reason: Pi has no per-call
   approval gate and no confinement yet.  A brief cannot supply them.
   - Use the `fallback` of the pick for edit work when it is set.
   - When `fallback` is null (a `pi-zdr` session), report the work to
     your supervisor.
6. Never run the host's own CLI through Bash.  Call the in-process
   tool.  Never use a shell-out to pass a gate the user declined.
   Reason: a shell-out is an untracked process.  The harness cannot
   list, inspect, or cancel it, and its tokens count against no budget.
7. Give every headless or `Workflow` run a turn or budget cap and a
   stop condition.  Reason: an unattended run has no other end.
8. After two failed fix attempts, the worker writes a handoff note and
   ends.  The dispatcher starts a fresh worker from the note.

## Claude Code tools

- `Agent`: one child in its own context window.
  - Set `model` and `effort` from the pick (`model_param`, `effort`).
  - `subagent_type`: an execution preset or a specialist agent
    definition from `~/.agents/agents/`.
  - `isolation: "worktree"`: only where `vcs-workflow` allows it.
    Reason: parallel workers that write the same files need isolation.
  - `run_in_background`: the worker runs across turns.
- `Workflow`: a JavaScript script over a known list of items.
  - `pipeline()` streams items through stages.  `parallel()` waits for
    all results.
  - `resumeFromRunId` restores unchanged earlier stages from the run
    cache.
  - Name `model` and `effort` in every `agent()` call.
  - Workflow agents return JSON that follows a schema.
- `SendMessage`: resume or steer an existing agent by ID or name.

### Teammate trap

- Omit `name` on an `Agent` call when you need its result.
  - Reason: with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, a call with
    `name` starts a teammate.  Its output does not return to the call.
    You get an idle notification only.
- A teammate sends its findings with `SendMessage` or the shared task
  list.
- A teammate runs in its own session.  It inherits `CLAUDE.md`,
  permissions, and effort from the lead.  Permission prompts show in
  the lead session.

## Pi tools

- `subagent`: one child, a scripted workflow, or parallel lanes.
  - One child: pass `{ agent, task }`.
  - A script: pass `{ workflowScript, async: true }` and use
    `runs.run()`, `runs.all()`, or `runs.lanes()`.
  - Set `model` to the `model_ref` of the pick.  Set the thinking level
    to its `effort`.
  - `isolation: "worktree"` gives an isolated Git worktree.
- `subagent_supervisor`: the backchannel for active children.  Use the
  actions `reply`, `send`, `pending`, and `status`.
- `bg_wait`: wait for detached runs.  Pass `{ id, nonBlocking: true }`
  to get a wake callback.  Pass `{ all: true }` only when this turn
  needs the result.
- A Pi child does not see `~/.agents/AGENTS.md` unless the brief
  carries it or tells the child to read it.  Reason: `pi-subagents`
  passes the global context file to a child only when
  `inheritGlobalContext` is true.  The default is false.

## Worker in a Herdr pane

Use this for a worker on another harness.

1. Find or make a worker tab with fewer than 8 panes
   (`layout.md`).  Read the pane ID from the JSON response.
2. Start the worker.  Pass model and effort as the harness's own flags
   after `--`.  Herdr has no model or effort option.

   ```sh
   herdr agent start <name> --kind pi --pane <pane-id> -- \
     --model <model> --thinking <level> --no-session
   ```

   - `--kind` takes `pi`, `claude`, and other harness names.
     `herdr agent --help` lists them.
   - `agent start` needs a shell pane at its prompt with nothing in the
     foreground.
3. Send the PACT worker brief: `herdr agent prompt <name> "<brief>"`.
   For a long brief, write it to a file and prompt with a line that
   names the path.
4. Name the final report file in the brief.  Wait with
   `herdr agent wait <name> --until idle --until done`.  Read the file.
   Read the pane with `herdr agent read` if the file is missing.
5. Close the pane after you read a good final report:
   `herdr pane close <pane-id>`.  Leave a failed worker's pane open for
   the user.  Close an empty worker tab with `herdr tab close <tab-id>`.

- A blocked agent shows a dialog.  Read the pane first.  Answer with
  `herdr agent send-keys <name> <key>`.  Reason: a prompt typed into a
  dialog answers a question you did not read.
- `< /dev/null` applies to shell-outs (rule 3).  A pane agent has a
  terminal.

## One-way message to a Claude Code session

- Command:
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
  (`references/consultant-questions.md`) or ask through your supervisor.
- A message that contains a single quote breaks the inline form.  Write
  the text to a file, add `Read` to `--allowedTools`, and tell the `-p`
  session to send the file's exact contents.  Verified form (use the
  same `--model`, `--effort`, and `--name` flags as above):

  ```sh
  claude --model claude-haiku-5-5 --effort low --name <sender-session-name> --allowedTools "Read SendMessage ListAgents" -p "Read the file \"<path>\".  Use the SendMessage tool to send its exact contents, unchanged, to the session named <target-session-name>.  Then print only the tool result."
  ```
- A Claude Code session never runs `claude` through a shell.  Use
  `SendMessage`.

## Shell-out hygiene

- Write the brief to a file with an absolute path under your session
  temp directory.  Give that path to `~/.agents/skills/model-selection/scripts/score.py --pick` as
  `--payload PATH`.  The pick command then reads the
  file.  Reason: multi-line text in a command string breaks.
- Add `--no-session` to a `pi` shell-out.
- Check the other CLI exists first: `command -v pi`.
