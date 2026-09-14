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

## Delegation

Trigger: Any hand-off of work to another agent, including child agents,
forks, multi-agent workflows, background workers, or command-line
interface (CLI) shell-outs.

- **Mandatory skill loading:** You MUST load the `model-router` skill
  (`~/.agents/skills/model-router/`) before performing any delegation or
  launching any child agent.  The skill determines whether to perform
  work inline or delegate, governs channel selection, and selects models.
- **Model selection:** Never select a model identifier from memory or
  hardcode model rankings.  Always query `scripts/score.py --pick`.
- **Channel routing and cross-harness execution:** When `score.py
  --pick` selects a model native to the active harness, use in-process
  delegation tools.  When it selects a non-native model whose execution
  block specifies an external command (e.g., Claude Code invoking `pi` to
  run Gemini, DeepSeek, or Qwen), executing that external CLI command
  via shell is the intended channel.  Never invoke the active harness's
  own CLI via shell.
- **Inherited permissions:** Security and approval gates apply to all
  delegated work.  A delegated worker must not execute actions requiring
  user approval without explicit consent, and shell-outs must not be used
  to bypass declined permission requests.

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

Every instruction written for an agent is a brief: XML-structured,
imperative, opening with a `<persona>`.  The contract, the tag
vocabulary, and the worked template live in
`~/.agents/skills/model-router/references/brief.md`.

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
6. **Vocabulary**: "tier" is reserved for model-access tiers
   (`~/.agents/model-benchmarks.json`) and license tiers; VCS skills use
   role nouns (staging layer, serializer) and pipeline step names, never
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
