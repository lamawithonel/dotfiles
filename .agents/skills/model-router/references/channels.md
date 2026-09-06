# Execution Channels: In-Process Tools and External Fallbacks

Delegation routes through either in-process harness tools or an external
command-line interface (CLI) fallback.  Always prefer in-process tools;
they maintain tracking, user attribution, and structured return values.

## Summary Matrix

| Capability | Claude Code Tool | Pi Tool | Accountability |
| --- | --- | --- | --- |
| Single child delegation | `Agent` | `subagent` | In-process, tracked, bounded |
| Multi-step orchestration | `Workflow` | `subagent` (`workflowScript`, `lanes`) | In-process, deterministic, scripted |
| Supervise active child | `SendMessage` | `subagent_supervisor` | In-process backchannel |
| Await detached work | Native task notification | `bg_wait` | Passive completion coordination |
| External CLI fallback | `Bash` (`pi -p ...`) | `bash` (`claude -p ...`) | Out-of-band, untracked process |

---

## 1. Native In-Process Delegation (Canonical)

In-process tools execute within the active harness session.  They return
structured receipts, respect host permissions, and integrate with the
task list.

### Claude Code (`Agent`, `Workflow`)

- `Agent`: Dispatches a single child worker in an isolated context
  window.
  - `model`: Set to the `model_param` string returned by `score.py
    --pick` (e.g. `"opus"`, `"sonnet"`).
  - `subagent_type`: Selects an execution preset (`general-purpose`,
    `Explore`, `Plan`).
  - `isolation: "worktree"`: Allocates a dedicated Git worktree.  Use
    this option only when parallel workers would write to the same files.
  - `run_in_background`: Detaches the worker so it executes across turns.
- `Workflow`: Executes a deterministic JavaScript orchestration script
  over a known list of items.
  - `pipeline()`: Streams items through stages independently.
  - `parallel()`: Waits for all stage results before proceeding.
  - `resumeFromRunId`: Restores unchanged prior stages from the run
    cache and executes only from the first modified call onward.
- `SendMessage`: Resumes or guides an existing agent by ID or name using
  its previous transcript.

### Pi Coding Agent (`subagent`, `subagent_supervisor`, `bg_wait`)

- `subagent`: Launches child agents, scripted workflows, and parallel
  lanes.
  - Single-child task: Pass `{ agent, task }`.
  - Inline orchestration: Pass `{ workflowScript, async: true }` using
    `runs.run()`, `runs.all()`, or `runs.lanes()`.
  - Isolation: Set `isolation: "worktree"` to assign an isolated Git
    worktree.
  - Model override: Set `model` to the OpenRouter or local reference
    returned by `score.py --pick` (e.g.
    `"openrouter/google/gemini-3.8-flash"`).
- `subagent_supervisor`: Serves as the inbound and outbound backchannel
  for active children.  Use actions `reply`, `send`, `pending`, and
  `status` to answer child inquiries without interrupting the parent turn.
- `bg_wait`: Observes detached or headless runs that lack native
  completion notifications.
  - Set `{ id, nonBlocking: true }` to register a wake callback.
  - Set `{ all: true }` only when a blocking result is strictly required
    in the current turn.

---

## 2. Team Coordination and the Teammate Trap

In Claude Code, setting `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` enables
agent teams.  Under this mode, calling `Agent` with a `name` parameter
spawns a **teammate** rather than an ordinary subagent.

### The Name Trap

- When agent teams are enabled, an `Agent` call with a `name` argument
  does not return its output to the calling tool call.  The harness
  delivers only an idle notification upon completion.
- To receive results directly, omit the `name` parameter, or set
  `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0`.
- When using teammates, the worker must explicitly send its findings back
  to the lead session using `SendMessage` or update the shared task list.

### Teammate Properties

- Teammates run in separate sessions with independent context windows.
- Teammates inherit the project instructions (`CLAUDE.md`), permissions,
  and effort levels of the lead session.
- Teammates communicate via mailboxes written to
  `~/.claude/teams/{team-name}/inboxes/{agent-name}.json`.
- Teammates cannot approve permissions for each other; permission prompts
  always surface in the lead session.

---

## 3. External CLI Fallback (Degraded and Out-of-Band)

A CLI shell-out invokes a foreign agent runtime (such as `pi -p` or
`claude -p`) from a shell command.

### Restrictions and Directives

1. **NEVER invoke the host agent's own CLI binary via `Bash`.**
   - Do not call `claude` from inside Claude Code.
   - Do not call `pi` from inside Pi.
   - Always use the native in-process tool for same-harness tasks.
2. **Treat external CLI calls as untracked processes, not child agents.**
   - CLI shell-outs do not appear in the harness task list.
   - Token expenditures are unattributed to the session budget.
   - The harness cannot intercept, inspect, or cancel the child process.
   - Shell-outs must never be used to bypass an approval gate that was
     declined by the user.

### Execution Hygiene

When a task requires a model available only through the alternate harness,
probe the environment and apply strict execution hygiene:

```sh
# Verify the alternate CLI is installed on this host
command -v pi
command -v claude
```

1. **Write the brief to a payload file:**
   Do not embed multi-line prompt text directly into the command string.
   Write the payload to a file and supply it via `$(cat payload.md)`.
2. **Use ephemeral session flags:**
   Include `--no-session` for `pi` to prevent cluttering session databases.
3. **Execute authoritative commands:**
   Copy the `execution.<harness>.command` string verbatim from
   `~/.agents/model-benchmarks.json`.
4. **Disclose the shell-out:**
   Because shell-outs execute out-of-band, the coordinator must report in
   its output that it invoked an external CLI fallback and state the
   reason.
