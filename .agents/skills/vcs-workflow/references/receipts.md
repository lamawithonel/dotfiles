# Receipts

Three JSON schemas plus one non-JSON journal projection.  Every field
below is a shell exit code, a `jj log -T` projection, or a parsed JSON
value -- never agent prose (P-RECEIPTS).  Field lists are read from
the shipped scripts, not from the design-doc draft; every place the
two disagree is called out explicitly, because the draft is not what
runs.

Who reads the handoff receipt: this skill's handoff step and the
pre-serialization checklist in `serialization.md`.  `git-commit` does
not -- it is the codex on commit craft and takes its input from the
prepared revisions themselves, so nothing in the receipt is an
instruction to it.

Adjacent detail lives elsewhere and is not repeated here: the gate's
flag matrix and `-j` warmth policy are in `verify.md`; the conflict
revset and marker tokens are in `conflicts.md`; the conversion levels
and the keys each one writes are in `onboarding.md` and
`safety-net.md`.

## vcs-handoff/2

Path: `<primary-root>/.local/state/agents/vcs/handoff.json`
Emitted by: `scripts/emit_handoff.sh [--range REVSET]`

The path is the PRIMARY workspace root, resolved through the
`.jj/repo` pointer file when the script runs inside a secondary jj
workspace -- an ephemeral workspace never gets a receipt of its own.

| Exit | Meaning | Receipt written? |
| :--- | :--- | :--- |
| 0 | `HANDOFF-OK` -- ready | yes, full |
| 1 | `HANDOFF-NOT-READY` -- fails[] non-empty | yes, full |
| 1 | `HANDOFF-FAIL jq assembly failed` | no -- previous receipt intact |
| 2 | usage -- bad `--range` invocation | no |
| 3 | `detect_shape.sh` returned `worktree-shadowed` | no |
| 5 | `HANDOFF-FAIL shape=git-only` or `shape=none` | no |
| 6 | `HANDOFF-FAIL LEVEL-BLOCKED level=oplog` | no |

Exit 1 is overloaded between two unrelated failure modes.  Do not
branch on the exit code alone -- grep the printed message prefix.
The assembly path is atomic: jq writes `handoff.json.tmp` and the
script `mv`s it into place only on success, removing the temp file
otherwise.  A failed run therefore leaves the previous good receipt
untouched -- stale, never truncated.  Check `probed_at`-style
freshness against the run you care about rather than trusting
existence alone.

Exit 5 is emitted immediately after `detect_shape.sh`, before
preflight and before any jj command: a repository with no store has
nothing to hand off, and `references/onboarding.md` covers converting
it.

Exit 6 is the level gate, checked after the shape and the workspace
but before the state directory is created and before preflight runs.
At `oplog` the pipeline stops at capture, so there is no prepared
stack to describe, and the receipt directory itself would surface as
an untracked path in a third-party checkout -- so nothing is written
anywhere, not even the directory.  The level is read at the primary
root, the same reader `preflight.sh`, `gate.sh`, `promote.sh`, and
`absorb_safe.sh` use.

Field shape as shipped, in written order:

```
schema         "vcs-handoff/2"
shape          colocated | jj-only | jj-workspace
level          oplog | standard | full
toolchain      {probe_verdict, probe_at}
preflight      {ok, protected[], store_id, editor_guard}
base           {revset, commit_id, op_id, fetched{ran, op_id}}
stack[]        {change_id, commit_id, first_line, files[]}
gate           <verbatim contents of gate.json, or null>
absorb         {ran, op_id, destinations[], residual, renames_blocked}
partition      {grain, splits[], refused[]}
conflicts[]
message_hints  {scope}
workspace      {name, is_secondary, primary_root}
repo           {root, origin_url}
ready          true | false
fails[]        subset of {preflight, gate, conflicts}
warns[]        fetch-not-run, probe-<verdict>, probe-stale
```

Field-by-field, what the script actually puts there:

- `level` is `git config --get vcs-workflow.level` read at the
  primary root; an unset or empty key reads as `"full"`, the same
  default `preflight.sh` and `gate.sh` resolve to.  It records what
  the repository was converted at, not what this run was asked for.
- `toolchain` carries exactly two fields, both copied verbatim from
  `compat-probe.json`: `probe_verdict` and `probe_at`.  There are no
  version fields -- the probe asserts behaviour, not versions.
  `probe_verdict` is `"missing"` when that file does not exist and
  `"unreadable"` when `jq` cannot parse it; otherwise it is whatever
  `compat_probe.sh` last wrote (`"green"` or `"drift"`).
- `preflight.ok` is `true` iff the fresh `preflight.sh` run this
  script triggers exits 0.  `preflight.protected[]` and
  `preflight.store_id` are `sed`-scraped from that run's
  `protected=[...]` and `store=...` stdout tokens -- not re-parsed
  from any file.  `preflight.editor_guard` mirrors `preflight.ok`
  exactly; it is not independently checked.
- `base.revset` is the **literal string `"trunk()"`**, always -- it
  names the promotion base pointer, not the stack revset.  The actual
  range used to build `stack[]` (the default
  `(trunk()::@-) ~ root()`, or the caller's `--range` override) is
  not recorded anywhere in this receipt.  Do not read `base.revset`
  as "the range that was gated."
- `base.fetched.ran` is the literal `false` and `base.fetched.op_id`
  is the literal `null`, always -- this script never runs fetch.  This
  is also why `warns[]` always carries `fetch-not-run` (below).
- `stack[]` entries carry only `change_id`, `commit_id`,
  `first_line`, and `files[]`.  There is **no per-revision `gate`
  field**, despite the draft schema listing one -- per-revision gate
  status does not exist anywhere in v1; only the aggregate top-level
  `gate` object (below) is available.
- `gate` is the entire contents of `gate.json` (see vcs-gate/1) copied
  in as-is, or JSON `null` if `gate.sh` has never run in this repo.
  It is a whole-range verdict, never a per-stack-entry one.
- `absorb` and `partition` are static placeholders, always emitted as
  `{ran: false, op_id: null, destinations: [], residual: null,
  renames_blocked: false}` and `{grain: "file", splits: [],
  refused: []}` respectively, regardless of whether `jj absorb` or
  `jj split` actually ran earlier in the session's pipeline.  Treat
  both as "not tracked by this receipt," never as "absorb/partition
  did not happen."
- `conflicts[]` is real: `jj log -r 'conflicts() & (RANGE)'`
  change-ids, and it **does** honor `--range` (unlike `base.revset`).
- `message_hints` carries one field, `scope`: a pure path
  computation, the common leading path segment across every changed
  file in the stack, else the shared file stem, else `""`.  There is
  no symbol list -- nothing in this skill parses source structure.
- `workspace.name` is the working copy's own workspace name
  (`default` in a single-workspace repo).  `workspace.is_secondary`
  is `true` iff `<jj root>/.jj/repo` is a pointer FILE rather than a
  directory, and `workspace.primary_root` is that pointer resolved to
  a physical path -- the same value as `repo.root`.
- `repo.origin_url` is `git config --get remote.origin.url` at the
  primary root, or JSON `null` when there is no such remote.  A
  `null` here is why `promote.sh` can have nothing to push to.
- `ready` is `true` iff `preflight.ok` is true, `gate.verdict` (from
  the embedded `gate` object) is `"pass"`, and `conflicts[]` is
  empty.  `fails[]` is the subset of `{preflight, gate, conflicts}`
  that failed that test.
- `warns[]` always contains `fetch-not-run` (unconditional, per the
  `base.fetched.ran` note above), plus `probe-<verdict>` whenever
  `toolchain.probe_verdict` is not `"green"` -- so one of
  `probe-drift`, `probe-missing`, or `probe-unreadable` -- plus
  `probe-stale` whenever the probe receipt is missing or older than
  seven days.

## vcs-gate/1

Path: `<repo>/.local/state/agents/vcs/gate.json`
Emitted by:
`scripts/gate.sh [--range REVSET] [--cheap] [--report] [--final-clean]
-- CMD [ARG...]`

| Exit | Meaning | Receipt written? |
| :--- | :--- | :--- |
| 0 | `GATE-PASS` | yes |
| 1 | `GATE-FAIL` | yes |
| 2 | usage -- bad flags, or no `-- CMD` | no |
| 3 | `detect_shape.sh` returned `worktree-shadowed` | no |
| 4 | `CONFLICT-BLOCKED` | no |
| 5 | wrong shape (git-only; jj shapes only) | no |

Only exit 0 and 1 touch `gate.json`; exits 2, 3, 4, and 5 leave
whatever receipt was already on disk untouched.  A caller that reads
`gate.json` without also checking `gate.sh`'s own last exit code can
read a **stale pass** left over from an earlier, unrelated run --
`promote.sh` only checks `.verdict`, so this is the one way a `pass`
gets consumed that does not correspond to the range just gated.

```
schema            "vcs-gate/1"
mode              "GATE" | "REPORT"
cmd[]             argv after `--`, verbatim
cmd_source        "argv"
range             the REVSET this run gated
j                  integer job count actually used
warm               0 | 1                  (JSON number, not boolean)
red_expected[]     change-ids tolerated as RED (REPORT mode only)
verdict           "pass" | "fail"
failed_change_id   change-id, or "" when verdict is "pass"
exit               see below -- meaning depends on mode
```

- `cmd_source` is the literal string `"argv"` unconditionally; it
  names the mechanism (parsed from the command line), not whether
  those argv came from the reviewed static set invariant 21 requires.
  Membership in that set is still prompt-enforced by whoever calls
  `gate.sh` -- this field cannot verify it.
- `mode` is `"REPORT"` when `--report` is passed or the range
  contains any `Verification-Status: red-expected` trailer;
  `"GATE"` otherwise.
- `j` and `warm`: `warm` reflects whether
  `<repo>/.local/state/agents/vcs/gate-warm` existed at the start of
  this run.  That sentinel is written after any passing run that was
  not `--cheap` and not `--final-clean`, and deleted by
  `--final-clean`.  `--cheap` or a warm sentinel both force
  `j = nproc`; a cold, non-cheap run forces `j = 1`.
- `exit`'s meaning depends on `mode`: in `GATE` mode it is the raw
  exit code of the single ranged `jj run`.  In `REPORT` mode it is
  synthetic -- `0` if every revision either passed or was a marked
  RED-expected tolerance, `1` if any unmarked revision failed --
  never the underlying per-revision `jj run` exit code.

## vcs-compat-probe/2

Path: `~/.agents/.local/state/vcs-workflow/compat-probe.json`
(host-level, not repo-level -- toolchain drift is a property of the
machine).  Written to a temp file and `mv`d into place.
Emitted by: `scripts/compat_probe.sh` (no arguments).
Exit: `0` when `verdict` is `"green"`, `1` when `"drift"`.  There is
no usage-error path; the script takes no flags.

A receipt that cannot be written is reported, never passed over.  When
the state directory cannot be created the script prints
`PROBE-FAIL receipt-dir` on stdout and exits 1; when the temp file
cannot be written, or cannot be renamed into place, it removes the
temp file, prints `PROBE-FAIL receipt-write` on stdout, and exits 1.
Either way no `PROBE-GREEN` line is printed and any previous receipt
is left exactly as it was -- so a `PROBE-FAIL` line means the claims
may well have passed while their record did not land, and the verdict
on disk is whatever the last successful run wrote.

```
schema         "vcs-compat-probe/2"
probed_at      UTC ISO-8601, `date -u +%Y-%m-%dT%H:%M:%SZ`
claims         {passed: <int>, failed: [<claim-name>, ...]}
verdict        "green" | "drift"
```

Four fields, and no others: no tool versions, no pin comparison, no
schema-version duplicate.  Every claim asserts behaviour -- a tool is
present, or a command, flag, revset, or config key still works as
documented -- because a pinned version number only ever produced
false drift.

- `verdict` is `"drift"` iff `claims.failed[]` is non-empty, and the
  stdout receipt says the same thing in one line:
  `PROBE-GREEN passed=<N> failed=[] receipt=<path>`, or
  `PROBE-DRIFT passed=<N> failed=[name name] receipt=<path>`.
  Per-claim diagnostics (`probe: FAIL <name>`) go to stderr.
- Every failure is named.  A missing tool fails its own presence
  claim AND every claim that needed it, each by name, so a drift
  report is a work list rather than a single opaque verdict.  The one
  absence claim, `push-no-force-flag`, is guarded so it can never
  pass vacuously when `jj` itself is gone (`references/traps.md` #25
  and #26).
- Staleness is separate from drift.  A green receipt older than seven
  days still says `"green"`; `preflight.sh` reports `probe=stale` in
  its receipt and `emit_handoff.sh` adds `probe-stale` to `warns[]`,
  neither of which fails a run.  Re-run the probe rather than
  reasoning about the age yourself.

## Journal projection (D1.6, invariant 25) -- not a JSON receipt

No script in this skill emits the promotion journal; `promote.sh`
prints `PROMOTE-OK` / `PROMOTE-FAIL` and nothing else -- there is no
`emit_journal.sh`.  Invariant 25 ("every promotion writes one journal
block ... reconstructible from `jj op log`") is **prompt-enforced**:
the calling agent writes the block by hand, after every successful
`promote.sh` run, one YAML block per promotion (never per capture).

Fields: `op_before`, `op_after`, `change_ids[]`, `gate_verdict`,
`receipt_path`, `shape`.  Session id goes in the header comment only,
never in the path or the fields themselves.  The canonical
reconstruction command is:

```sh
jj op show -p <op_id>
```

Any journal entry that cannot be rebuilt from `jj op log` this way is
malformed by definition -- the oplog is truth, the journal is only an
index into it.

## The `reference-transaction` false-negative hazard (invariant 22)

One git hook survives under jj authorship: `reference-transaction`,
and it fires on exactly one path, `jj git push`, at its `prepared`
stage.  A hook that exits nonzero at `prepared` makes `jj git push`
report failure -- nonzero exit, error text on stderr -- **after the
remote has already been updated**.  A nonzero `jj git push` exit is
therefore never proof the remote is unchanged.

This hazard is scoped to `promote.sh`'s push step alone.  `gate.sh`
only runs `jj run` locally and never pushes; `emit_handoff.sh` and
`compat_probe.sh` touch no remote either.  None of the three can hit
this hook.

`promote.sh`'s `_push()` is where invariant 22 is enforced.  On any
`jj git push` failure it does not retry blindly -- it re-queries the
remote before failing:

```sh
jj log -r 'remote_bookmarks()' --no-graph \
	-T 'commit_id.short() ++ " " ++ bookmarks ++ "\n"'
```

printed to stderr right after the banner
`promote: push failed; remote state may STILL have changed
(reference-transaction hooks lie).  Re-query before retrying:`.
`promote.sh` still exits 1 either way -- it never auto-retries and
never auto-classifies the failure as real or spurious.  The re-query
is tool-enforced (it always runs on push failure); reading its output
and deciding whether the target commit already landed at the
push-target bookmark, versus genuinely retrying, is prompt-enforced.
Compare the re-queried `commit_id` for the bookmark against the
`REV` `promote.sh` was asked to push: if it already matches, the push
in fact succeeded and a retry is redundant; if it does not, the push
genuinely failed and retrying is safe.
