# Absorb

`jj absorb` reassigns diff hunks from `--from` (default `@`) to the
closest ancestor that last touched the same lines-- it is blame
routing, not code review.  It has zero knowledge of correctness;
per-revision verification still runs after every absorb, because
absorb can rewrite a mid-stack commit's file inventory without a
single wrong-looking line ever appearing in the final `@` diff (see
Rename collateral, below).

## Command

```
jj absorb [FILESETS]...              # bare: --from=@, --into=mutable()
jj absorb <path> ...                 # fileset-scoped (preferred)
jj absorb --into <revset> <path> ... # destination-scoped, hard filter
jj absorb --no-integrate-operation   # dry run
```

## Routing model

- The search domain for a hunk's owner is ancestors of `--from`
  (default `@`); the destination set is `--into` (default
  `mutable()`), narrowed by this skill's invariant 12 to
  `mutable() & ~::remote_bookmarks()`.  Pass that explicitly-- do not
  rely on jj's bare default, which stops at plain `mutable()` and
  says nothing about remote visibility.
- Blame is line-provenance, not content-hash.  An adversarial probe
  with two textually-identical `value = 1` lines sitting in unrelated
  ancestors routed the edited copy to its true owner with zero
  cross-contamination (0/1 misroute under deliberate collision
  stress).
- An ambiguous hunk-- one whose contiguous line run spans two owners,
  or one owner plus an unrelated insertion within a few lines-- is
  left whole in the source revision.  Absorb never guesses across an
  ownership boundary; it under-routes instead.

## Measured rates

| Metric | Result | Basis |
| :-- | :-- | :-- |
| Misroutes | 0/27 | 26 authored edits + 1 new-file control, 4-commit/11-file stack |
| Safe residual (left in `@`) | 5/26 | adjacency-clustering; never wrong-ancestor |
| Adversarial identical-content | 0/1 | two `value = 1` lines, distinct ancestors |
| Fileset-scoped leakage | 0/0 | out-of-scope paths untouched |
| `--into` destination leakage | 0/0 | out-of-scope destination commits untouched |

Source: wf2-dives.json item 1 ("Is jj absorb default-on, advisory, or
dangerous..."), folded into design-decisions-final.md D1.2.

## Destination invariant

Every absorb destination is a subset of
`mutable() & ~::remote_bookmarks()` (invariant 12)-- the mechanical
form of "during active review, make changes in NEW commits."  An
absorb that could reach a pushed, reviewed commit is a policy
violation before the routing question is even asked.

## Rename collateral-- the R-row hard block

**Bare `jj absorb` treats a rename as two unrelated hunks, not one
routable unit.**  Any `R ` row in `jj status` blocks bare absorb;
route through `--into <rev> <paths>` instead, or handle the rename by
hand.

```
jj status | grep '^R '   # any hit: do not run bare `jj absorb`
```

Two signatures, both invisible in absorb's own stdout summary and in
a plain `jj diff -r @` residual check:

| Signature | Ownership | Symptom |
| :-- | :-- | :-- |
| Silent empty | single owner | ancestor file emptied; `jj file show -r <anc> <oldpath>` returns "No such path"; only visible signal is a clean `A <newpath>` residual in `@` |
| Conflict plant | split across 2+ ancestors | `New conflicts appeared in 2 commits`; markers land in every owning ancestor |

Detect either, after any absorb that touched a rename:

```
jj op show -p --summary | grep -E '^(Removed|Deleted) (regular file|file)'
jj log -r 'conflicts()' --no-graph
```

Signature (a) fires even on a pure rename with zero content edit-- it
is not conditional on an accompanying fix.  Treat every `R ` row as
in scope for the guard, not only renames that also carry a diff.

## Precision forms

```
jj absorb <path1> <path2> ...   # fileset-scoped: only these paths eligible to move
jj absorb --into <revset>       # destination-scoped: only these commits eligible as targets
```

Both are hard filters, not preferences: 0/0 leakage into out-of-scope
paths or out-of-scope destination commits in either form.  Prefer
fileset-scoped absorb whenever the touched paths are already known--
it costs nothing in safety and shrinks the adjacency-clustering
ambiguity surface that produces safe residual.

## Dry run

`--no-integrate-operation` is a global flag, not absorb-specific: the
operation is created and its result computed and printed, but never
integrated into `jj op log`, and the working copy is not updated.

```
jj absorb --no-integrate-operation ...   # prints the resulting operation id
jj --at-op=<id> diff                     # inspect the would-be result
jj op integrate <id>                     # only if you want to keep it
```

Discarding is inaction: an un-integrated operation is not part of the
oplog, so there is nothing to undo.

## Immutable-owner no-op

Absorb against a properly protected immutable owner is a true no-op
(wave-3 HOLDS): `Nothing changed.`, exit 0, zero new operations in
`jj op log`.  An explicit `--into <immutable-rev>` hard-errors before
any mutation-- it never silently drops the hunk into `@` instead.

## Mandatory post-absorb pair

Absorb's own stdout (`Absorbed changes into N revisions: ...`) does
not surface rename collateral.  Run both, every time, before
promotion (invariant 13):

```
# 1. residual check
jj log -r @ -T 'if(empty, "ABSORB_COMPLETE\n", "RESIDUAL_PRESENT\n")' --no-graph
jj diff -r @ --summary

# 2. op-log review
jj op show -p --summary   # compact, per-destination-commit overview
jj op show -p             # full per-file, line-numbered before/after
```

`jj evolog -p` is rejected as the audit channel: for this same
operation its output was dominated by synthetic conflict-resolution
scaffolding (`<<<<<<<` markers, "Removed conflict" / "Resolved
conflict" entries from absorb's own rebase machinery), not a clean
statement of what moved.  `jj op show -p` is the one canonical audit
command.

---

Results populate the handoff `absorb` block (`ran`, `op_id`,
`destinations`, `residual`, `renames_blocked`); field semantics live
in `references/receipts.md`.
