# Onboarding a git repository to jj

Ask only when `detect_shape.sh` reports `git-only` and
`onboard.sh status` reports `undecided`.  A headless session has no
interactive question tool and never converts: run the session in plain
git and say so with `ONBOARD-PENDING`, which is the agent's own line for
that case, not a receipt any script emits.  An agent-invoked entry never
re-asks once a decision is recorded.

## The two questions

Claude Code asks with `AskUserQuestion`, Pi with `ask_user_question`.
The text is the same either way.

Q1, header `Convert?`: "Convert this repository to jj?  jj becomes a
private local operations log: granular capture, `jj undo`, and rollback
while work is open.  Published history stays git."

| Answer | Effect |
| :-- | :-- |
| `Yes` | Ask Q2, then `onboard.sh apply --level <answer>`. |
| `Not now` | Nothing is recorded; ask again next session. |
| `No, keep plain git` | `onboard.sh record --decline`; only a user invocation re-asks. |

Q2, header `Level`, asked only after `Yes`: "Which conversion level fits
this repository?  The level matches who owns it."

| Level | Fits | What it does | What stays git |
| :-- | :-- | :-- | :-- |
| `oplog` | Third-party checkouts, patches to repos you do not own. | Colocated store for capture and rollback only: `jj undo`, `jj restore`, `jj op restore`.  Preflight writes the three safety keys.  jj never describes, pushes, or moves bookmarks. | Every commit and push is plain git through `git-commit`, so the repo's hooks keep firing and nothing jj-shaped reaches a reviewer. |
| `standard` | Collaborative repos with group conventions. | Full pipeline: absorb, split, `gate.sh`, `jj describe --stdin`, and `jj git push --bookmark`.  `snapshot.auto-track = "none"`, so only files explicitly `jj file track`ed can publish.  `gate.sh` runs the project's hook command, because git hooks do not fire under jj. | Remote history is ordinary git branches; nothing tracked changes. |
| `full` | Private repos. | `standard` plus jj's default `snapshot.auto-track` (`all()`), absorb default-on, workspace isolation, and journal by op-id. | Same. |

## What gets recorded

`onboard.sh` writes three keys with `git config --local`, in the repo's
own `.git/config`: never pushed, invisible to reviewers, and no file
appears in the working tree.

| Key | Value |
| :-- | :-- |
| `vcs-workflow.onboarding` | `converted` or `declined` |
| `vcs-workflow.level` | `oplog`, `standard`, or `full` |
| `vcs-workflow.decided` | ISO date, UTC |

The jj-side keys the level needs go to `--repo` scope through
`preflight.sh`, under `~/.config/jj/repos/`, also outside the tree.

A secondary workspace holds no keys of its own; `status` reports the
primary's decision, so a workspace of an `oplog` repo reads `oplog`.

## Consequences to state before converting

Measured in a fixture against the installed jj and git, never inferred
from their documentation:

- `.jj/` is self-ignored.  The store writes `.jj/.gitignore` containing
  `/*`, so `git status --porcelain` stays empty and no `.gitignore` edit
  is needed.
- Git `HEAD` follows the parent of `@`.  While `@`'s parent is the
  bookmarked commit, `HEAD` stays attached (still `refs/heads/main`
  after `jj git init --colocate` and after an edit).  The first `jj new`
  moves `@` onto a fresh child, and `HEAD` then detaches at the unnamed
  parent commit.  Re-attach with `git switch <branch>` before handing
  the checkout back to git tooling.
- jj adds local refs and objects: one `refs/jj/keep/<commit>` per commit
  it retains.  No push carries them unless a bookmark points at them.
- jj snapshots the whole working copy, so at level `standard` and `full`
  `apply` ensures `.local/` and `.cache/` are ignored, appending any
  missing pattern to the local, unpushed `.git/info/exclude` and never
  to `.gitignore`; it then warns `exclude-added`.  Level `oplog` writes
  nothing.

## Changing level, and overriding a decline

- Change level: `onboard.sh apply --level <new>`.  It rewrites only the
  `--repo` keys through preflight and the recorded level key.  It never
  removes the store, downgrades included.
- Override a decline: a user invocation ("convert this repo", "change
  the jj level", `/vcs-workflow`) runs `onboard.sh reset`, which removes
  the whole `vcs-workflow` section and never touches the store, then
  asks both questions again.
- A refusal (`ONBOARD-REFUSE reason=<...>`) is the user's to resolve.
  The detail and the remedies go to stderr; `onboard.sh` never runs the
  remedy for them.  Every precheck refuses before a store exists, so a
  refused repository is never half converted.  Four reasons name the
  caller's own state rather than the repository's:

| Reason | Meaning |
| :-- | :-- |
| `jj-editor` | `JJ_EDITOR` is set to something other than `:true`.  It outranks the `--repo` editor keys, so unset it and re-run. |
| `no-git-config level=<L\|->` | A jj-only repo has no git config to record a decision in; only `--level full` applies there, and `record --decline` is refused for the same reason. |
| `protected-bookmark-name` | `PREFLIGHT_PROTECTED_BOOKMARKS` carries a name outside `A-Za-z0-9._/+-`.  `preflight.sh` interpolates each name into a revset literal and refuses anything else, so onboarding refuses it first, before a store exists. |
| `preflight store-created=<yes\|no>` | The prechecks passed and `preflight.sh` still failed.  The flag says whether this run left a store behind; `exclude-write` and `config-write` carry it too. |
