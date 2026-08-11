# Partition

v1 ships file grain only: `jj split <paths> -m`, nothing else.  This
file also carries the hunk-grain design that wave 3 falsified, so the
lessons survive for whoever rebuilds it (R3, section 8.2).  A
multi-concern single file has no v1 auto-path -- it goes to a human.

## v1 procedure -- file grain

```sh
jj split <paths...> -m 'type(scope): subject'
```

Undo: `jj undo`.

Verified against jj 0.44.0 (`jj split --help`): `-i`/`--interactive`
"is the default if no filesets are provided" -- passing paths already
skips the diff editor, so bare `<paths> -m` is non-interactive on its
own.  No `--tool` wiring needed for file grain.

| Case                             | Action                                |
| :--------------------------------- | :-------------------------------------- |
| File's changes are one concern    | `jj split <path...> -m 'msg'`          |
| File's changes are 2+ concerns    | Refuse auto-split; hand off to a human (R3) |

`-m` labels only the split-out (selected) commit; the remaining
commit keeps `@`'s original description, which is usually empty for
fresh uncommitted work.  For N concerns tangled in one changeset,
split out N-1 times, each with its own `-m`, then `jj describe -m`
the tail commit -- `-m` on `split` never reaches it.

Receipt shape (`vcs-handoff/1`, `references/receipts.md`):

```
partition {grain:"file", splits[]{paths[], change_id}, refused[]}
```

`refused[]` is where a multi-concern file lands -- a recorded
refusal, not a crash and not a guess.

## ast-grep exit-code discipline (binding today, not just v2)

Where this already runs in v1: the degraded `message_hints` field
(`references/receipts.md`) does a read-only `ast-grep --json` scan of
changed files for an unranked symbol hint list.  Same rules apply
there as to the deferred classifier below.

Invoke `ast-grep` directly, never `sg` -- deprecated upstream in
0.45.1, prints a banner on every call, confirmed live (`sg` present
alongside `ast-grep 0.45.1` post-install).  Receipt: `wf4-dives.json`
Q1 evidence #5.

Exit codes, measured against ast-grep 0.45.1 in 4 cases (invalid
kind, valid-kind-zero-match, valid-kind-with-match, bad path):

| Exit | stderr    | Meaning                                    |
| :--- | :--------- | :------------------------------------------- |
| 8    | --        | Hard fail -- invalid/typo'd `--kind` name    |
| 0    | --        | Success                                     |
| 1    | empty     | Success, zero matches -- benign, common      |
| 1    | nonempty  | Real error, e.g. file not found             |

Zero-match and file-not-found are BOTH exit 1 -- indistinguishable by
exit code alone.  Rule: exit 8 is the only code to hard-fail on;
otherwise always parse `--json`/`--json=compact` and check stderr
emptiness, never branch on exit 0 vs 1.  Receipt: `wf2-dives.json` Q3
evidence #3.

```sh
ast-grep run --lang <lang> --kind <kind> <path> --json=compact
# exit 8             -> hard fail
# exit 0              -> success, parse stdout
# exit 1, stderr==''  -> success, zero matches
# exit 1, stderr!=''  -> real error
```

Dedupe nested-kind matches on `(start, end)`: TS `export_statement`
wraps `function_declaration` and double-books every exported
function -- confirmed, `export function computeTotal(...)` reported
twice at the identical L1-L7 span.  Receipt: `wf2-dives.json` Q3
evidence #5.

## The 18-entry kind table (verified)

Each entry independently confirmed: `ast-grep run --lang <lang>
--kind <kind> <smoke-file> --json=compact` required exit 0 and at
least one real match, none taken from memory or docs alone.  Receipt:
`wf2-dives.json` Q3 evidence #4.

| Language   | function-like                                                  | container-like                                                              |
| :---------- | :---------------------------------------------------------------- | :------------------------------------------------------------------------------ |
| python     | `function_definition`, `lambda`                                | `class_definition`, `decorated_definition`                                  |
| rust       | `function_item`, `closure_expression`                          | `impl_item`, `struct_item`, `enum_item`, `trait_item`, `mod_item`            |
| typescript | `function_declaration`, `method_definition`, `arrow_function`  | `class_declaration`, `interface_declaration`, `type_alias_declaration`, `export_statement` |

18 kinds total: 4 python, 7 rust, 7 typescript.

## Why hunk-grain is deferred (R3)

The wave-2 pipeline (`git diff -U0` -> ast-grep kind-query -> interval
overlap -> `jj split --tool`) produced a lossless 2-commit split
across 6 files, 3 languages, and 2 tangled concerns: a pure rename
commit and a pure feature commit, recombining losslessly to the
original diff, zero manual hunk-picking.  Receipt: `wf2-dives.json` Q3
verdict.

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
therefore cuts `partition_propose.py` and `split_apply.sh` from v1
entirely; `jj split <paths> -m` needs neither.

## v2 design notes -- not implemented, kept for the rebuild

Binding constraints on whoever rebuilds the hunk-grain classifier
(`design-decisions-final.md` section 8.2):

1. Hunk-first walk, never symbol-first.  Every `-U0` hunk must be
   claimed by exactly one classified symbol.
2. Gate auto-split on 100% hunk coverage per file, not "at least one
   classified hunk".  Any orphan hunk sends the WHOLE file to
   suggest-only -- orphan hunks are common, not exotic.
3. The same-hunk collision detector must exist as code: count
   distinct changed-token runs per hunk (or run a finer word- or
   expression-level diff), and refuse the hunk and its file when the
   count exceeds 1 in a way the rename-pair table does not explain.
4. The refusal path needs a passing fixture -- 3+ concerns, orphan
   hunks in every language, one same-hunk collision -- before the
   classifier is trusted unattended.
5. **Two-anchor rule.**  Classify on the ast-grep SYMBOL span;
   partition on the owning HUNK's line range.  The AST node excludes
   blank-line padding the hunk includes: a 3-line node inside a
   5-line hunk left two orphan blank lines polluting the other
   commit.  Receipt: `wf2-dives.json` Q3 evidence #7.
6. **Old-side rename anchoring.**  Classify rename-vs-new against the
   hunk's OLD-side range, never the new symbol's own line numbers.
   An earlier insertion shifted lines and misclassified a brand-new
   function as a rename of a coincidentally relocated one.  Receipt:
   `wf2-dives.json` Q3 evidence #6.
7. Keep the 18-entry kind table above; dedupe on `(start, end)`.
8. Every git invocation stays hardened: through `git_diff_safe.sh`,
   with `-c core.quotePath=false`, an explicit `returncode == 0`
   assertion, and revsets resolved to commit ids before git is called
   at all.  See `references/traps.md` #1 and #17.
9. Serena (`find_referencing_symbols`, `rename_symbol`) is the
   natural accelerator, still never a dependency (R4): true rename
   vs. delete-plus-add is exactly what ast-grep's structural matching
   cannot do reliably, and rename misclassification is what forced
   rule 6.  Probe for it; degrade to ast-grep when absent; never let
   a receipt field depend on it.
10. `split_apply.sh` returns only with the classifier: `jj split
    --tool` needs an executable on disk, and the `$left`/`$right`
    contract cannot be inlined.

## When a file has multiple concerns today

Refuse; hand it to a human.  No sub-file auto-partitioning ships
until the hunk-first classifier above passes its gating fixture --
see rule 4.

---

Doc: `design-decisions-final.md` D1.4, section 8.2.
