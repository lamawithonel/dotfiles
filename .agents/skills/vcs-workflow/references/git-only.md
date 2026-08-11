# Git-Only Mode

`detect_shape.sh` returns `git-only` when no `.jj` root resolves.
This mode is a supported, reduced, explicitly higher-risk floor, not
a peer of the jj-backed shapes (D1.9).  It trades away auto-capture
and one-command hunk routing for plain git primitives; verify every
step below, because none of it fails loud by default.

## Scope

In scope: hunk-grain staging, fixup accumulation with a deferred
autosquash handoff, per-revision verification, and worktree
isolation.  Out of scope: an absorb equivalent, oplog rollback
tiers, and any classifier-driven partitioning (D1.9).

## Hunk-grain staging (TTY-free)

git's only hunk primitive, `git add -p`, is TTY-only.  The shipped
substitute:

    mkdir -p "$OUT_DIR"
    scripts/git_diff_safe.sh diff -U0 |
      awk -v dir="$OUT_DIR" -f scripts/git_only_hunks.awk

`git_only_hunks.awk` splits the stream into one `hunk-NNN.patch` per
`@@` block, each carrying its own `diff --git` / `index` / `---` /
`+++` header, so every hunk applies independently.  It handles
multiple files in one stream (a new `diff --git` header resets the
per-file context) and skips binary diffs with a warning to stderr
instead of emitting a broken patch.  It prints the hunk count on
stdout.

Apply one hunk at a time:

    git apply --cached --unidiff-zero "$OUT_DIR/hunk-001.patch"
    git diff --cached                     # verify, every time

**Fuzzy-relocation trap**: `--unidiff-zero` relocates a `-U0` hunk by
searching for its context, not by trusting the stored line number.
Verified correct against +1 and +4 line drift from intervening
commits, but a file with duplicated surrounding lines can still
mis-place a hunk silently.  `git diff --cached` after every apply is
not optional -- it is the only check that catches a wrong placement
before it is committed.

Undo a bad apply before committing:

    git apply --cached -R --unidiff-zero "$OUT_DIR/hunk-001.patch"

After committing: `git reset --soft HEAD~1`.

New (untracked) files carry no diff for the splitter to see; stage
them individually by explicit path.  **Invariant 9**: the staging
path never emits `git add` with `-A`, `.`, or `-a` -- the path greps
its own command line and refuses.  Tool-enforced, not a style
preference.

## Fixup accumulation, deferred autosquash

Accumulate fixes against already-committed hunks without touching
history:

    git commit --fixup=<target-sha>

This produces a `fixup! <target subject>` commit on top of the
stack; the working tree stays clean and no rebase runs.  Undo:
`git reset --soft HEAD~1` removes the fixup commit and re-stages its
content.

Folding the fixups is a **separate, user-gated, deferred step** --
do not run it automatically:

    GIT_SEQUENCE_EDITOR=true git rebase --autosquash <base>

No literal `-i`: git's own docs confirm `--autosquash` "uses the
--interactive machinery internally, but it can be run without an
explicit --interactive."  Only `GIT_SEQUENCE_EDITOR` needs
neutralizing -- `--fixup=` commits fold silently without opening the
message editor, unlike `--squash=`, which this workflow never
emits.  At work, `git rebase --exec` and `git rebase --autosquash`
are both unlisted in the permission profile and therefore ask-gated
on every invocation; that is acceptable here precisely because the
handoff is rare and deliberate, never looped.

Undo after a completed autosquash: `git reset --hard ORIG_HEAD` (git
sets `ORIG_HEAD` to the pre-rebase tip on every rebase).  Mid-rebase,
use `git rebase --abort` instead.

## Per-revision verification (`git rebase --exec`)

`gate.sh` refuses outright in this shape
(`GATE-FAIL shape=git-only`) and points here.  Run the project's
test command directly, once per revision in the range:

    git rebase --exec '<test-cmd>' <base>

Validated as load-bearing (D1.9, `[A9-amended]`): it stops at
exactly the failing commit, and `git rebase --abort` cleanly
restores the original history.

**Attribution correction**: `.git/rebase-merge/stopped-sha` does
**not** exist for `--exec` failures -- only for pick/apply
conflicts.  Because the failing commit is already picked and checked
out by the time its `exec` runs, `git rev-parse HEAD` names it
directly.  Cross-check (or use when `HEAD` is ambiguous) by reading
the last `pick` line preceding the failed `exec` line in
`.git/rebase-merge/done`.

Recovery is unconditional: `git rebase --abort`.  There is no
partial-success state to salvage -- abort and re-run after fixing
the underlying failure.

Never nest `gh`, `pip`, `pip3`, or `sbt` inside the `--exec` string:
the wrapper strips the sandbox exemption from anything it shells out
to, and a compound `--exec` command (anything with `&&`, `;`, and
similar) runs as a `/bin/sh -c` child of git, never as a literal
token the permission layer can re-match.  Issue those as their own
top-level Bash command instead.

## Worktree isolation and crash recovery

Isolate concurrent agent work with `git worktree`, driven through
the harness's `EnterWorktree` / `ExitWorktree` tools, never raw
`git worktree` / `rm -rf` Bash calls -- those tools carry their own
permission surface and keep worktree bookkeeping from fighting the
Bash allow/deny lists.

Cheat sheet, five crash scenarios, all verified live:

| Symptom | Recovery | Outcome |
| :-- | :-- | :-- |
| Stale `index.lock` after a crashed process; writes fail, reads still work | Confirm nothing holds it (`ps aux \| grep '[g]it'`), then `rm -f "$(git rev-parse --git-dir)/index.lock"` | Writes resume; no auto-recovery exists |
| Worktree directory `rm -rf`'d (disk wipe, container recycle) | `git worktree list` flags it `prunable`; `git worktree prune -v` | Branch ref survives; see durability caveats below for the content |
| Worktree directory moved, not deleted | `git worktree repair` from the new location | One command, no data loss |
| Need to protect bookkeeping during risky work | `git worktree lock <path> --reason '<why>'` | Survives even if the directory is later deleted; undo with `git worktree unlock <path>` |
| Removing a locked worktree on purpose | `git worktree remove --force --force <path>` | Destructive; no undo -- this is what the lock was guarding against |

## Durability caveats -- unattended runs are a NO-GO

There is **no auto-capture** in this mode.  Nothing is safe until it
is on disk *and* `git add`ed, and even that floor is thin:

- Content never `git add`ed: gone completely on `rm -rf`.  Absent
  even from `git fsck --unreachable`.
- Content that was `git add`ed: survives only as an anonymous,
  path-less, message-less, default-GC-eligible dangling blob
  (`git fsck --unreachable --no-reflogs`, then `git cat-file -p
  <sha>` for forensic-only recovery -- no filename, no message, no
  author).

Because the worst case is total loss and the best case is unlabeled
forensic debris, **unattended or overnight autonomous runs are a
no-go in git-only mode.**  Commit far more aggressively than a
jj-backed agent would need to; every fixup commit above is cheap
insurance against exactly this.

## Force-push rules

`--force-with-lease` only, never bare `--force`, and only after
explicit user confirmation -- carried forward from the retired
`GIT_WORKFLOW_RULES.md`.  jj shapes need no equivalent rule because
`jj git push` has no force flag at all.  There is no clean undo once
the remote accepts a force-push; confirmation is the safeguard, not
a recovery step.
