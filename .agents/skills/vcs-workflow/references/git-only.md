# Git-only fallback

`detect_shape.sh` returns `git-only` when no `.jj` root resolves.
Three repositories stay here: one where jj is absent from the host,
one that is a linked git worktree (`jj git init --colocate` refuses
inside one, and a nested one is the shadowed shape), and one where the
user declined conversion (`vcs-workflow.onboarding = declined`).  This
is a floor, not a peer of the jj-backed shapes.

**Unavailable.**  No capture, so nothing for `jj undo`, `jj restore`,
or `jj op restore` to read; no absorb, no `jj split`; and `gate.sh`,
`promote.sh`, `absorb_safe.sh`, and `emit_handoff.sh` all refuse.
`scripts/git_diff_safe.sh` is the only script of this skill that runs
here -- use it for every `git diff`, `show`, and `log` read, because
it pins `core.quotePath=false` and checks the exit code a bare call
swallows.  There is no hunk kit: select by explicit path, never
`git add -A`, `git add .`, or `git commit -a`.

**Commit often.**  Content never `git add`ed is gone completely on an
`rm -rf`, absent even from `git fsck --unreachable`; content that was
`git add`ed survives only as an anonymous, path-less, GC-eligible
dangling blob.  Because the worst case is total loss and the best case
is unlabeled forensic debris, unattended or overnight autonomous runs
are a no-go here, and commits land far more often than a jj-backed
agent would need.  Every one goes through `git-commit`, the authority
on atomicity and message bytes in this shape exactly as in the others.

**Verify with the project's own gate command** -- the reviewed static
one its `hk.pkl`, `mise.toml`, or contributing guide names -- once per
revision: `git rebase --exec '<gate cmd>' <base>`.  It stops at the
failing commit, `git rev-parse HEAD` names it
(`.git/rebase-merge/stopped-sha` does not exist for `--exec`
failures), and `git rebase --abort` restores the original history
unconditionally.  Never nest `gh`, `pip`, `pip3`, or `sbt` inside the
`--exec` string.

**Isolate in a jj workspace taken off a repository that already has a
store** (`references/isolation.md`), or run the work serially in this
checkout.  A git worktree of this repository cannot take a store of
its own, and a nested one shadows whatever parent does have one.

**Force-push:** `--force-with-lease` only, never bare `--force`, and
only after explicit user confirmation.  There is no clean undo once
the remote accepts one; confirmation is the safeguard, not a recovery
step.
