# Global Instructions

## Local Instructions

Read @~/.agents/AGENTS.local.md for local instructions.  Local instructions
take precedence over global instructions.

## Session Start Instructions

Perform these actions if they have not yet been performed unless the user
requests otherwise:

- Use the `/caveman` skill
- Use the `/ponytail` skill
- Create a session temporary directory at session start or if the session
  was resumed-- either `$TMPDIR/<session-id>` or `/tmp/<session-id>` if
  `$TMPDIR` is unset.  Remember the expanded path and hard-code it when used.

---

## Runtime Protocol (All Harnesses)

Universal invariants for every harness that loads this file (Claude Code,
Pi, and future harnesses).  Harness bootstrap files add only native tool
wiring and MUST NOT restate or override these invariants.

### Context Isolation

- Force worker sub-agents to operate within isolated execution windows.
- Sub-agents must swallow verbose streams (compilers, test runners,
  package managers, renderers) internally and return only high-signal
  results to the parent thread.
- Parent context receives conclusions, receipts, and `file:line`
  references-- never raw tool-output dumps.

### Execution Ceilings and Circuit Breakers

- **12-turn ceiling:** sub-agents are allowed up to 12 sequential turns
  to execute complex, multi-step implementations.
- **3-turn state-stagnation breaker:** a sub-agent MUST immediately
  self-terminate and yield control if 3 consecutive turns produce zero
  state progress (e.g., executing the identical terminal command,
  repeating a failing edit, or hitting the exact same error boundary).
- **Early boundary escape:** if a sub-agent discovers during its initial
  context-gathering turn that the assignment requires modifying more
  than 3 decoupled subsystems, it must halt immediately, output an
  execution map, and return control to the coordinator for finer task
  partitioning.

### Cross-Harness Model Dispatch

Detect the active harness before dispatching model work:

- `CLAUDECODE=1` in the environment -> Claude Code.
- `PI_CODING_AGENT` or `PI_SESSION_ID` in the environment -> Pi.
- Neither -> assume no harness sub-agent tools; use CLI shell-outs only.

Harness availability is per-host, never assumed: an external channel
exists only if its CLI is actually installed (`command -v pi`,
`command -v claude`).  Some hosts run Claude Code alone, with a
restricted private-hosted model set and no Pi at all; on such hosts
every non-native model is simply unavailable and the router must
route around it.

Native models dispatch through the harness's own sub-agent tools; all
other models shell out to the other harness's CLI where that CLI is
installed:

| Harness     | Native models              | Native channel     | External channel     |
| ----------- | -------------------------- | ------------------ | -------------------- |
| Claude Code | Anthropic Claude           | `Agent`/`Workflow` | `pi` CLI shell-out   |
| Pi          | OpenRouter and `llama-cpp` | Pi sub-agents      | `claude -p` shell-out |

The table shows channel shapes only; the exact command string or tool
parameters for a given model live in that model's
`execution.<harness>` block in `~/.agents/models.json`.

Model selection is data-driven-- never pick a delegate model from memory
or vibes:

- The registry is two files split by sync domain.
  `~/.agents/models.json` is HOST-LOCAL truth: only the models
  reachable from this host, under this host's ids and aliases
  (private-hosted and Bedrock deployments use different ids than
  consumer plans); never sync it between machines.
  `~/.agents/benchmarks.json` is GLOBAL truth (benchmark scores and
  public pricing keyed by public model identity): identical
  everywhere, safe to sync via dotfiles, refreshed where egress
  allows and received by sync on restricted hosts.
- When a task requires delegation, load the `model-router` skill
  (`~/.agents/skills/model-router/`).  It scores candidates against
  the two-file registry (real benchmark metrics and live pricing;
  zero arbitrary rankings).
- Claude Code specifics (tool parameters, shell-out syntax, outage
  handling) live in `~/.claude/CLAUDE.md`.
- Where Pi is installed, it loads this file directly and needs no
  separate bootstrap; the dispatch table above plus the `model-router`
  skill fully resolve Pi-side routing.  Pi's scoped model roster is
  `enabledModels` in `~/.pi/agent/settings.json`.

### Skill Storage

Skills live in `~/.agents/skills/` as the single source of truth.
Harness skill directories are symlinks into it (e.g., `~/.claude/skills
-> ../.agents/skills`).  Never install a skill into a harness-private
directory.

## Project-level Host-Local Directories

If a project directory has no declared host-local directory scheme:

- Use `.local/share/` for host-local data
- Use `.local/state/` for host-local state
- Use `.cache/` for host-local temporary files
- Use `$TMPDIR/<session-id>` for one-off temporary session files
- Use the XDG base dir specification guidelines when selecting the
  correct directory.  The directories intentionally mimic the XDG base
  dir spec to make this classification easy.

If they are not already used by the project, add these directory patterns
to the project `.gitignore` on first use or creation of a nested file:

- `.local/`
- `.cache/`

If the project already uses them and they cannot be safely git-ignored,
add the next deepest level that can be safely added, for example,
`.local/state/` if it is unused or `.local/state/<slug>/` if
`.local/state/` is used.

## Long-Context Recovery

To recover from crashes or paused sessions...

- Keep a YAML-formatted project journal at `.local/state/agents/journal/<YYYY-MM-DD>.md`
- Log a journal entry on each turn that edits or deletes a project file.
- Journal VCS work by pointer (op-id, change-id) on promotion, not on
  capture; the jj oplog is the truth and the journal is the index into
  it.
- Use `.cache/agents/` as a project-level scratchpad.
- **DO NOT** use session IDs in path or file names.
- **DO** use session IDs in file entry headers, metadata, comments, etc.
- **DO NOT** eagerly read every journal file.
- **DO** look for and read the latest journal file at session start.
- **DO** inform the user if there are journal files older than 2 weeks old.
- **DO NOT** trim or purge the journal directories without asking the user.

## English Writing Style Guide

- Use two spaces after sentences for readability.  Most code, comments, READMEs,
  documentation, and LLM text documents render in monospace fonts.  Without
  proportional fonts and dynamic kerning the modern rule of "use only one
  space after periods" is moot.  The conditions that led to the older em-space
  rule exist today and we should honor that rule for readability.  Besides,
  modern text rendering systems usually collapse the two spaces down at
  render-time, so it makes little difference for readers that prefer one
  space over two, it will all look the same in the end.
- Use an oxford comma in lists of three or more items for clarity, e.g.,
  "A, B, and C".
- Do not use the unicode em-dash (—).  Instead, use two ASCII hyphens (--).
- Use the em-dash sparingly and only when it improves clarity.  Avoid using
  it in place of parentheses or commas.
- Semicolons are great when used correctly; they fall flat when overused.

## Agent Prompt Style

- **ALWAYS** use XML-style prompts when crafting instructions for agents.
- **ALWAYS** use imperative tone.
- Always start with a `<persona>` section to elicit desired behavior, except
  when starting from a pre-defined agent persona.  The persona is not a role.
  The persona should "tickle the tensors" and "poke the weights," using words
  and phrases to activate relevant model embeddings and experts.  Define
  the personality in terms of integral theory's four quadrants.
- Use a `<role>` section to define the agent's role and responsibilities.
- Use a `<context>` section to orient agent.
- Use `<return>` with an optional `<template>` to specify return expectations.
- Use other tags as needed.  Tags are informal with no set schema.  Examples
  include: `<approach>`, `<deliverables>`, `<example_group>`, `<example>`,
  `<hard_gates>`, `<kickoff>`, `<scope>`, `<stages>`, `<the_ask>`,
  `<working_agreement>`, `<success_criteria>`, `<prompt>`, etc.
- Tags may be nested and may include arbitrary parameters.
- Place tags on their own lines, except for extremely short lines.
- Use blank lines between top-level sections.

Example:

```xml
<persona name="Mr. Robot">
You think...          # (Interior-Individual)
You behave...         # (Exterior-Individual)
You relate to/with... # (Interior-Collective)
You participate...    # (Exterior-Collective)
</persona>

<role>
You are a...
</role>

<context>
...
</context>

<the_ask>
Summary...
  <example_group>
    <example>short example...</example>
    <example>single-line example...</example>
    <example>
      longer
      multi-line
      text
    </example>
  </example_group>
</the_ask>

<return>
Return instructions...
  <template>
    ...
  </template>
</return>
```

## Software Development Lifecycle

- **ALWAYS** use RED -> GREEN testing
- **ALWAYS** use Behavior-Driven Development (BDD)
- **ALWAYS** adhere to the Test Pyramid (highest volume first):
  1. Static Checks (Types & Linting)
  2. Unit Tests (Isolated logic, fast mocks)
  3. Integration Tests (Real DB, disk, or local I/O)
  4. Contract Tests (API schemas & service boundaries)
  5. E2E Tests (Full system workflows)

## Version Control & Workspace Directives

1. **Conditional VCS Routing**: Route code mutations, diff analyses,
   and task checkpoints through `vcs-workflow` ONLY when its
   `scripts/detect_shape.sh` returns a workable shape (colocated,
   jj-only, jj-workspace, or git-only) or when initializing VCS.
   Never route to vcs-workflow -- or run ANY jj command, reads
   included -- when the shape is `worktree-shadowed`; use plain git
   there.
2. **Un-tracked Workspace Exemption**: Skip VCS workflows during early
   planning, brainstorming, research, or non-repository chat sessions.
3. **History Integrity**: Within tracked repositories, enforce
   non-destructive workspace operations and never pollute commit
   history with unverified intermediate states.  Exception: the
   vcs-workflow preflight may write four allowlisted jj config keys at
   `--repo` scope, announced in its receipt.
4. **Commit Serialization**: Hand off to `git-commit` after
   verification gates pass.  `git-commit` is the codex -- the
   authority on atomicity criteria, selection doctrine, message
   structure, style, and trailers.  `vcs-workflow` prepares atomic
   revisions to that standard and supplies the jj-shape serialization
   mechanics (its `references/serialization.md`); gates run upstream,
   judgment stays with the codex.
5. **Autonomy Ceiling**: The ceiling is the PR.  Pushing a branch and
   opening a PR may be automatic; merging to the default branch is a
   standing human gate.
6. **Vocabulary**: "tier" is reserved for model-access tiers
   (`~/.agents/models.json`) and license tiers; VCS skills use role
   nouns (staging layer, serializer) and pipeline step names, never
   Tier-N.
7. **Hookless Snapshot Guard**: before any file-targeting
   `git checkout`, `git restore`, `git stash`, `git clean`, or
   `git reset` in a colocated jj repo, run a jj snapshot (`jj status`
   or any jj command) first, in the same turn, with nothing
   intervening.  These git commands are commonly
   permission-allow-listed, and allow-listed does not mean safe to run
   blind against a still-open jj commit.  Prefer
   `jj restore --from <rev> <path>` whenever the intent is to discard
   working-copy content: it snapshots before it mutates, so a mistake
   is one `jj undo` from recovery.
8. **`/commit` Routing**: `/commit` routes to the `git-commit` skill
   (the executor).  `caveman-commit` is a message-style layer only;
   when caveman mode is active, git-commit delegates prose style to it
   and retains validation, trailers, and serialization.

## Tool Preferences

- Use mise as the primary task runner and devtool dependency manager
- Use language-specific package managers for project dependency management
- Use `cargo build`, `cargo embed`, and `probe-rs` for Rust build and flash
  operations-- not mise.
- Use `gh` to interact with GitHub, NEVER `curl`.
- Use Podman over Docker for container operations.  Rootless mode is
  the default.
- Use SELinux-aware bind mounts (`:Z`) when mounting host paths into
  containers.

### Dependency & Third-Party Licensing

When selecting, adding, or installing dependencies, external packages, or
source code:

* **Permissive Default:** Permissive software (Apache-2.0, BSD, MIT) is
  auto-approved.
* **Non-Permissive / Complex Licenses:** Do not install or import strong
  copyleft, source-available, or unverified packages without checking compliance.
* **Skill Trigger:** Before editing lockfiles (`package.json`, `Cargo.toml`,
  `go.mod`, etc.), adding imports, or executing package installs, you **MUST
  load and execute the `license-compliance` skill** to classify the license
  tier and follow its execution instructions.
