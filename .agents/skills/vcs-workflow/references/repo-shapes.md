# Repo shapes

`scripts/detect_shape.sh` classifies the working directory into one of
five shapes before any other script or jj command runs.  Invariant 1:
no jj command -- reads included -- runs before it returns `colocated`,
`jj-only`, or `jj-workspace`; `worktree-shadowed` means plain git only,
full stop.  Detection is structural (two commands, not a config read),
so it cannot be fooled by stale state:

```sh
_git_top=$(git rev-parse --show-toplevel 2>/dev/null) || _git_top=''
_jj_root=$(jj root 2>/dev/null) || _jj_root=''
```

Check order, exactly as shipped (later branches are unreachable once
an earlier one matches):

1. Both resolve and disagree -> `worktree-shadowed`, exit 3.
2. `$_jj_root` resolves -> test `$_jj_root/.git`, then
   `$_jj_root/.jj/repo`, in that order -> `colocated` / `jj-workspace`
   / `jj-only`, exit 0.
3. Only `$_git_top` resolves -> `git-only`, exit 0.
4. Neither resolves -> `none`, exit 2.

The `.jj/repo` test is file-vs-directory, never `-L`: a secondary
workspace's `.jj/repo` is a one-line pointer FILE holding a relative
path string to the primary's store, not a symlink.

## The five shapes

| Shape | Signature | Exit | Permitted |
| :-- | :-- | :-- | :-- |
| `colocated` | `$_jj_root` resolves, equals `$_git_top`, and `$_jj_root/.git` exists | 0 | Full pipeline.  Native `git diff`/`show`/`log` work through `scripts/git_diff_safe.sh` (invariant 17); the lazy-export mechanic below and the file-targeting git-command ban (invariant 19) apply only here, because this is the only shape with a live git index next to `.jj`. |
| `jj-only` | `$_jj_root` resolves, no `.git` there, `.jj/repo` is a directory (not a file) | 0 | Full pipeline.  No live git working tree exists, so the file-targeting git-command ban and the lazy-export mechanic are moot -- there is nothing for them to hit. |
| `jj-workspace` | `$_jj_root` resolves (the secondary's own directory, distinct from the primary's), `.jj/repo` there is a FILE | 0 | Full pipeline.  Preflight's `--repo`-scoped config resolves through the pointer file to the primary's `config-id`, so a workspace never needs its own preflight run -- only that the underlying store has had one (invariant 2). |
| `git-only` | `$_jj_root` empty, `$_git_top` resolves | 0 | Reduced mode, not a peer: hunk-grain staging (`git_diff_safe.sh` + `git_only_hunks.awk` + `git apply --cached --unidiff-zero`), fixup accumulation with deferred autosquash, `git rebase --exec` per-revision verify.  No absorb equivalent, no oplog rollback tiers, no classifier partitioning.  Unattended/overnight runs are a no-go: an `rm -rf`'d worktree loses never-`git add`ed content completely, and `git add`ed content survives only as an anonymous, path-less, GC-eligible dangling blob.  Full recipe: `references/git-only.md`. |
| `worktree-shadowed` | `$_jj_root` and `$_git_top` both resolve and **disagree** | 3 | Nothing for jj, reads included.  Plain git only.  Never pair this skill with worktree-based subagent isolation. |
| `none` | neither resolves | 2 | Skill does not apply. |

## Nested vs. sibling worktrees

A git worktree of a colocated (or jj-only) repo has no `.jj/` of its
own -- the shadow risk turns entirely on *where* that worktree sits
relative to the parent's directory tree, and the two placements fail
in opposite ways.

**Nested** -- this harness's own `EnterWorktree`/`ExitWorktree` tools
(also `--worktree`, `isolation:"worktree"`, background sessions) place
the worktree inside the parent checkout's own directory tree.
`git rev-parse --show-toplevel` is worktree-metadata-aware and
correctly resolves to the nested worktree's own root; `jj root` is
not -- it walks up the filesystem looking for the nearest `.jj`, finds
none in the worktree itself, keeps walking past the worktree boundary,
and lands on the PARENT's `.jj`.  That disagreement is exactly the
`worktree-shadowed` signature above.  Left undetected, the failure is
silent and structural, not cosmetic: in the wave-3 reproduction,
`jj status` reported the PARENT's own uncommitted file as
`A ../parent-inprogress.txt` while the nested worktree's real edits
never appeared as changed at all, and a subsequent `jj describe`
committed that parent file under the agent's message.  jj was not
confused about the worktree -- it never knew the worktree existed and
was answering, correctly, for a different directory.  A second trap
compounds it: `ExitWorktree` with `discard_changes: true` trusts a
git-level dirty check that is correct, but an agent that instead
trusts jj's report (wrong, because jj never saw this directory) and
forces the discard destroys the work permanently -- jj recorded no
operation for it, so there is nothing for `jj undo` to restore.  Never
pair vcs-workflow with worktree-based subagent isolation; this is why.

**Sibling** -- a plain `git worktree add ../foo` placed outside the
parent's directory tree fails loud instead.  Walking up from inside it
never reaches the parent's `.jj` at all, so a bare jj command errors
immediately: `Error: There is no jj repo in "."`.  Run through
`detect_shape.sh`, `$_jj_root` is simply empty (no mismatch to
detect), and the script falls through to `git-only`, exit 0 -- a
correct, safe classification, not a near miss.  The sibling case is
self-diagnosing; the nested case is the one this script exists for.

## The colocated lazy-export mechanic

Applies only to `colocated`.  jj is the source of truth there; the
git side (index and objects) is a lazily-maintained *export* of jj's
state, not a live mirror kept in lockstep.  For a file belonging to
the still-open `@` commit -- one `jj new` has not yet finalized -- the
git index holds the well-known empty blob (`e69de29b...`, 0 bytes)
regardless of how many real jj snapshots have already captured content
for that file: jj does not export real blob content for an open
commit into the git side until finalization closes it.

The consequence is invariant 19 and traps.md item 12: `git checkout --
<path>` or `git restore <path>` reads from the git side, so it reverts
straight to the last-*finalized* parent, discarding the open commit's
entire in-progress diff -- past however many captured jj snapshots
plus any uncaptured edit -- silently, with no error and no warning.
Because git wrote the working file directly, jj has no operation
recording the loss, so `jj undo` cannot recover it either.  The
jj-native substitute, `jj restore --from <rev> <path>`, has identical
destructive intent but runs through jj, which auto-snapshots the
pre-restore state first -- so the same mistake through the jj command
is one `jj undo` away from full recovery.  This is why both git forms
join the forbidden vocabulary in a colocated shape specifically:
elsewhere there is no git index for them to silently read from.
