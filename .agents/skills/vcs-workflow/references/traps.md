# Traps

The consolidated silent-failure catalogue.  Every entry fails without
an error, a nonzero exit, or any other signal that would normally stop
an agent -- that is the qualifying bar for inclusion here.  Loud
failures (a real nonzero exit, a real exception) are not traps; they
are just errors, and the caller already handles them.

Entries 1-22 are the original catalogue, numbered as settled in the
design decisions (`traps.md carries all 22 entries`).  Entries 23-27
were found while building the scripts under `scripts/` and are new.
Where a shipped script encodes the mitigation, the entry cites the
exact file and line so a 3am reader can jump straight to the fix
instead of trusting this prose.

## 1-22: the original catalogue

1. **A jj revset handed to git.**  `git diff -U0 @-` in a colocated
   repo exits 128 with empty stdout (rc=0 only when piped through
   `cat`, which swallows the real exit code); the actual defect is an
   unchecked subprocess return code one call site above the git
   invocation.  Fix: resolve the revset to a commit id first
   (`jj log -r <revset> --no-graph -T commit_id`) and assert
   `returncode == 0`.  Encoded in `scripts/git_diff_safe.sh:36-42`,
   the single sanctioned entry point for hardened git reads.

2. **ast-grep exit-code overloading.**  8 is a hard failure; 0 or 1
   with empty stderr is success; 1 with non-empty stderr is a real
   error; a benign zero-match result and a real file-not-found error
   both return 1 and are otherwise indistinguishable.  Fix: parse
   `--json`, never gate on the exit code alone.  No v1 script ships
   this (the classifier that would call it is deferred to v2, section
   8.2 of the design decisions); document it here for any ad hoc
   `ast-grep` invocation in the meantime.

3. **Nested-kind double-match.**  TypeScript's `export_statement` kind
   wraps `function_declaration`, so a naive per-kind scan counts one
   exported function twice.  Fix: dedupe matches on `(start, end)`
   span, not on kind name.  Same v2-classifier caveat as #2 -- no v1
   script encodes this yet.

4. **`--ignore-errors` on `jj run`.**  Zeroes the exit code on a real
   failure and deletes the `Hint: Failed revision:` attribution the
   caller needs to find what broke.  Fix: never pass it.  Enforced by
   omission in `scripts/gate.sh:124` and `:137` -- neither `jj run`
   call carries the flag, and the script header names it explicitly
   as a documented invariant (`gate.sh:19-20`).

5. **`description("text")` is glob-matched.**  A bare string in a
   `description()` revset filter is parsed as a `glob:` pattern and
   silently returns zero results against a message with no glob
   metacharacters that still doesn't match literally. Fix: use
   `description(substring:"...")`.  Applied throughout
   `scripts/gate.sh:106` and `scripts/promote.sh:66,69`.

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

8. **difftastic's binary is named `difft`, not `difftastic`.**  jj's
   builtin `difftastic` merge-tool preset invokes a binary literally
   named `difftastic`, which fails with exit 1 "No such file or
   directory" against every mainstream install (mise, cargo, brew, and
   distro packages all name the binary `difft`).  Fix:
   `merge-tools.difftastic.program = "difft"`.  Written by
   `scripts/preflight.sh:87-88` as one of the four sanctioned `--repo`
   config keys.

9. **Worktree shadow.**  A harness-created nested worktree has no its
   own `.jj/`, so jj walks up the filesystem and answers for the
   *parent* repo: it reports and can commit the parent's uncommitted
   files under the agent's message, while the worktree's own changes
   never appear.  A sibling (non-nested) worktree fails loudly instead
   (`Error: There is no jj repo in "."`), so the silent-danger mode is
   specific to the nested case.  Fix: `scripts/detect_shape.sh:23-26`
   compares `jj root` against `git rev-parse --show-toplevel`; a
   mismatch is `worktree-shadowed`, exit 3, hard stop -- no jj command
   may run, reads included.  Never pair this skill with worktree-based
   subagent isolation.

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
    `pip install cog` installs Replicate's ML tool -- none is the
    jj/ast-grep toolchain.  Only `ast-grep-cli` is a legitimate pip
    channel among these tools.  Fix: never `pip install jj` /
    `jujutsu` / `cog`; this is forbidden vocabulary in `SKILL.md`.

15. **`mise use` phones home even for an already-linked version.**  It
    unconditionally probes `mise-versions.jdx.dev` then
    `api.github.com`, 3 retries with backoff, on a machine where that
    network path is exactly what's locked down -- non-fatal but pure
    latency, and a surprise egress attempt on a host that shouldn't
    make one.  `mise use --locked` separately hard-fails without a
    pre-existing lockfile entry.  Fix: `mise link` (pure filesystem
    symlink, zero network) plus `mise config set` (writes TOML
    directly, also zero network).  Receipted live in
    `scripts/bootstrap_work.sh:29-41`; applied at
    `bootstrap_work.sh:236-241`.

16. **`reference-transaction` makes `jj git push`'s exit code lie.**
    It is the one git hook path that survives under jj authorship; a
    hook failing at the `prepared` stage returned exit 1 to the caller
    while the commit had already landed on the remote -- a nonzero
    exit is not proof the push didn't happen.  Fix: on any push
    failure, re-query `remote_bookmarks()` before retrying rather than
    assuming nothing changed.  Encoded in `scripts/promote.sh:82-88`,
    which prints the re-query results to stderr on every push failure
    before failing the script.

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
    `.git/rebase-merge/done`, instead.  Applies to the git-only
    verification path; full recipe in `references/git-only.md`.

19. **`jj diff --git` is not `git diff --git`.**  The two output
    formats diverge starting at byte 50 of a hunk: similarity-index
    presence, 7 versus 10 hex digits of blob abbreviation, and
    hunk-header form all differ.  A parser validated against one
    format is not validated against the other -- feeding jj's format
    into a git-diff parser (or vice versa) fails silently on fields
    that merely look right.  Fix: pick one format per parser and test
    against real output from that exact command, not its sibling.

20. **`sg` is deprecated.**  ast-grep 0.45.1 prints a deprecation
    banner pointing at `ast-grep` on every invocation of the `sg`
    alias -- noise at best, a broken pipe parse at worst if the banner
    lands on stdout in an older build.  Fix: always invoke `ast-grep`.
    `scripts/compat_probe.sh` and `scripts/bootstrap_work.sh:290` both
    reference `sg` only as the deprecated-alias binary name to smoke
    check, never as the command to run.

21. **`git apply --unidiff-zero` fuzzy relocation.**  With zero context
    lines, `git apply` relocates a hunk by fuzzy match against
    surrounding content, which can mis-place it in a file with
    duplicated nearby lines.  Verified correct against +1 and +4 line
    drift; not proven safe in general.  Fix: `git diff --cached` after
    every apply to confirm the hunk landed where intended.  Receipted
    and cross-linked to this entry directly in
    `scripts/git_only_hunks.awk:15-18`, which produces the hunks this
    flag applies.

22. **The named slop avoid-list.**  `agentic-jujutsu` (npm) and
    `agenticdevops/aof`'s "agentic-jujutsu" / "Verification & Quality
    Assurance" skills: unresolvable repos, a 403 package page, an
    unsubstantiated "23x faster than git" claim, and an opaque "Truth
    Score" rollback gate with no documented mechanism.  These rank
    above legitimate tools in generic searches and will surface again
    in future research; naming them here costs one entry instead of
    costing a re-discovery afternoon.  Do not adopt either.

## 23-27: found building the v1 scripts

23. **`JJ_EDITOR` beats persisted `--repo` config.**  Actual jj 0.44.0
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
    `ui.diff-editor` = `:true` (`scripts/preflight.sh:85-86`), *and*
    hard-fail if `JJ_EDITOR` is set to anything else
    (`scripts/preflight.sh:51-53`), *and* pass
    `--config 'ui.editor=:true'` on every editor-invoking command
    line as a third belt.

24. **`jj run` without `--ignore-changes` silently amends the gated
    revisions.**  Without the flag, `jj run` treats the working-copy
    state left behind by the test command as a real edit and amends
    the revisions it just gated with that state -- a test gate quietly
    becomes an auto-fixer that rewrites history nobody asked it to
    touch, with no error at all.  Fix: `--ignore-changes` on every
    invocation, no exceptions.  Enforced in `scripts/gate.sh:124` and
    `:137`, both call sites; the header documents it as a named
    invariant at `gate.sh:16-18`.

25. **An absence claim can false-positive on help prose.**  Checking
    "does `jj git push --help` define no force flag" by grepping the
    full help text for `force` would false-positive: the help output
    describes `jj git push`'s own safety behavior as "similar to
    `git push --force-with-lease`" by analogy, so a substring match
    finds `--force-with-lease` in explanatory prose and reports a
    force flag that does not exist.  Fix: match flag *definition*
    lines only, line-anchored (`^[[:space:]]*(-f, )?--force`), never
    prose anywhere else in the help text.  Found and fixed while
    building the `push-no-force-flag` absence claim in
    `scripts/compat_probe.sh:130-138`.

26. **A vacuous absence claim when the tool itself is missing.**  The
    same absence check above has a second failure mode: if
    `jj git push --help` fails outright (binary missing, broken
    install), a naive "the force-flag pattern doesn't match" test
    reports success -- the claim "no force flag exists" trivially
    holds when there is no help output to search at all, which is not
    the thing the check was meant to verify.  Fix: guard presence
    first; only evaluate the absence claim after confirming the
    underlying command actually produced output.  Implemented as the
    `if ! jj git push --help >/dev/null 2>&1; then _fail ...` guard at
    `scripts/compat_probe.sh:135`, ahead of the pattern match.

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
    `scripts/compat_probe.sh:130-138` does for entry 25 and 26's same
    check.
