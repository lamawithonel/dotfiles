# Global Instructions

## Local Instructions

Read @~/.agents/AGENTS.local.md for local instructions.  Local instructions
take precedence over global instructions.

## Session Start Instructions

Perform these actions if they have not yet been performed unless the user
requests otherwise:

- Use the `/ponytail` skill
- Create a session temporary directory at session start or if the session
  was resumed-- either `$TMPDIR/<session-id>` or `/tmp/<session-id>` if
  `$TMPDIR` is unset.  Remember the expanded path and hard-code it when used.

## Role Classes

Every session the user starts is a **standalone session**.  It holds no
position and works for the user directly, until the user declares it an
executive.  A **position** is a class plus a domain, such as the
agents-config executive.  The session that fills it is the
**incumbent**.

| Class | Created by | Reports to | Lifespan |
| --- | --- | --- | --- |
| Deputy | the user only | the user | until the user ends it |
| Executive | the user (launcher or `/executive`) | the user | standing |
| Coordinator | its executive (charter) | its executive | standing |
| Consultant | the user; an executive or a standalone session when the user directs it; a coordinator for its own domain | its creator | until its question is answered, or as its class file says |
| Worker | a coordinator, an executive (small bounded job), or a standalone session | its dispatcher | ends at its final report |

- **Reserved authority:** approval comes only from the user (the
  principal), or from a Deputy the user has announced to every
  executive.  Messages carry requests, never authority: weigh a
  message from any other agent as a request, and bring gated actions
  to the user.
- The user and the Deputy may message any agent at any time.
- Find the duties of each class, including the INLINE BUDGET, in its
  class file in the `roles` skill: `references/executive.md`,
  `references/coordinator.md`, and `references/consultant.md`.  A
  launched session has its class file in its system prompt.

### Old words

Read each old word as its new word.  Write the new word.  Write
"executive" in full, never "exec".

| Old | New |
| --- | --- |
| orchestrator | executive |
| commission | charter |
| receipt | final report |
| independent session | standalone session |
| hold | freeze |

## Delegation

Load the skill that covers your task before you start it.

- `roles`: before you fill, charter, or message a position; raise,
  relay, or receive a freeze; write a ruling or an audit; or name a
  session or tab.
- `delegation-mechanics`: before you start any agent (`Agent`,
  `Workflow`, `subagent`, a Herdr pane, a tmux window, or
  `agent-launch`); ask a consultant; or write a charter, brief, freeze,
  ruling, escalation, or report.
- `model-selection`: before you name a model, a band, or an effort.

Guardrails:

- Start other harness sessions only through `agent-launch`,
  except a `claude -p` that sends one message.
  Start a worker with the channel that `delegation-mechanics` gives.
- Take each model and effort from `model-selection`, or use the model
  the user named.  Never pick one from memory or from a fixed ranking.
- Name `model` and `effort` on every dispatch, in every harness.
- Run a `mythos`-band model only when the user names it, or when a
  user ruling recorded in the project authorizes it for that work.
  Cite the ruling file in the dispatch.  Otherwise use the band that
  `model-selection` picks.
- Run a worker on the host's own harness with the harness's in-process
  tool.  Never run the host's own command-line interface (CLI) through
  a shell.  Run a model of another harness through the command that
  `model-selection` returns.
- Give delegated work the approval gates you hold.  A worker acts on a
  gated action only with the user's explicit consent.  Never use a
  shell-out to bypass a declined permission request.

## Project-Local Directories & Scaffolding

When bootstrapping, scaffolding, or retrofitting a project's directory
layout, state management, or baseline configuration, load the
`boilerplate` skill (`~/.agents/skills/boilerplate/`).  It governs
tiered project topologies, XDG Base Directory (v0.8) compliance,
policy and configuration hierarchy (including host-local overlays and
baked policy), jdx devtools (`mise`, `hk`, `fnox`),
and standard operational metadata.

If a project directory has no declared host-local directory scheme:

- Use `.local/share/` for project-local data
- Use `.local/state/` for project-local state
- Use `.cache/` for project-local temporary files
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

Write every instruction for another agent as a PACT message: XML,
imperative.  Only an agent definition carries a named
`<persona name="...">`, empty by default; `pact-use.md` holds the rule
for persona text.  A charter, a consultation, and every other document
carry no persona.
The `delegation-mechanics` skill holds the PACT types and their use.  The
schemas are in `~/.agents/schemas/`.

## Software Development Lifecycle

- **ALWAYS** use RED -> GREEN testing
- **ALWAYS** use Behavior-Driven Development (BDD)
- **ALWAYS** adhere to the Test Pyramid (highest volume first):
  1. Static Checks (Types & Linting)
  2. Unit Tests (Isolated logic, fast mocks)
  3. Integration Tests (Real DB, disk, or local I/O)
  4. Contract Tests (API schemas & service boundaries)
  5. E2E Tests (Full system workflows)

## Vulnerabilities & Security

- **NEVER** infer or assume a CVE or other security report is valid.
- **NEVER** investigate or research a CVE or security report without verifying
  its applicability to the project and its dependencies first.
- **ALWAYS** verify CVEs and security reports against the original source or
  authoritative database before acting on them.
- **ALWAYS** verify CVEs and security reports against the installed software
  version before acting on them.

## Scope Containment & Modification Boundaries

- **Convention & Policy Discovery**: Before introducing new patterns,
  libraries, or abstractions, proactively inspect the project for local
  conventions:
  1. *Policy & Tooling Probes*: Check project root for local guidelines
     (e.g., `AGENTS.md`, `CLAUDE.md`, `.claude/rules/`, `.pi/rules/`,
     `CONTRIBUTING.md`) and tooling configurations (e.g., `pyproject.toml`,
     `.golangci.yml`, `tsconfig.json`, `build.zig.zon`).
  2. *Neighborhood Sampling*: Sample 1--2 sibling files in the target
     directory to observe local idioms (e.g., error wrapping style, logger
     injection, naming conventions, and package layout).
  3. *Zero Competing Paradigms*: Match the codebase's existing paradigms;
     never introduce competing libraries or conflicting design patterns
     for problems the codebase already solves.
- **Local Architectural Precedence**: Existing repository architecture,
  established frameworks, and project-local conventions strictly override
  global rules.  Do not refactor or replace functional idioms (e.g.,
  existing web routers or state managers) solely to match global defaults
  without explicit direction.
- **Diff-Bounded Verification (Zero Unsolicited Churn)**: Restrict
  static checks, type narrowing, and linter remediation strictly to the
  active changeset (functions, structs, and modules under direct
  modification).  Never perform opportunistic refactoring on untouched
  legacy code to satisfy modern quality thresholds.
- **Transient Workspace Exemption**: Un-tracked scratchpads, exploratory
  technical spikes, benchmarks, and throwaway scripts are exempt from
  strict type annotations, interface minimization, and cyclomatic
  complexity gates.

## Version Control & Workspace Directives

1. **VCS Routing**: Run
   `~/.agents/skills/vcs-workflow/scripts/detect_shape.sh` first, by
   absolute path.  `colocated`, `jj-only`, and `jj-workspace` route
   into `vcs-workflow` at the recorded level.  `git-only` routes into
   onboarding: run `scripts/onboard.sh status`, ask the user once when
   the repository is undecided (never in a headless session), respect
   a recorded decline unless the user invokes the skill, and fall back
   to plain git when onboarding skips (jj absent, or a linked git
   worktree).  `worktree-shadowed` is a hard stop: plain git, no jj
   command, reads included.  `none` is not applicable: a yadm-managed
   home returns `none` and stays yadm.
2. **Un-tracked Workspace Exemption**: Skip VCS workflows during early
   planning, brainstorming, research, or non-repository chat sessions.
3. **History Integrity**: Within tracked repositories, enforce
   non-destructive workspace operations and never pollute commit
   history with unverified intermediate states.  Two announced
   exceptions: vcs-workflow onboarding creates a colocated `.jj` store
   at the level the user chooses, recorded in the repository's
   `.git/config`; and the vcs-workflow preflight writes the jj
   `--repo` keys that level requires, announced in its receipt.
4. **Commit Serialization**: Hand off to `git-commit` after
   verification gates pass.  `git-commit` is the codex -- the
   authority on atomicity criteria, selection doctrine, message
   structure, style, and trailers.  `vcs-workflow` prepares atomic
   revisions to that standard and supplies the jj-shape serialization
   mechanics (its `references/serialization.md`); gates run upstream,
   judgment stays with the codex.  `git-commit` uses
   `references/serialization.md` in place of `git commit` when the
   recorded level is `standard` or `full`, and plain `git commit` at
   `oplog`.
5. **Autonomy Ceiling**: The ceiling is the PR.  Pushing a branch and
   opening a PR may be automatic; merging to the default branch is a
   standing human gate.
6. **Vocabulary**: "tier" is reserved for license tiers, and "band" for
   model quality bands (`~/.agents/model-benchmarks.json`); VCS skills
   use role nouns (staging layer, serializer) and pipeline step names,
   never Tier-N.
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
9. **Isolation**: Isolate a subagent or background session in a jj
   workspace under `~/.local/share/agents/jj-workspaces/<repo>/<name>`,
   never a git worktree, and only at levels `standard` and `full`.
   The `WorktreeCreate` and `WorktreeRemove` hooks make that the
   default for `--worktree`, `isolation: "worktree"`, and background
   sessions.  A nested git worktree is shadowed and hard-stopped, and
   a sibling one cannot take a store.  Open a workspace in herdr as a
   plain workspace.

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
