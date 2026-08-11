# Conflicts

Conflicts are data, not control flow.  jj materializes a conflicting
rebase as an ordinary revision carrying a `(conflict)` marker; the
rebase itself succeeds, exit 0.  Nothing halts on its own -- the gate
is what has to see none.  This file covers detection, the gate
interaction, resolution options, the post-edit marker grep, and push
refusal.

## Detection

```sh
jj log -r 'conflicts() & (<range>)' --no-graph \
	-T 'change_id.short() ++ "\n"'
```

Rule: PASS iff stdout is empty.  `jj log`'s exit code is always 0,
conflicts present or not -- read the output, never the exit status.

**Never use `jj resolve --list -r <revset>`'s exit code for this.**
Three codes, meaning opposite things depending which you expect as
"clean":

| Condition                      | Exit |
| :------------------------------ | :--- |
| revision has conflicts          | 0    |
| revset resolves to no revisions | 1    |
| revision exists, no conflicts   | 2    |

0 means "has conflicts" here -- the inverse of the usual "0 = OK"
reading.  A gate branching on this exit code silently inverts its own
pass/fail logic.  Receipt: `wf2-dives.json` Q6 evidence #5.

## Gate interaction (`gate.sh`)

`jj run` does not special-case a conflicted revision -- it executes the
verification command inside the marker-polluted file.  Observed on a
real conflict: `SyntaxError: invalid decimal literal` pointing at a
literal `------- tkkyktmt` marker line, exit 1, structurally identical
to a genuine test failure.  Receipt: `wf2-dives.json` Q6 evidence #4.

`gate.sh` therefore checks `conflicts() & $RANGE` before mode
selection and before any `jj run` invocation runs at all:

```sh
_conflicted=$(jj log -r "conflicts() & ($RANGE)" --no-graph \
	-T 'change_id.short() ++ "\n"')
[ -n "$_conflicted" ] && exit 4   # CONFLICT-BLOCKED, printed, never run
```

Exit 4 (`CONFLICT-BLOCKED`) is distinct from exit 1 (a real gate
failure) precisely so the two are never conflated downstream.  Full
table, from `gate.sh`'s own header: 0 pass, 1 gate failure, 2 usage,
3 worktree-shadowed, 4 CONFLICT-BLOCKED, 5 wrong shape.

Undo: none needed -- detection and the pre-flight check are read-only.

## Resolution -- user-directed only, never automatic

No path below runs on its own after a CONFLICT-BLOCKED exit.  Each is
invoked deliberately, by name, by whoever is resolving the conflict.

| Path              | Command                                                   | Validates result?                          | Use when |
| :----------------- | :--------------------------------------------------------- | :------------------------------------------- | :-------- |
| Pick a side        | `jj resolve --tool :ours` or `:theirs`                     | No -- discards the other side wholesale, always exits 0 | one side is simply correct |
| Wholesale restore  | `jj restore --from <rev> [--into <rev>] <path>`             | No -- plain file-copy op                    | same; can leave an `(empty)` descendant, review it |
| External 3-way     | `jj resolve --tool <name>` with a `merge-tools.<name>` config | Yes -- gated on the tool's own exit code    | a real line-level merge, with a deterministic, non-interactive tool configured |
| Manual edit        | edit the file directly; the next jj command auto-snapshots  | No -- zero marker-syntax validation         | last resort only, MUST be followed by the marker grep below |
| Bare `jj resolve`  | --                                                          | --                                          | **forbidden** -- opens an interactive mergetool, hangs a non-interactive session |

Undo for any attempt: `jj undo` -- one operation away, nothing pushed
yet.

`jj restore --from` receipt: it incidentally produced an `(empty)`
commit when the resolved side's diff against its new parent collapsed
to nothing.  Treat an unexpectedly-empty post-resolution commit as a
review flag, not a bug -- it usually means the change was fully
subsumed.  Receipt: `wf2-dives.json` Q6 evidence #9.

## Post-manual-edit marker grep (manual-edit path only)

jj performs zero validation on manually-edited conflict content.  A
sloppy edit that leaves a stray marker fragment is silently accepted
as ordinary file content and `conflict` flips to `false` anyway.
Confirmed: overwriting a file with a stray `<<<<<<< STRAY MARKER` line
and running any jj command (auto-snapshot) set `conflict=false` with
the fragment still sitting in the file, uncommitted-on, no warning.
Receipt: `wf2-dives.json` Q6 evidence #8.

jj's markers are not git's.  A git-tuned grep for a bare `=======`
under-matches every time -- jj never emits one.  Grep for jj's own six
tokens instead: two shared, plus two per rendering style.  The same
conflict rendered "diff" style in the normal working copy and in
`jj show`, and "snapshot" style inside `jj run`'s isolated ephemeral
workspace -- same repo, same config, no override found, so treat both
as live:

```sh
grep -nE '^<<<<<<< conflict|^>>>>>>> conflict.*ends|^%%%%%%%|^\\{8}|^-------|^\+\+\+\+\+\+\+' <path>
```

| # | Token                    | Style                        |
| :- | :------------------------ | :----------------------------- |
| 1 | `^<<<<<<< conflict`       | shared -- outer open           |
| 2 | `^>>>>>>> conflict.*ends` | shared -- outer close          |
| 3 | `%%%%%%%`                 | diff (working copy, `jj show`) |
| 4 | `\\\\\\\\` (8 backslashes) | diff -- inner `to:` separator |
| 5 | `-------`                 | snapshot (`jj run`)            |
| 6 | `+++++++`                 | snapshot (`jj run`)            |

Any hit after a manual edit means the edit did not actually resolve
the conflict.  Re-edit, or fall back to a validated path above, before
`jj undo`-ing back out.

## Push refusal

`jj git push` refuses a conflicted commit unconditionally and
precisely:

```
Error: Won't push commit <id> since it has conflicts
```

exit 1.  Receipt: `wf2-dives.json` Q6 evidence #10, against a real
bare-repo remote.

`--allow-conflicts` is the one documented override, and it is
forbidden vocabulary in this skill (invariant 7): it defeats a refusal
that is otherwise unconditional and precise, and nothing downstream
re-validates a conflict that slipped through it.  Never append it,
including as a retry fallback.

## Semantic conflicts

Zero textual conflicts (`conflicts()` empty) is necessary but not
sufficient.  jj has no concept of a semantic conflict: shared config,
shared types, and shared test utilities that both sides edited
compatibly at the text level can still be wrong together.  That check
stays a human gate; nothing in this skill automates it.

---

Doc: `design-decisions-final.md` D1.7.  Invariant 10.
