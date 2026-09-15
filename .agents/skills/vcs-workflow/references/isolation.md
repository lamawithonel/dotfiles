# Isolation: jj workspaces, not git worktrees

## Facts

A jj workspace has its own working copy and `.jj`, and no `.git`:
`detect_shape.sh` answers `jj-workspace` and git has nothing to read.
jj does not support git worktrees: a linked worktree NESTED under a
colocated repo is the `worktree-shadowed` shape, where `jj root`
resolves to the parent checkout and every jj command -- reads included
-- acts on the parent's files.  A SIBLING linked worktree is plain
`git-only`: `jj git init --colocate` refuses inside it.  One directory
cannot be both, so isolation picks the workspace, the side that keeps
capture.

## Hook contract

`scripts/workspace_hook.sh` answers Claude Code's `WorktreeCreate` and
`WorktreeRemove`, which fire for `--worktree`, for agents declared
`isolation: "worktree"`, and for background sessions.  Register it
once, for both events:

```json
"WorktreeCreate": [{"hooks": [{"type": "command",
  "command": "/home/lucas/.agents/skills/vcs-workflow/scripts/workspace_hook.sh"}]}],
"WorktreeRemove": [{"hooks": [{"type": "command",
  "command": "/home/lucas/.agents/skills/vcs-workflow/scripts/workspace_hook.sh"}]}]
```

Stdin is one JSON object: `session_id`, `hook_event_name`,
`worktree_path`, and `cwd`.  Only the BASENAME of `worktree_path` is
used, as the workspace name: Claude Code proposes
`.claude/worktrees/<name>` inside the repo -- the shadowed shape -- on
create and on remove alike, so both events discard the proposed path
and rebuild the directory from `cwd`; only a remove target that already
sits under the workspaces root is taken as given.  The workspace lands
at
`${XDG_DATA_HOME:-$HOME/.local/share}/agents/jj-workspaces/<slug>/<name>`,
`<slug>` being the primary's basename plus eight hex digits of the
sha256 of its physical path.  On create, stdout carries the workspace
directory and nothing else, and Claude Code enters the directory the
hook printed; receipts, warnings, and jj chatter stay on stderr.  Claude
Code refuses a hook directory that resolves inside ANY git repo, so the
hook proves the target is outside one before asking jj.  It processes
`.worktreeinclude` only for worktrees it creates itself, so the hook
reads `<primary>/.worktreeinclude` and symlinks each entry that exists
into the workspace, warning on a missing one.  `${CLAUDE_PROJECT_DIR}`
keeps pointing at the launch directory (the primary) while `cwd`
follows the session into the workspace, so anything that must act on
the primary uses it.  Claude Code's stale-worktree sweep never removes
these; cleanup is the remove event or a person.  Create is resumable: a
registered workspace whose directory is still present is refreshed with
`jj workspace update-stale` and its path reprinted, so a reconnecting
session lands on the same directory.

Refusals print `WORKSPACE-HOOK-FAIL reason=<r>` and exit 1; unusable
stdin or an unknown event is exit 2, and nothing ever falls back to a
git worktree:

- `needs-onboarding` -- the shape at `cwd` is neither `colocated` nor
  `jj-only`.
- `level-oplog` -- isolation is a `standard` or `full` step.
- `primary-unresolved` -- no primary root resolves behind `cwd`.
- `target-unwritable` -- the slug directory cannot be created.
- `target-in-git-repo` -- the workspaces root resolves inside a git
  repo, which both jj and Claude Code refuse.
- `orphan-directory` -- the directory is there, the registration is not.
- `update-stale-failed` -- the resume refresh failed.
- `add-failed` -- `jj workspace add` failed.
- `refused-path` -- the remove target is outside the workspaces root
  and no primary is reachable from `cwd` to rebuild it from.
- `snapshot-failed` -- `jj status` could not capture the workspace.
- `forget-failed` -- `jj workspace forget` failed.
- `remove-failed` -- `rm -rf` failed.

## What a workspace can and cannot do

Every jj operation reaches the shared repo from any workspace:
`jj describe --stdin`, `jj absorb`, `gate.sh`, and `jj git push
--bookmark` all work from a secondary workspace, and a bookmark pushed
there is the same bookmark everywhere.  `gh` does not: it reads the
CWD's git remote, which a workspace has none of, so every `gh` call
needs `-R <owner>/<repo>` and `--head <branch>`.  `@` is PER WORKSPACE,
so a revset meaning "my work" means something else in the next one:
name change ids or bookmarks in anything that crosses the boundary.  A
working copy left behind by a concurrent operation is stale until
`jj workspace update-stale`, which the hook runs on every resume.
`herdr worktree` is git-only: open a workspace as a plain
`herdr workspace`.

## Cleanup order

Snapshot, forget, then delete -- in that order, never delete first.
`jj -R <dir> status` captures whatever the workspace still holds, so an
interrupted session stays recoverable from the primary's `jj op log`;
`jj -R <primary> workspace forget <name>` drops the registration but
keeps the captured commit; `rm -rf` removes the directory.  A failed
snapshot or a failed forget keeps the directory and exits 1: a deleted
directory whose registration survives holds the name hostage.  A
directory that is already gone still gets the forget, reported as
`state=absent`.  With the primary gone there is nothing to capture
into: the hook warns, skips both jj steps, and deletes.

## Mid-session EnterWorktree

Measured 2026-09-15 in gentoo-overlay: the `EnterWorktree` tool does
route through `WorktreeCreate`, but its stdin JSON carries a `name`
field and no `worktree_path`.  The hook accepts either; on neither it
refuses with `reason=bad-input keys=[...]` listing what it received, so
a future change to the tool's input shape is diagnosed from the
receipt.  With that fix the session landed under the workspaces root
with shape `jj-workspace`.

## Sandbox: the shared store is outside the workspace

Every snapshot from a workspace writes into the PRIMARY's `.jj` and
`.git/objects`; that is the design, exactly as a git worktree writes
into the shared `.git`.  Claude Code's sandbox allows those shared
writes for git worktrees it created itself, but a hook-created jj
workspace moves the session's write set to the workspace alone, so
`jj status` there fails with "Read-only file system" on
`<primary>/.git/objects` (measured 2026-09-15).  Until the sandbox's
filesystem allow list covers the primary's store, jj commands inside a
hook-created workspace run with the sandbox disabled, through the
session's own permission gate.
