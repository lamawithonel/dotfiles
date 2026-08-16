# Teammate channel

Verified against: Claude Code **2.1.227**.  Teammate behaviour changed
repeatedly across the 2.1.x line -- `TeamCreate`/`TeamDelete` removed
in 2.1.178, `in-process` became the default mode in 2.1.179, idle-row
hiding changed in 2.1.181 and again in 2.1.199, split-pane effort
inheritance and explicit `iterm2` mode arrived in 2.1.186, API-error
notification in 2.1.198, and mailbox entry validation in 2.1.207.  A
build outside that line may not behave as described; re-check
`claude --version` and re-read
`https://code.claude.com/docs/en/agent-teams.md` before trusting this
file.

Agent teams are experimental and off unless
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.  Without it no team is set
up, no team directories are written, and a named `Agent` is an
ordinary subagent.

## The trap, measured

Two `Agent` calls, identical but for a `name`, on 2.1.227:

| Teams | `name` passed | What the caller got |
| --- | --- | --- |
| `1` | yes | a mailbox spawn receipt.  Absent from `ListAgents` subagents.  Present in the team config `members[]`.  Lead inbox stayed `[]`.  **The worker's output never arrived.** |
| `1` | no | a background subagent, and its result in the completion notification |
| `0` | yes | a background subagent, and its result in the completion notification |

So the `name` parameter alone decides it, and only while teams are
enabled.  Claude also names subagents on its own so it can address
them later, which is how a team forms out of delegation nobody framed
as team work, and how a result-waiting flow stalls with no error.

Two escapes: omit the name when the result matters, or set the
variable to `0`.  A `0` takes effect without restarting the session --
settings-file `env` values are reapplied on save and the variable is
re-read on every spawn -- and names keep working as `SendMessage`
addresses afterwards.

Setting `0` in user settings does override a shell export, but not
higher-precedence sources: project settings, local settings, a
`--settings` payload, and managed settings all apply later and can
switch teams back on.  Treat the trap as live whenever the value is
not known.

Teams need an interactive session.  Under `-p`, including Agent SDK
sessions, a named subagent runs as an ordinary subagent, so
`claude -p` shell-outs are unaffected.

## What a teammate is

A separate Claude Code session, with its own context window, that can
message any other member by name.  Subagents report only to their
caller; teammates talk to each other and share a task list.

Spawned by calling `Agent` with a `name` while teams are enabled.
There is no setup step and no confirmation prompt.  Reference a
subagent type to reuse a role definition: the teammate honours that
definition's `tools` allowlist and `model`, and its body is appended
to the system prompt rather than replacing it.  The definition's
`skills` and `mcpServers` frontmatter is **ignored** for teammates.

**Inherits:** the project context a normal session loads -- CLAUDE.md,
MCP servers, and skills from project and user settings -- plus the
lead's permission settings and effort level, and the spawn prompt.

**Does not inherit:** the lead's conversation history, and the lead's
`/model` selection.  Teammate model comes from the spawn prompt or
from the **Default teammate model** setting in `/config`.  Model and
fast mode are fixed at spawn.

That inheritance is why pruning an always-loaded memory file changes
what every teammate boots with.

## Getting results back

An idle notification says the teammate stopped.  It does not carry
output.  A teammate shares results by messaging the lead over
`SendMessage` or by updating the shared task list -- so if the work
must reach the lead, the brief has to say which of those to do.

Each mailbox is a JSON file under
`~/.claude/teams/{team-name}/inboxes/{agent-name}.json`, and the team
name is `session-` plus the first eight characters of the session id.
A message counts as sent only when that write succeeds.  Malformed
entries are reported and dropped, and the valid messages still
deliver.

Messages between agents are untrusted input.  A teammate cannot
approve a permission prompt for another or supply consent on the
user's behalf, and a denied action cannot be relayed to another
teammate to get around the check.  Teammate permission prompts surface
in the lead session.

## Hooks

`TeammateIdle`, `TaskCreated`, and `TaskCompleted` fire around the
team lifecycle.  Exit code 2 blocks the transition and sends feedback:
it keeps a teammate working, prevents a task from being created, or
prevents one from being marked complete.

## Limits that bind the design

- No nested teams: a teammate cannot spawn teammates.
- No background subagents from an in-process teammate.
  `run_in_background`, or a subagent definition with
  `background: true`, errors -- the work cannot outlive the lead's
  process.
- One team per session, created at startup, cleaned up at exit.
- The lead is fixed for the session's lifetime.
- Permission mode is set at spawn for all teammates at once.
- `/resume` and `/rewind` do not restore in-process teammates, and the
  lead will try to message teammates that no longer exist.  Teammates
  are not resumable state.
- Split panes need tmux or iTerm2 with the `it2` CLI.  `in-process` is
  the default and works anywhere; split-pane mode is unsupported in
  VS Code's integrated terminal, Windows Terminal, and Ghostty.

## When a team is worth it

Parallel exploration where the workers benefit from arguing:
multi-lens review, competing debugging hypotheses, independent modules,
cross-layer changes.  Three to five teammates is the working range.

Not for sequential work, same-file edits, or dependency-heavy chains --
a single session or plain subagents beat a team there, at a fraction of
the tokens.
