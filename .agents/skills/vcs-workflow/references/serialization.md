# Serialization: the clerk

The `git-commit` skill is the CODEX: the sole authority on what a
published commit is -- atomicity criteria, logical selection, message
structure, RCA/ADR body depth, style, trailers, and tracking
references.  Read it and satisfy it; nothing here overrides it.

This reference is the CLERK: the shape-specific mechanics of getting a
codex-conformant message attached to a revision.  It exists because
two measured facts prevent the codex's git-only mechanics from running
verbatim under jj shapes, not because any of its judgment moved.

Fact 1: any jj working-copy update erases the git index, so
`git add`-based selection cannot survive in a jj-managed repo.  The
codex's selection DOCTRINE (SRP, one logical change, hunk-level care,
no bulk staging, no secrets) still governs -- it is executed with
`jj split <paths> -m` and `jj absorb` upstream in this skill's
pipeline, and the result is judged against the codex before
serialization.

Fact 2: no message-gating git hook fires under jj authorship
(commit-msg, pre-commit, and post-commit are all bypassed), so
hook-based enforcement of the codex must be replaced by explicit
validation before serializing.

## Serializing per shape

The published result is byte-identical either way: `jj describe
--stdin` and `git commit -F` were `cmp`-verified equal across
multi-paragraph bodies, 72-column wraps, `BREAKING-CHANGE:` footers,
multiple trailers, and UTF-8.  The published log stays a traditional
git log; jj is the writing instrument, never the artifact.

```sh
# jj shapes (colocated, jj-only, jj-workspace): describe the revision
jj describe -r <rev> --stdin < "$MSG_FILE"

# git-only shape: exactly as the codex documents
git commit -F "$MSG_FILE"
```

Undo for a wrong description: `jj undo` (or
`jj describe -r <rev> --stdin < corrected.txt`).

## Pre-serialization checklist (jj shapes)

1. **Validate the drafted message against the codex** with a
   deterministic exit code -- no hook will do it for you.  Where
   `cog` (cocogitto) is installed, `cog verify --file "$MSG_FILE"`;
   otherwise check header shape, length caps, trailer form, and body
   wrap explicitly against the codex's rules.
2. **Compose in a file or quoted heredoc, never double-quoted `-m`**:
   backticks and `$` execute under double quotes, and codex-style
   bodies contain backticked identifiers routinely.
3. **`test -s "$MSG_FILE"`** -- empty stdin silently WIPES an
   existing description.
4. **Identity**: `jj config get user.name` and `user.email` must be
   non-empty.  jj never falls back to a colocated repo's
   `git config`; unset identity commits as the literal
   `JJ_EMPTY_STRING`, with only a warning.
5. **Hygiene is the author's job**: jj stores message bytes verbatim
   plus exactly one trailing newline.  Strip leading and trailing
   blank lines, collapse mid-message blank runs, rstrip each line,
   and normalize CRLF to LF -- the cleanup git used to apply for
   free.
6. **Read `handoff.json`** (`references/receipts.md`) for the
   prepared stack, per-revision files, and scope hints -- the
   selection work already performed under the codex's criteria.
   Judge it; refuse to serialize what fails the codex.

## Reserved trailer

`Verification-Status:` is reserved; `red-expected` is its only legal
value (the intra-session RED checkpoint marker from this skill's
pipeline).  It must never reach a PR -- `promote.sh` rejects any
range carrying it.

## Hook reality

The one git hook that still fires under jj is `reference-transaction`,
and only on push: a failing one makes `jj git push` report failure
AFTER the remote has already updated.  Re-query `remote_bookmarks()`
before retrying (promote.sh does this).

## Odds and ends

- `git.write-change-id-header=false` (repo scope) when raw
  commit-object schema equality with plain git matters: jj injects a
  `change-id` pseudo-header, invisible to `git log --format=%B`,
  visible to `git cat-file -p`.
- `/commit` routes to `git-commit` (the codex and executor).  This
  reference only supplies the jj-shape mechanics when git-commit
  serializes inside a jj repo.
- History-rewriting scope under jj: restacking unpushed, mutable work
  is normal and oplog-reversible; `immutable_heads()` mechanically
  fences published history (see `references/safety-net.md`).  The
  codex's prohibitions on automatic rebase and force-push stand
  untouched for published commits.
