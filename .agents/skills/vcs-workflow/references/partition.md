# Partition

v1 ships file grain only: `jj split <paths> -m`, nothing else.  A
multi-concern single file has no auto-path -- it goes to a human.
This file carries the procedure, the receipt it lands in, and the
reason the sub-file classifier is deferred rather than shipped; the
classifier's own design constraints live in
`~/.agents/.local/share/research/vcs-workflow/design-decisions-final.md`,
section 8.2 (R3).

## v1 procedure -- file grain

```sh
jj split <paths...> -m 'type(scope): subject'
```

Undo: `jj undo`.

`jj split --help` states that `-i`/`--interactive` "is the default if
no filesets are provided" -- passing paths already skips the diff
editor, so bare `<paths> -m` is non-interactive on its own.  No
`--tool` wiring needed for file grain.  `scripts/compat_probe.sh`'s
`split-message` and `split-tool` claims re-check both flags.

| Case                             | Action                                |
| :--------------------------------- | :-------------------------------------- |
| File's changes are one concern    | `jj split <path...> -m 'msg'`          |
| File's changes are 2+ concerns    | Refuse auto-split; hand off to a human (R3) |

`-m` labels only the split-out (selected) commit; the remaining
commit keeps `@`'s original description, which is usually empty for
fresh uncommitted work.  For N concerns tangled in one changeset,
split out N-1 times, each with its own `-m`, then `jj describe -m`
the tail commit -- `-m` on `split` never reaches it.

Splitting is a `standard`/`full` step.  At level `oplog` the skill
never rewrites revisions: partition the work by committing it in
pieces with git, through the codex.

Receipt shape (`vcs-handoff/2`, `references/receipts.md`):

```
partition {grain:"file", splits[]{paths[], change_id}, refused[]}
```

`refused[]` is where a multi-concern file lands -- a recorded
refusal, not a crash and not a guess.  `emit_handoff.sh` emits the
whole `partition` object as a static placeholder, so the refusal is
the splitting agent's to record, never something the receipt observed
(`references/receipts.md`).

## Why hunk-grain is deferred (R3)

The wave-2 pipeline (`git diff -U0` -> structural kind query ->
interval overlap -> `jj split --tool`) produced a lossless 2-commit
split across 6 files, 3 languages, and 2 tangled concerns: a pure
rename commit and a pure feature commit, recombining losslessly to
the original diff, zero manual hunk-picking.

Wave 3 ran the same design against a harder fixture and falsified the
two properties that made it safe to run unattended:

- **A1 -- symbol-first walk is blind to orphan hunks.**  All six
  files in a 3-concern fixture had at least one hunk with zero symbol
  overlap (module-scope constants, import blocks).  A real
  `jj split --tool` run bundled an unrelated bugfix, in all three
  languages, into a rename-only commit -- zero warning, zero manifest
  entry, zero refusal signal.
- **A2 -- no same-hunk collision detector.**  The "hand off to a
  human" mitigation for two concerns in one hunk never fired because
  nothing detected the collision: a single `-U0` hunk with a rename
  on line 1 and an unrelated change on line 2 was emitted as one
  confident single-concern entry.

Both failures produced silent wrong output, not a refusal -- the
disqualifying property for anything meant to run unattended.  R3
therefore cuts the classifier and its apply script from the skill
entirely; `jj split <paths> -m` needs neither.

## Rebuilding the classifier

Binding constraints, and the evidence behind each, are section 8.2 of
`design-decisions-final.md`; they are not restated here, because a
second copy drifts.  The two that decide whether a rebuild may run
unattended at all: every `-U0` hunk in a file must be claimed by
exactly one classified symbol, and a same-hunk collision detector
must exist as code, with a passing refusal fixture -- 3+ concerns,
orphan hunks in every language, one same-hunk collision -- before the
classifier is trusted.  Every git read it makes still goes through
`scripts/git_diff_safe.sh` (`references/traps.md` #1 and #10).

## When a file has multiple concerns today

Refuse; hand it to a human.  No sub-file auto-partitioning ships
until the hunk-first classifier passes that gating fixture.
