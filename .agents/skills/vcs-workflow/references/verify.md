# Verify

`scripts/gate.sh` is the only caller of `jj run` in this skill --
every verification gate goes through it.  It wraps `jj run` with the
flag invariants whose violation is silent, picks GATE vs REPORT shape
mechanically, and writes a `vcs-gate/1` receipt.  Read-only: a passing
or failing gate never mutates repo state, so there is no undo.

## Usage

```sh
gate.sh [--range REVSET] [--cheap] [--report] [--final-clean] \
	-- CMD [ARG...]
```

| Flag | Effect |
| :-- | :-- |
| `--range REVSET` | Revset to gate.  Default: `(trunk()::@) ~ root()`. |
| `--cheap` | Sub-second command (lint, ast-grep, fast unit tests): `-j$(nproc)` unconditionally. |
| `--report` | Force per-revision REPORT mode even with no RED trailer in range. |
| `--final-clean` | Reproducibility-critical final gate only: adds `--clean`, discards every warm job slot.  Never part of the routine loop. |

Exit codes, from the script's own header: `0` pass, `1` gate failure,
`2` usage error, `3` worktree-shadowed, `4` `CONFLICT-BLOCKED`, `5`
wrong shape (`git-only`, `none` -- see `references/git-only.md` for
the git-only gate path).  Conflict pre-flight and its exit-4 shape are
`references/conflicts.md`'s scope, not repeated here.

Receipt: `<repo>/.local/state/agents/vcs/gate.json`.

## Flag matrix

### `--ignore-changes` -- mandatory, every invocation

`gate.sh` carries it on every `jj run` call and gives no flag to omit
it.  Without it, `jj run` treats the gated command like a formatter:
it amends the revision with whatever the working copy looks like
afterward.  A test gate silently becomes an auto-fixer, and any test
byproduct (cache dirs, coverage files, anything the command writes)
gets folded into the revision's committed content.  It also correctly
bypasses the immutable-commit refusal without loosening protection via
`--ignore-immutable` -- the right shape for re-verifying an
already-landed revision.  Invariant 6.  Receipt: `wf2-dives.json` Q1
evidence #10, Q6 evidence #13.

### `--ignore-errors` -- forbidden vocabulary, never emitted

Never appears anywhere in `gate.sh`; there is no flag that requests
it.  It zeroes `jj run`'s own exit code on a real failure **and**
deletes the `Hint: Failed revision:` attribution line -- a gate that
checked the exit code with `--ignore-errors` set would silently report
success on a genuine failure, defeating the receipt's exit-code
contract at exactly the moment it matters.  Invariant 7.  Receipt:
`wf2-dives.json` Q1 evidence #9.

### `--clean` -- reserved for `--final-clean` only

`gate.sh`'s parser recognizes exactly four flags: `--range`,
`--cheap`, `--report`, `--final-clean`.  A bare `--clean` is not one
of them -- it falls to the parser's catch-all case, which fails,
prints usage, and exits 2.  The only path to a literal `--clean`
reaching `jj run` is `--final-clean`, which sets `CLEAN_ARG='--clean'`
internally, warns on stderr first (it is expensive), and deletes the
warm flag so the next routine run starts cold again.  Invariant 8.
Never pass it in the routine verify loop: it forces a fresh checkout
-- for a compiled project, a full cold dependency-compile -- on every
revision, every invocation.

### `-j` warmth policy

No revision-count tiering.  The only tier is job-slot warmth, because
jj's own per-revision materialization tax is negligible next to a
compiled build tool's cold-dependency tax, and jj's persistent
`.jj/run/default/<slot>/` working copies already amortize that tax
across revisions within one run and across separate invocations.

jj's own tax, isolated (`true` as the command, no real build
involved): 1.5-2ms/rev serial at `-j1`; under 1ms/rev marginal at
`-j4`, where parallelism absorbs almost all of it.

Measured on a real 3-revision Rust stack (dtolnay/semver,
cargo build+test):

| Job-slot state | `-j1` | `-j4` |
| :-- | :-- | :-- |
| Cold (`.jj/run` wiped) | 13.08s | 23.24s -- 1.92x slower; 3 concurrent cold cargo builds thrash the same cores (165.7s vs 50.3s CPU) |
| Warm (slots pre-populated) | 1.327s | 0.638s -- ~2.1x faster than warm `-j1` |

Cold `-j4` creates `min(jobs, revcount)` separate job slots, each
paying the full ~12s dependency-compile tax **concurrently** -- a
clear wall-clock loss whenever the cold tax dominates the per-rev warm
cost, which is the common case for a real dependency graph.  The
one-time extra cost of starting cold at `-j4` instead of `-j1` is
23.24 - 13.08 = 10.16s; the per-run saving once warm is 1.327 - 0.638
= 0.689s/run; break-even is 10.16 / 0.689 ~= 14.75 subsequent warm
re-runs against the same persisted job-slot dirs before `-j4` repays
its own cold-start tax.  On an ephemeral checkout that break-even is
never reached; on a long-lived local dev workspace it is easily
reached.  Receipt: `wf2-dives.json` Q1 evidence #1, #4-#7, #11.

`gate.sh`'s implementation of this policy:

- `JOBS=1` by default (cold or unknown-warmth).
- `--cheap` forces `JOBS=$(nproc)` unconditionally, independent of
  warmth -- cheap checks are assumed to carry negligible jj-side tax
  at any revision count.
- Warmth is a session-scoped flag file,
  `$(jj root)/.local/state/agents/vcs/gate-warm`.  If present,
  `JOBS=$(nproc)` even without `--cheap`.
- The flag is set **only** after a passing run that was neither
  `--cheap` nor `--final-clean` -- a cheap run says nothing about a
  compiled build's warmth, and a final-clean run just discarded it.
- `--final-clean` deletes the flag before running, and the post-run
  "set warm" step explicitly excludes `FINAL_CLEAN=1` -- a passing
  final-clean run does not immediately re-arm it.  Full reset, not a
  one-off.

## GATE vs REPORT -- selected mechanically, not chosen by the caller

`gate.sh` decides the shape from what is actually in `$RANGE`,
condensed from its `_revlist`/`_pick_mode_and_jobs` functions:

```sh
RED_TRAILER='Verification-Status: red-expected'
RED_REVS=$(jj log -r "description(substring:\"$RED_TRAILER\") & ($RANGE)" \
	--no-graph -T 'change_id.short() ++ "\n"')
[ -n "$RED_REVS" ] && MODE='REPORT'
```

`--report` forces REPORT even with no RED revision present; otherwise
any RED trailer in range forces it automatically.  The trailer is a
real git trailer, not a substring hack -- it survives squash, rebase,
and split, matching SKILL.md's "RED and xfail" section.

**GATE** (no RED revision in range, the common case): one ranged call,

```sh
jj run --ignore-changes $CLEAN_ARG -j "$JOBS" -r "$RANGE" -- "$@"
```

Fail-fast: `jj run` stops at the first failing revision in DAG order
and never attempts anything after it -- even under `-j >1`, where
later revisions may already be running concurrently, only one `Hint:
Failed revision:` line ever surfaces, which `gate.sh` parses for
`FAILED_CHANGE`.  Cheapest shape, exact culprit, but silent about
everything past the first failure.  Receipt: `wf2-dives.json` Q6
evidence #12.

**REPORT** (mandatory whenever the range carries the RED trailer): a
per-revision loop, always `-j 1` per iteration regardless of the
`$JOBS`/warmth value computed above -- each iteration is already a
single revision, there is nothing to parallelize, and in this mode
`$JOBS` ends up recorded in the receipt but unused by the actual
calls:

```sh
for _rev in $(jj log -r "$RANGE" --no-graph -T 'change_id.short() ++ "\n"'); do
	if jj run --ignore-changes $CLEAN_ARG -j 1 -r "$_rev" -- "$@" \
		>/dev/null 2>&1
	then
		:                                    # OK, continue
	elif printf '%s\n' "$RED_REVS" | grep -q "^$_rev$"
	then
		:                                    # RED-EXPECTED, tolerated, continue
	else
		VERDICT='fail'; FAILED_CHANGE=$_rev  # unmarked FAIL, continue anyway
	fi
done
```

The loop never breaks on a failure -- that is the entire reason REPORT
exists: a ranged call aborts at the first failure and never reports on
later revisions, so a stack carrying a deliberate RED commit needs
every revision checked individually to tell "expected red" apart from
"everything after this is simply unknown."  Verified both directions:
a marked RED commit tolerated, an unmarked regression caught.
Receipt: `wf2-dives.json` Q6 evidence #14.

## Atomicity of a failed ranged run

A failed GATE call is not merely fail-fast in what it reports -- it is
fully atomic in what it leaves behind.  A revision that had passed
*before* a later revision in the same range failed was checked and
found not to be amended, and **no new operation was recorded in `jj op
log` at all** for the whole invocation.  The batch rolls back to a
no-op on any failure.  Nothing partial survives to build on; a
subsequently fixed-and-rerun gate starts clean, never resumed.  Only
`--ignore-errors` would salvage the passing subset's side effects, and
it is forbidden (above).  Receipt: `design-decisions-final.md` D1.3
`[W3-amended]`.

## Default range: `(trunk()::@) ~ root()`

The default applies only when `--range` is not passed -- an explicit
`--range` replaces it verbatim, with no automatic `~ root()` appended.
A caller who hand-writes a revset spanning back to `root()` on a
local-only trunk reintroduces the trap below; the defensive exclusion
lives only in the literal default constant.

Why the exclusion: jj's builtin `trunk()` alias resolves through
`remote_bookmarks(...)`, falling back to bare `root()` -- the empty
virtual root, before any content -- when no matching remote bookmark
exists.  A fully local-only repo's trunk *is* `root()`; there is
nothing else for `trunk()` to resolve to, confirmed directly: `trunk()
& immutable()` returned only `root()` on a real local-only-trunk repo,
even after `immutable_heads()` was correctly configured.  In that case
`trunk()::@` literally is `root()::@`, so an unqualified range includes
the root commit itself -- no tracked files exist there at all.
Checking out and running the gate command against an empty tree
produces its own confusing failure (missing project files, not a real
test regression), the same shape of silent-failure trap as the
conflict-marker case in `references/conflicts.md`, though not
separately reproduced here.  `~ root()` strips it unconditionally, so
the same literal range works unmodified whether or not `trunk()`
needed the fallback: against a repo with a configured remote, `root()`
was never inside `trunk()::@` to begin with, and the subtraction is a
no-op.

Receipt: `jj help -k revsets` states `trunk()` "falls back to root()
if no matching remote bookmark exists" (`wf4-dives.json` Q3); the
local-only-trunk repro is `wf2-dives.json` Q4 evidence #3;
`design-decisions-final.md` lines 731-734.

## Escape hatch: `jj bisect run`

`gate.sh` does not implement tip-then-bisect, and does not need to at
PR-stack scale (1-10 commits): default per-revision GATE/REPORT
already delivers exact, single-pass failure attribution at negligible
jj-side cost (the 1.5-2ms/rev tax above).  Bisection pays off only
when a per-revision check is too expensive to run on *every* revision,
or a range is pathologically large -- neither is the common case this
skill targets.  Invoke it directly, outside `gate.sh`, only for that
case:

```sh
jj bisect run -- <cmd>
```

## Never wrap `gh`, `pip`, `pip3`, or `sbt` inside `jj run --`

R1 (constitutional): these four run **unsandboxed** at work.
`sandbox.excludedCommands` most plausibly matches on the same
top-level-command-string basis as the Bash permission matcher (the
live matcher was not directly inspectable here; treat this as the
conservative assumption).  A gate command like `jj run -- pip install
-e .` or `jj run -- sbt test` presents to that matcher as a
`jj`-prefixed string, not a `pip`- or `sbt`-prefixed one -- it would
run **sandboxed**, losing exactly the exemption those tools need, and
most likely fail closed against a denied package-index domain
(`pypi.org` is explicitly denied).  Same trap for `git rebase --exec
"<cmd>"` in git-only mode.  Any command needing that exemption is
issued as its own direct, top-level Bash command, never nested inside
`jj run --` or `git rebase --exec`.  Invariant 20; catalogued as trap
#13 in `references/traps.md` ("permission-tier laundering").  Receipt:
`wf4-dives.json` Q2, cross-cutting risk #3.

## Gate command provenance (`cmd_source`)

The other half of the same trap: the harness permission matcher sees
only the literal top-level Bash string, so anything composed inside
`jj run -- <cmd>` inherits the wrapper's tier and is never
independently re-parsed against the deny list -- a `<cmd>` built from
untrusted input could smuggle a denied command straight through.
`gate.sh`'s only available mitigation is read-side: the receipt
records exactly what it was given, `cmd` and `cmd_source` (hardcoded
`"argv"`), so a review can audit what actually ran.  It does not, and
cannot, verify that the command came from a reviewed, effectively
static per-repo set -- that half is prompt-enforced, the caller's
responsibility, never freely composed at runtime.  Invariant 21;
accepted residual risk, not a solved problem.  Receipt:
`wf4-dives.json` Q2, cross-cutting risk #2.

---

Doc: `design-decisions-final.md` D1.3.  Invariants 6-8, 20-21.
