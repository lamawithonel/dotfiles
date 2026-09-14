# Traps

The consolidated silent-failure catalogue.  Every entry fails without
an error, a nonzero exit, or any other signal that would normally stop
an agent -- that is the qualifying bar for inclusion here.  Loud
failures (a real nonzero exit, a real exception) are not traps; they
are just errors, and the caller already handles them.

Entries 1-22 are the original catalogue, numbered as settled in the
design decisions; entries 23-27 were found while building the scripts
under `scripts/`.  The catalogue carries 21 live entries.  Where a
shipped script encodes the mitigation, the entry cites the exact file
and the line or claim name, so a 3am reader can jump straight to the
fix instead of trusting this prose.

Numbers are stable identifiers, not positions.  2, 3, 8, 15, 20, and
21 retired with the ast-grep, difftastic, mise, and hunk-splitting
tooling; those numbers are not reused.

## 1-22: the original catalogue

1. **A jj revset handed to git.**  `git diff -U0 @-` in a colocated
   repo exits 128 with empty stdout (rc=0 only when piped through
   `cat`, which swallows the real exit code); the actual defect is an
   unchecked subprocess return code one call site above the git
   invocation.  Fix: resolve the revset to a commit id first
   (`jj log -r <revset> --no-graph -T commit_id`) and assert
   `returncode == 0`.  Encoded in `scripts/git_diff_safe.sh:36-42`,
   the single sanctioned entry point for hardened git reads.

4. **`--ignore-errors` on `jj run`.**  Zeroes the exit code on a real
   failure and deletes the `Hint: Failed revision:` attribution the
   caller needs to find what broke.  Fix: never pass it.  Enforced by
   omission in `scripts/gate.sh` -- neither of its two `jj run` calls
   carries the flag, and the script header names it explicitly as a
   documented invariant.

5. **`description("text")` is glob-matched.**  A bare string in a
   `description()` revset filter is parsed as a `glob:` pattern and
   silently returns zero results against a message with no glob
   metacharacters that still doesn't match literally. Fix: use
   `description(substring:"...")`.  Applied in every RED-trailer
   lookup in `scripts/gate.sh` and `scripts/promote.sh`, and
   re-checked live by the `revset-description-substring` claim in
   `scripts/compat_probe.sh`.

6. **Empty stdin silently wipes a description.**
   `printf '' | jj describe --stdin` clears the commit message with no
   error and no warning.  Fix: assert `test -s "$MSG_FILE"` before
   piping it in.  No vcs-workflow script calls `jj describe --stdin`
   directly (that call site belongs to the `git-commit` skill); the
   guard is the caller's responsibility at the point of use.

7. **`JJ_EMPTY_STRING` identity.**  jj resolves author and committer
   identity only from its own config layers and does not fall back to
   a colocated repo's `git config`.  With jj identity unset, it
   committed as the literal string `JJ_EMPTY_STRING`, backed by a
   warning rather than a failure -- easy to miss in a busy log. Fix:
   verify `jj config get user.name` / `user.email` resolve to real
   values before the first commit in a fresh clone.

9. **Worktree shadow.**  A harness-created nested worktree has no
   `.jj/` of its own, so jj walks up the filesystem and answers for the
   *parent* repo: it reports and can commit the parent's uncommitted
   files under the agent's message, while the worktree's own changes
   never appear.  A sibling (non-nested) worktree fails loudly instead
   (`Error: There is no jj repo in "."`), so the silent-danger mode is
   specific to the nested case.  Fix: `scripts/detect_shape.sh`
   compares `jj root` against `git rev-parse --show-toplevel`, both
   resolved to physical paths so a symlinked root is not a false
   positive; a
   mismatch is `worktree-shadowed`, exit 3, hard stop -- no jj command
   may run, reads included.  Do not reach for a git worktree to
   isolate a subagent; isolate with jj workspaces instead
   (`references/isolation.md`).  A worktree cannot be converted out of
   the trap either: `jj git init --colocate` refuses inside any linked
   git worktree, loudly.

10. **`core.quotePath` octal-escapes non-ASCII filenames.**  git's
    default `core.quotePath=true` renders a diff header as
    `+++ "b/py/caf\303\251_util.py"`; a parser that naively extracts
    the path string dies with `KeyError: None` or worse, silently
    matches the wrong file.  Fix: `-c core.quotePath=false`, or
    NUL-delimited `-z` extraction.  Applied unconditionally by
    `scripts/git_diff_safe.sh:36` -- the single sanctioned entry point
    for hardened `git diff` / `show` / `log` reads.

11. **Line-ending divergence, two forms.**  LF/CRLF drift between the
    old and new sides of a diff inflates ordinary hunks into
    whole-symbol rewrites, burying the real change; separately, on a
    message containing `\r\n`, `git commit -F` strips the `\r` while
    `jj describe --stdin` preserves it, so the two paths produce
    byte-different commit messages from the same input file. Fix:
    normalize to LF before diffing or describing.

12. **`git checkout -- <path>` / `git restore <path>` in a colocated
    repo.**  For a file belonging to the still-open `@` commit, the
    git index holds the empty blob (`e69de29b...`, 0 bytes) no matter
    how many real jj snapshots already captured content -- jj does not
    export real git blob content for a commit until `jj new`
    finalizes it.  Both commands therefore revert straight to the
    last-finalized parent, discarding the entire in-progress diff --
    past every intervening captured turn -- silently, with no error,
    and unrecoverably by `jj undo` (there is no jj operation to undo;
    the mutation happened entirely inside git's working tree).  Fix:
    `jj restore --from <rev> <path>`, which auto-snapshots the
    pre-restore state first, so one `jj undo` recovers everything.
    Both git forms are forbidden vocabulary in a colocated shape (see
    `SKILL.md`'s Forbidden vocabulary section); they are allow-listed
    at the permission layer, so allow-listed does not mean safe here.

13. **Compound-command permission-tier laundering.**  Anything wrapped
    inside `jj run -- <cmd>` or `git rebase --exec "<cmd>"` inherits
    the *wrapper's* permission tier and is never independently
    re-parsed against the deny list -- the same mechanism that strips
    the sandbox exemption from a wrapped `gh` / `pip` / `sbt`.
    Accepted residual risk, mitigated by sourcing gate and exec
    commands only from a reviewed static set; never compose one from
    untrusted input, and never wrap `gh`, `pip`, `pip3`, or `sbt`
    inside either form.

14. **PyPI namesquats.**  `pip install jj` installs "Remote HTTP
    Mock", `pip install jujutsu` installs a `v0.0.1` impostor, and
    `pip install cog` installs Replicate's ML tool -- none of the three
    is the tool its name suggests, and each installs successfully, so
    the tell is behavioural, not an error.  The `cog` this skill means
    is cocogitto, the conventional-commit validator
    (`references/serialization.md`); it comes from `mise` or `cargo`,
    never from pip, and PyPI's `cog` is an unrelated project.  Fix:
    never `pip install jj` / `jujutsu` / `cog`; this is forbidden
    vocabulary in `SKILL.md`.

16. **`reference-transaction` makes `jj git push`'s exit code lie.**
    It is the one git hook path that survives under jj authorship; a
    hook failing at the `prepared` stage returned exit 1 to the caller
    while the commit had already landed on the remote -- a nonzero
    exit is not proof the push didn't happen.  Fix: on any push
    failure, re-query `remote_bookmarks()` before retrying rather than
    assuming nothing changed.  Encoded in `scripts/promote.sh`'s
    `_push()`, which prints the re-query results to stderr on every
    push failure before failing the script.

17. **Absorb rename collateral, two signatures.**  Single-owner: the
    ancestor revision is silently emptied of the moved file's content,
    with only a clean `A <newpath>` row elsewhere as the tell.
    Split-ownership: conflict markers get planted into two or more
    ancestor revisions at once.  Fix: any `R ` row in `jj status`
    blocks bare `jj absorb`; route renames through a reviewed manual
    absorb instead.  `SKILL.md`'s Absorb section states this as a hard
    rule; full routing model and both signatures in detail live in
    `references/absorb.md`.

18. **`git rebase --exec` attribution.**  `.git/rebase-merge/stopped-sha`
    -- the file an agent would naturally check to see which commit an
    exec step failed on -- does not exist for exec failures at all.
    Fix: read `HEAD`, or the last `pick` line in
    `.git/rebase-merge/done`, instead.  Applies to any
    `git rebase --exec` run outside this skill -- a git-only
    repository, a declined one, or a hand-run rebase in a converted
    one; `gate.sh` never shells out to `git rebase`.

19. **`jj diff --git` is not `git diff --git`.**  The two output
    formats diverge starting at byte 50 of a hunk: similarity-index
    presence, 7 versus 10 hex digits of blob abbreviation, and
    hunk-header form all differ.  A parser validated against one
    format is not validated against the other -- feeding jj's format
    into a git-diff parser (or vice versa) fails silently on fields
    that merely look right.  Fix: pick one format per parser and test
    against real output from that exact command, not its sibling.

22. **The named slop avoid-list.**  `agentic-jujutsu` (npm) and
    `agenticdevops/aof`'s "agentic-jujutsu" / "Verification & Quality
    Assurance" skills: unresolvable repos, a 403 package page, an
    unsubstantiated "23x faster than git" claim, and an opaque "Truth
    Score" rollback gate with no documented mechanism.  These rank
    above legitimate tools in generic searches and will surface again
    in future research; naming them here costs one entry instead of
    costing a re-discovery afternoon.  Do not adopt either.

## 23-27: found building the v1 scripts

23. **`JJ_EDITOR` beats persisted `--repo` config.**  jj's actual
    precedence, highest to lowest: (1) a command-line `--config` flag,
    (2) `$JJ_EDITOR`, (3) persisted `ui.editor` from any file scope
    including `--repo`, (4) `$EDITOR` or the built-in default.  A
    persisted `--repo` write of `ui.editor` is not sufficient by
    itself: with `ui.editor = "cat"` written at `--repo` scope and
    `JJ_EDITOR=true` also set, `jj describe` still picked up
    `JJ_EDITOR` and completed instantly with `Nothing changed.` --
    silently skipping the intended no-op editor.  A script that trusts
    only the `--repo` write and never checks the environment will hang
    or misbehave under a `JJ_EDITOR` an agent's harness happened to
    export.  Fix, belt and braces: persist `--repo` `ui.editor` and
    `ui.diff-editor` = `:true` in `scripts/preflight.sh`, *and*
    hard-fail there if `JJ_EDITOR` is set to anything else, *and* pass
    `--config 'ui.editor=:true'` on every editor-invoking command
    line as a third belt.

24. **`jj run` without `--ignore-changes` silently amends the gated
    revisions.**  Without the flag, `jj run` treats the working-copy
    state left behind by the test command as a real edit and amends
    the revisions it just gated with that state -- a test gate quietly
    becomes an auto-fixer that rewrites history nobody asked it to
    touch, with no error at all.  Fix: `--ignore-changes` on every
    invocation, no exceptions.  Enforced at both `jj run` call sites
    in `scripts/gate.sh`, the ranged GATE call and the per-revision
    REPORT loop; the script header documents it as a named invariant.
    `scripts/compat_probe.sh`'s `run-ignore-changes` claim re-checks
    that the flag still exists.

25. **An absence claim can false-positive on help prose.**  Checking
    "does `jj git push --help` define no force flag" by grepping the
    full help text for `force` would false-positive: the help output
    describes `jj git push`'s own safety behavior as "similar to
    `git push --force-with-lease`" by analogy, so a substring match
    finds `--force-with-lease` in explanatory prose and reports a
    force flag that does not exist.  Fix: match flag *definition*
    lines only, line-anchored (`^[[:space:]]*(-f, )?--force`), never
    prose anywhere else in the help text.  Found and fixed while
    building the `push-no-force-flag` claim, the one absence claim in
    `scripts/compat_probe.sh`; grep for the claim name to read the
    guard.

26. **A vacuous absence claim when the tool itself is missing.**  The
    same absence check above has a second failure mode: if
    `jj git push --help` fails outright (binary missing, broken
    install), a naive "the force-flag pattern doesn't match" test
    reports success -- the claim "no force flag exists" trivially
    holds when there is no help output to search at all, which is not
    the thing the check was meant to verify.  Fix: guard presence
    first; only evaluate the absence claim after confirming the
    underlying command actually produced output.  Implemented as the
    `if ! jj git push --help > /dev/null 2>&1; then _fail ...` guard
    ahead of the pattern match in the `push-no-force-flag` claim.  The
    same rule generalizes: when `jj` is absent, `compat_probe.sh`
    fails every jj-dependent claim by name rather than letting any of
    them pass unexamined.

27. **`grep -qv PATTERN` as an absence check is an always-true trap on
    multi-line input.**  `grep -qv` succeeds (exit 0) the instant it
    finds *any* line that does not match, which is true of nearly any
    multi-line help or log output regardless of whether a matching
    line also exists elsewhere in the same stream -- so `cmd --help |
    grep -qv FLAG` as a stand-in for "FLAG is absent" is true almost
    unconditionally and proves nothing.  Fix: never use `grep -qv` to
    assert absence over multi-line output; assert presence with a
    positive, line-anchored `grep -q`/`grep -qE` and invert the shell
    conditional (`if ... ; then absent; else present; fi`) instead, as
    the `push-no-force-flag` claim in `scripts/compat_probe.sh` does
    for entry 25 and 26's same check.
