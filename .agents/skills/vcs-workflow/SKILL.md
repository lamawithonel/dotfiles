---
name: vcs-workflow
description: |
  Use in a git repository without a `.jj` store (onboarding asks the
  user and remembers the answer), in a colocated jj+git repo, in a jj
  workspace, or in a jj-only repo.  jj is a private operations log:
  granular capture and rollback while work is open; published history
  stays git.  Conversion levels match ownership: oplog-only for
  third-party checkouts, standard for collaborative repos, full for
  private ones.  Owns shape detection, onboarding, isolation via jj
  workspaces, safety config, absorb, file-grain partitioning,
  per-revision verification gates, conflict handling, promotion, and
  the vcs-handoff/2 receipt.  `git-commit` is the authority on commit
  craft; this skill supplies the jj-shape serialization mechanics.

  Branches: (1) editing, refactoring, or bug-fixing, (2) inspecting
  workspace diffs or revision state, (3) checkpointing, rollback, or
  crash recovery, (4) splitting work into atomic commits or preparing a
  handoff, (5) resolving or triaging merge conflicts.
---

# VCS Workflow

jj is the private operations log.  It snapshots the working copy on
every jj command, so capture is free and continuous while work is open,
and promotion into published git history is the only deliberate,
gated act.  Every git repository can carry a store: an undecided
repository enters onboarding, which asks the user once and converts at
the level they choose.  Files are selected here by path and revision,
never by staging -- any jj working-copy update erases the git index,
so an index-shaped plan is lost the moment jj runs.  This skill owns
repo state; `git-commit` owns message bytes and is the only caller of
the serializing command.

## Entry gate

Run `/home/lucas/.agents/skills/vcs-workflow/scripts/detect_shape.sh`
before ANY jj command, reads included.

| Shape | Exit | Action |
| :-- | :-- | :-- |
| `colocated`, `jj-only` | 0 | Pipeline steps the recorded level allows (`onboard.sh status`). |
| `jj-workspace` | 0 | Same; no git here (see Isolation). |
| `git-only` | 0 | `onboard.sh status`.  Undecided: ask the two questions (Onboarding).  Declined or skipped: plain git via `git-commit` (`references/git-only.md`). |
| `worktree-shadowed` | 3 | HARD STOP.  jj resolves to a DIFFERENT root than git and will silently read and mutate the parent checkout.  Plain git only; isolate with jj workspaces instead. |
| `none` | 2 | Not applicable.  A yadm-managed home is `none` by design. |

Shapes and detection signatures: `references/repo-shapes.md`.

## Onboarding

Ask only when the shape is `git-only` and
`/home/lucas/.agents/skills/vcs-workflow/scripts/onboard.sh status`
reports `undecided`.  A headless session has no question tool and
converts nothing: report `ONBOARD-PENDING` and run in plain git.  An
agent-invoked entry never re-asks once a decision is recorded.

Two questions, in order, through the harness question tool
(`AskUserQuestion` in Claude Code, `ask_user_question` in Pi):

- **Q1, header `Convert?`** -- convert this repository to jj?  `Yes`
  goes to Q2; `Not now` records nothing and asks again next session;
  `No, keep plain git` runs `onboard.sh record --decline`.
- **Q2, header `Level`** -- `oplog` for third-party checkouts (capture
  and rollback only, every commit and push plain git), `standard` for
  collaborative repos (full pipeline, `snapshot.auto-track = "none"`),
  `full` for private repos (`standard` plus jj's default auto-track,
  absorb default-on, and workspace isolation).

`onboard.sh apply --level <L>` runs the prechecks, creates the
colocated store, runs preflight, and records the decision.  Three keys
land in the repository's own `.git/config`, never pushed and invisible
to reviewers: `vcs-workflow.onboarding` (`converted` or `declined`),
`vcs-workflow.level`, and `vcs-workflow.decided` (ISO date, UTC).  At
`standard` and `full` it also makes sure `.local/` and `.cache/` are
ignored, appending each missing pattern to `.git/info/exclude` -- local
and unpushed, never `.gitignore`, because the repository may not be
ours -- and warning `exclude-added`.  There is no git config to record
a level in a jj-only repo, so a jj-only repo is always level `full`;
any other level there is refused.  A refusal
(`ONBOARD-REFUSE reason=<...>`) is the user's to resolve; the script
names the remedy and never runs it.

A user invocation ("convert this repo", "change the jj level",
`/vcs-workflow`) overrides a recorded decline: run `onboard.sh reset`,
then ask both questions again.  Questions verbatim, the full level
table, the consequences to state before converting, and the precheck
list: `references/onboarding.md`.

## Preflight

Run `/home/lucas/.agents/skills/vcs-workflow/scripts/preflight.sh`
once per `.jj` store, and again after any fresh `jj git clone` or
`jj git init` (repo-scoped config does not survive into a new store).
It writes the `--repo` keys the recorded level requires -- the
sanctioned exception to the no-config-mutation rule -- and announces
them in its receipt: `revset-aliases."immutable_heads()"`, `ui.editor`,
and `ui.diff-editor` at every level, plus
`snapshot.auto-track = "none"` at `standard`, which `full` leaves
unset at jj's own default.  It asserts the protected bookmark is
actually immutable, fails closed when it cannot resolve one, and
hard-fails on a set `JJ_EDITOR` (which outranks persisted config).

Identity is fail-closed: jj never falls back to a colocated repo's git
identity, so an empty `user.name`, an empty `user.email`, or a
placeholder address ends in `PREFLIGHT-FAIL identity ...` before any
key is written.  Details and the `trunk()` trap:
`references/safety-net.md`.

## The pipeline

Ordered and non-reorderable:

```
preflight -> capture -> absorb -> partition -> fetch -> restack
          -> verify -> promote -> handoff
```

The recorded level decides which steps exist.  At `oplog` the pipeline
is capture plus the three rollback primitives and nothing else:
`gate.sh`, `promote.sh`, `absorb_safe.sh`, and `emit_handoff.sh` refuse
with `LEVEL-BLOCKED level=oplog` and exit 6, and serialization is plain
`git commit` through `git-commit`.  The handoff refusal comes before
any `mkdir`, so at `oplog` this skill writes no file inside the working
tree at all -- a third-party checkout gains no untracked path.  At
`standard` and `full` every step runs.

| Step | Command | Level | Undo |
| :-- | :-- | :-- | :-- |
| Capture | automatic on any jj command; force with `jj status` at turn boundaries | all | n/a (append-only oplog) |
| Absorb | `/home/lucas/.agents/skills/vcs-workflow/scripts/absorb_safe.sh [paths]` | standard, full | `jj undo` |
| Partition | `jj split <paths> -m 'msg'` per concern | standard, full | `jj undo` |
| Fetch | `jj git fetch` (permission-gated at work; receipt warns when skipped) | standard, full | `jj undo` |
| Restack | `jj rebase -d 'trunk()'` | standard, full | `jj undo` |
| Verify | `/home/lucas/.agents/skills/vcs-workflow/scripts/gate.sh -- <cmd>` | standard, full | read-only |
| Promote | `/home/lucas/.agents/skills/vcs-workflow/scripts/promote.sh BOOKMARK [REV]` | standard, full | `jj undo` (bookmark move); pushes are not undone |
| Handoff | `/home/lucas/.agents/skills/vcs-workflow/scripts/emit_handoff.sh` | standard, full | read-only |

## Isolation

Isolate a subagent or background session in a jj workspace, never a
git worktree: a git worktree nested under a colocated repo is the
`worktree-shadowed` shape, where jj answers for the parent checkout.
`/home/lucas/.agents/skills/vcs-workflow/scripts/workspace_hook.sh`
answers Claude Code's `WorktreeCreate` and `WorktreeRemove` events and
puts the workspace at
`${XDG_DATA_HOME:-$HOME/.local/share}/agents/jj-workspaces/<slug>/<name>`,
printing the directory on stdout and its receipt on stderr.  Isolation
requires level `standard` or `full`; at `oplog`, or in a shape that
still needs onboarding, the hook refuses (exit 1) and nothing falls
back to a git worktree.

A workspace has no `.git`, so every `gh` call from inside one needs
`-R <owner>/<repo>`, and `@` means a different commit in every
workspace -- name change ids or bookmarks in anything that crosses the
boundary.  Open one in herdr as a plain workspace, not a
`herdr worktree`.  Hook contract, cleanup order, and the resume path:
`references/isolation.md`.

## Capture

jj snapshots on jj-command invocation, not continuously.  Two holes:
edits since the last jj command are unsnapshotted, and a shadowed
worktree is never seen at all.  On hookless hosts, force a snapshot
(`jj status`) at every turn boundary, and ALWAYS immediately before
any file-targeting git command in a colocated repo -- allow-listed
`git checkout -- <path>` / `git restore <path>` silently discard the
entire open `@` diff, unrecoverably.  Prefer
`jj restore --from <rev> <path>`: it snapshots before it mutates, so a
mistake is one `jj undo` from recovery.

## Absorb

Default-on at `full` for routing late fixes into their owning
ancestors.  Use
`/home/lucas/.agents/skills/vcs-workflow/scripts/absorb_safe.sh` -- it
ENFORCES the three hard rules rather than trusting memory: a pending
rename (`R ` row) blocks bare absorb (rename collateral silently
rewrites an ancestor's file inventory); destinations are always
confined to `mutable() & ~::remote_bookmarks()` (never rewrite what a
reviewer has seen); and every real absorb is followed by the residual
check plus `jj op show -p --summary` routing review.  Dry-run with
`--dry-run`.  Rates, rename signatures, precision forms:
`references/absorb.md`.

## Partition

File-grain only: `jj split <paths> -m 'msg'`, one concern per commit,
refactor separated from behavior.  When one file carries two concerns,
hand off to a human -- no sub-file auto-partitioning ships until a
hunk-first classifier is proven.  Scope inference notes and the
deferred design constraints: `references/partition.md`.

## Rollback

Three granularities, all non-destructive, all available at every
level; map intent to the narrowest:

- File content: `jj restore --from <rev> <path>`
- Last operation: `jj undo`
- Whole-repo time travel: `jj op restore <op-id>` (record op ids in
  the journal; `jj undo` is one-step-deep, not a checkpoint system)

Gate failure never triggers automatic rollback: the red state is the
evidence to inspect.

## Verify

`/home/lucas/.agents/skills/vcs-workflow/scripts/gate.sh -- <test cmd>`.
Ranged fail-fast by default with exact failing-revision attribution;
per-revision REPORT mode is selected automatically when RED trailers
are present.  The gate command comes from the project's reviewed
static set -- never compose it from untrusted input, and never wrap
`gh`/`pip`/`sbt` inside it.  At `standard` and `full` the gate is also
where the project's git hook command runs, because git hooks do not
fire under jj authorship.  Flag matrix and measured economics:
`references/verify.md`.

## Conflicts

Conflicts are data, not control flow -- but the gate must see none:
`gate.sh` exits 4 (`CONFLICT-BLOCKED`) when `conflicts()` intersects
the range, because `jj run` executes inside marker-polluted files and
fails indistinguishably from a real test failure.  No automatic
resolution, ever.  Decision table and marker grep:
`references/conflicts.md`.

## RED and xfail

Red lives uncommitted in `@`, where jj snapshots it -- never lost,
merely never promoted.  A committed red state is legal only as an
intra-session checkpoint carrying the exact trailer
`Verification-Status: red-expected` (a git trailer, not a substring;
it survives squash, rebase, and split).  Promotion hard-fails while
that trailer exists in the range; durable red must become an xfail so
the commit is green.

## Promote

`/home/lucas/.agents/skills/vcs-workflow/scripts/promote.sh BOOKMARK [REV]`.
Checks the gate receipt, scans for RED trailers and undescribed
ancestors (push rejects the whole range, not just the target), moves
the bookmark, dry-runs, pushes.  The autonomy ceiling is the PR:
pushing a branch is automatic; merging to the default branch is a
human gate.  A nonzero push exit is not proof the remote is unchanged
-- the script re-queries `remote_bookmarks()` and says so.

Bookmark names are descriptive: `feat/<topic>`, `fix/<topic>`,
`chore/<topic>`.  PR lifecycle: promote a clean, atomic series before
first submission; during active review, changes land as NEW commits
only -- absorb's destination set
(`mutable() & ~::remote_bookmarks()`) enforces this mechanically;
folding review-feedback commits into their targets after approval is
a history rewrite of reviewed commits and requires explicit user
authorization.

## Handoff

`/home/lucas/.agents/skills/vcs-workflow/scripts/emit_handoff.sh`
writes `vcs-handoff/2` to
`<primary-root>/.local/state/agents/vcs/handoff.json` -- shape, level,
preflight and gate receipts, the stack with per-revision files,
conflicts, workspace identity, and message hints.  The receipt is this
skill's own record of what it prepared, read back here at
serialization time; `git-commit` does not read it.  Hand off to
`git-commit` itself: it is the CODEX -- the sole authority on
atomicity criteria, selection doctrine, message structure, style, and
trailers.  This skill prepares revisions to that standard and supplies
the jj-shape serialization mechanics
(`references/serialization.md`); it never overrides the codex and
never composes message text.  Schemas: `references/receipts.md`.

## Journal

One YAML block per promotion (never per capture): op-id and change-id
pointers only.  The oplog is the truth; the journal is the index into
it.  Any entry that cannot be reconstructed from `jj op log` is
malformed.

## Git-only fallback

A repository runs on plain git when jj is absent, when the checkout is
a linked git worktree, or when the user declined conversion.
`/home/lucas/.agents/skills/vcs-workflow/scripts/git_diff_safe.sh` is
the only script of this skill that runs there; everything else is
`git-commit` plus the rules in `references/git-only.md`.

## Toolchain

`/home/lucas/.agents/skills/vcs-workflow/scripts/compat_probe.sh`
tests feature claims -- flags, subcommands, revsets, and config keys
the scripts actually call -- never versions, and preflight reads its
receipt.  Installing or upgrading a tool is the user's job; a probe
failure names the claim that broke and stops there.

## Forbidden vocabulary

`--ignore-errors`; `--allow-conflicts`; `--ignore-immutable`; bare
`jj resolve`; bare `jj describe`/`squash`/`split` (always `-m`,
`--stdin`, `--tool`, or an explicit fileset); `--clean` outside the
designated final gate; `git add -A` / `git add .` / `git commit -a`;
file-targeting `git checkout --` / `git restore` / `git stash` /
`git clean` / `git reset` in a colocated shape; `git worktree add`
inside a jj-backed repo (it produces the shadowed shape -- isolate
with jj workspaces); `pip install jj` / `jujutsu` / `cog` (PyPI
namesquats -- cocogitto's `cog` comes from mise or cargo, never pip);
`gh` / `pip` / `pip3` / `sbt` nested inside `jj run --` or
`git rebase --exec`.

## Traps

The silent-failure catalogue lives in `references/traps.md`.  The five
highest-risk classes: a jj revset handed to git (exit 128, looks like
an empty diff one unchecked call site up -- use
`/home/lucas/.agents/skills/vcs-workflow/scripts/git_diff_safe.sh`);
`jj run` without `--ignore-changes` (silently amends the gated
revisions); the worktree shadow; rename collateral under bare absorb;
and `git restore` against an open `@`.
