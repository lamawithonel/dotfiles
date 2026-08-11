---
name: vcs-workflow
description: |
  Staging and verification layer for repo state during agent coding
  work.  Capture is free and always-on (jj auto-snapshot); promotion
  is deliberate and gated.  Owns shape detection, safety config,
  absorb, file-grain partitioning, per-revision verification gates,
  conflict handling, promotion (bookmark + push), and the
  vcs-handoff/1 receipt consumed at commit time (see
  references/serialization.md; the git-commit skill is the normative
  authority on commit craft).

  Activates when working inside a version-controlled repository on:
  (1) editing, refactoring, or bug-fixing tasks,
  (2) inspecting workspace diffs or revision state,
  (3) checkpointing, rollback, or crash recovery,
  (4) splitting work into atomic commits or preparing a handoff,
  (5) resolving or triaging merge conflicts.
  Verified-against: jj 0.44.0, ast-grep 0.45.1, difftastic 0.70.0,
  git 2.54 (scripts/compat_probe.sh re-verifies; pins live there).
---

# VCS Workflow

Capture is free; promotion is deliberate.  jj snapshots the working
copy on every jj command, so nothing deliberate is ever "saved" -- the
only question this skill answers is whether a state is ready to be
promoted into history.  This skill owns repo state; `git-commit` owns
message bytes and is the only caller of the serializing command.
Neither skill stages files -- under jj there is no index.

## Entry gate

Run `scripts/detect_shape.sh` before ANY jj command, reads included.

- `colocated | jj-only | jj-workspace` (exit 0): proceed.
- `git-only` (exit 0): reduced mode; see `references/git-only.md`.
- `none` (exit 2): no VCS here; this skill does not apply.
- `worktree-shadowed` (exit 3): **HARD STOP.**  jj resolves to a
  DIFFERENT root than git and will silently read and mutate the
  parent checkout.  Use plain git only.  Never pair this skill with
  worktree-based subagent isolation.

Shapes and detection signatures: `references/repo-shapes.md`.

## Preflight

Run `scripts/preflight.sh` once per `.jj` store, and again after any
fresh `jj git clone` or `jj git init` (repo-scoped config does not
survive into a new store).  It writes exactly four `--repo` keys (the
sanctioned exception to the no-config-mutation rule), asserts the
protected bookmark is actually immutable, fails closed when it cannot
resolve one, and hard-fails on a set `JJ_EDITOR` (which outranks
persisted config).  Read its one-line receipt.  Details and the
`trunk()` trap: `references/safety-net.md`.

## The pipeline

Ordered and non-reorderable:

```
preflight -> capture -> absorb -> partition -> fetch -> restack
          -> verify -> promote -> handoff
```

| Step | Command | Undo |
| :-- | :-- | :-- |
| Capture | automatic on any jj command; force with `jj status` at turn boundaries | n/a (append-only oplog) |
| Absorb | `scripts/absorb_safe.sh [paths]` (enforces the rules below) | `jj undo` |
| Partition | `jj split <paths> -m 'msg'` per concern | `jj undo` |
| Fetch | `jj git fetch` (ask-tier at work; receipt warns when skipped) | `jj undo` |
| Restack | `jj rebase -d 'trunk()'` | `jj undo` |
| Verify | `scripts/gate.sh -- <cmd>` | read-only |
| Promote | `scripts/promote.sh BOOKMARK [REV]` | `jj undo` (bookmark move); pushes are not undone |
| Handoff | `scripts/emit_handoff.sh` | read-only |

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

Default-on for routing late fixes into their owning ancestors.  Use
`scripts/absorb_safe.sh` -- it ENFORCES the three hard rules rather
than trusting memory: a pending rename (`R ` row) blocks bare absorb
(rename collateral silently rewrites an ancestor's file inventory);
destinations are always confined to
`mutable() & ~::remote_bookmarks()` (never rewrite what a reviewer
has seen); and every real absorb is followed by the residual check
plus `jj op show -p --summary` routing review.  Dry-run with
`--dry-run`.  Rates, rename signatures, precision forms:
`references/absorb.md`.

## Partition

File-grain only in v1: `jj split <paths> -m 'msg'`, one concern per
commit, refactor separated from behavior.  When one file carries two
concerns, hand off to a human -- no sub-file auto-partitioning ships
until the hunk-first classifier is proven.  Scope inference notes and
the v2 design constraints: `references/partition.md`.

## Rollback

Three granularities, all non-destructive; map intent to the narrowest:

- File content: `jj restore --from <rev> <path>`
- Last operation: `jj undo`
- Whole-repo time travel: `jj op restore <op-id>` (record op ids in
  the journal; `jj undo` is one-step-deep, not a checkpoint system)

Gate failure never triggers automatic rollback: the red state is the
evidence to inspect.

## Verify

`scripts/gate.sh -- <test cmd>`.  Ranged fail-fast by default with
exact failing-revision attribution; per-revision REPORT mode is
selected automatically when RED trailers are present.  The gate
command comes from the project's reviewed static set -- never compose
it from untrusted input, and never wrap `gh`/`pip`/`sbt` inside it.
Flag matrix and measured economics: `references/verify.md`.

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

`scripts/promote.sh BOOKMARK [REV]`.  Checks the gate receipt, scans
for RED trailers and undescribed ancestors (push rejects the whole
range, not just the target), moves the bookmark, dry-runs, pushes.
The autonomy ceiling is the PR: pushing a branch is automatic;
merging to the default branch is a human gate.  A nonzero push exit
is not proof the remote is unchanged -- the script re-queries
`remote_bookmarks()` and says so.

Bookmark names are descriptive: `feat/<topic>`, `fix/<topic>`,
`chore/<topic>`.  PR lifecycle: promote a clean, atomic series before
first submission; during active review, changes land as NEW commits
only -- absorb's destination set
(`mutable() & ~::remote_bookmarks()`) enforces this mechanically;
folding review-feedback commits into their targets after approval is
a history rewrite of reviewed commits and requires explicit user
authorization.

## Handoff

`scripts/emit_handoff.sh` writes `vcs-handoff/1` to
`<repo>/.local/state/agents/vcs/handoff.json` -- shape, preflight and
gate receipts, the stack with per-revision files, conflicts, and
message hints.  Hand off to `git-commit`: it is the CODEX -- the sole
authority on atomicity criteria, selection doctrine, message
structure, style, and trailers.  This skill prepares revisions to its
standard and supplies the jj-shape serialization mechanics
(`references/serialization.md`); it never overrides the codex and
never composes message text.  Schemas: `references/receipts.md`.

## Journal

One YAML block per promotion (never per capture): op-id and change-id
pointers only.  The oplog is the truth; the journal is the index into
it.  Any entry that cannot be reconstructed from `jj op log` is
malformed.

## git-only mode

Supported, reduced, higher-risk: no auto-capture (an `rm -rf`'d
worktree loses un-added work completely), hunk staging via
`scripts/git_diff_safe.sh` + `scripts/git_only_hunks.awk` +
`git apply --cached --unidiff-zero`, fixups with a deferred
user-gated autosquash, per-revision verification via
`git rebase --exec`.  Unattended runs are a NO-GO in this mode.
Full recipes: `references/git-only.md`.

## Toolchain

Pins and drift: `scripts/compat_probe.sh` (scheduled via pitchfork
where available; preflight reads its receipt).  Drift remediation:
`scripts/gh_recover.sh`.  First install on a locked-down host:
`scripts/bootstrap_work.sh` -- gh-first, fail-closed integrity, zero
mise security changes; agent-issued or run manually in a plain
terminal, same receipts either way.  `references/bootstrap-locked.md`.

## Forbidden vocabulary

`--ignore-errors`; `--allow-conflicts`; `--ignore-immutable`; bare
`jj resolve`; bare `jj describe`/`squash`/`split` (always `-m`,
`--stdin`, `--tool`, or an explicit fileset); `--clean` outside the
designated final gate; `git add -A` / `git add .` / `git commit -a`;
file-targeting `git checkout --` / `git restore` / `git stash` /
`git clean` / `git reset` in a colocated shape; `pip install jj` /
`jujutsu` / `cog` (PyPI namesquats); any mise security toggle
(`MISE_AQUA_GITHUB_ATTESTATIONS=false` first among them); `gh` /
`pip` / `pip3` / `sbt` nested inside `jj run --` or
`git rebase --exec`.

## Traps

The silent-failure catalogue lives in `references/traps.md`.  The five
highest-risk classes: a jj revset handed to git (exit 128, looks like
an empty diff one unchecked call site up -- use
`scripts/git_diff_safe.sh`); `jj run` without `--ignore-changes`
(silently amends the gated revisions); the worktree shadow; rename
collateral under bare absorb; and `git restore` against an open `@`.
