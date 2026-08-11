# Receipts

Four JSON schemas plus one non-JSON journal projection.  Every field
below is a shell exit code, a `jj log -T` projection, or a parsed JSON
value -- never agent prose (P-RECEIPTS).  Field lists are read from
the shipped scripts, not from the design-doc draft; every place the
two disagree is called out explicitly, because the draft is not what
runs.

Adjacent detail lives elsewhere and is not repeated here: the gate's
flag matrix and `-j` warmth policy are in `verify.md`; the conflict
revset and marker tokens are in `conflicts.md`; the bootstrap
integrity ladder is in `bootstrap-locked.md`.

## vcs-handoff/1

Path: `<repo>/.local/state/agents/vcs/handoff.json`
Emitted by: `scripts/emit_handoff.sh [--range REVSET]`

| Exit | Meaning | Receipt written? |
| :--- | :--- | :--- |
| 0 | `HANDOFF-OK` -- ready | yes, full |
| 1 | `HANDOFF-NOT-READY` -- fails[] non-empty | yes, full |
| 1 | `HANDOFF-FAIL jq assembly failed` | **yes, but truncated to empty** |
| 2 | usage -- bad `--range` invocation | no |
| 3 | `detect_shape.sh` returned `worktree-shadowed` | no |

Exit 1 is overloaded between two unrelated failure modes.  Do not
branch on the exit code alone -- grep the printed message prefix.
The jq-assembly-failure path is rare but dangerous: the shell's `>`
redirect truncates `handoff.json` before jq runs, so on that one path
the previous good receipt is gone and the new one is zero bytes.  A
reader that only checks "does the file exist" after this path gets a
present-but-empty file, not a stale-but-valid one.

Field shape as shipped:

```
schema         "vcs-handoff/1"
shape          colocated | jj-only | jj-workspace | git-only
toolchain      {jj, ast_grep, difftastic, probe_verdict, probe_at}
preflight      {ok, protected[], store_id, editor_guard}
base           {revset, commit_id, op_id, fetched{ran, op_id}}
stack[]        {change_id, commit_id, first_line, files[]}
gate           <verbatim contents of gate.json, or null>
absorb         {ran, op_id, destinations[], residual, renames_blocked}
partition      {grain, splits[], refused[]}
conflicts[]
message_hints  {scope, symbols[], symbols_source}
ready, fails[], warns[]
```

Field-by-field, what the script actually puts there:

- `toolchain.jj`, `toolchain.ast_grep`, `toolchain.difftastic` are the
  literal JSON `null` unconditionally in v1 -- nothing populates them.
  Only `toolchain.probe_verdict` and `toolchain.probe_at` are real,
  copied verbatim from `compat-probe.json`.  `probe_verdict` is
  `"missing"` when that file does not exist and `"unreadable"` when
  `jq` cannot parse it; otherwise it is whatever
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
- `message_hints.scope` is a pure path computation: the common leading
  path segment across every changed file in the stack, else the
  shared file stem, else `""`.  `message_hints.symbols[]` is the
  literal `[]` and `symbols_source` is the literal `"none"`,
  always -- the read-only `ast-grep --json` scan the design doc
  describes is not implemented in this script.
- `ready` is `true` iff `preflight.ok` is true, `gate.verdict` (from
  the embedded `gate` object) is `"pass"`, and `conflicts[]` is
  empty.  `fails[]` is the subset of `{preflight, gate, conflicts}`
  that failed that test.
- `warns[]` always contains `fetch-not-run` (unconditional, per the
  `base.fetched.ran` note above), plus `probe-<verdict>` whenever
  `toolchain.probe_verdict` is not `"green"` -- so one of
  `probe-drift`, `probe-missing`, or `probe-unreadable`.

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

## vcs-compat-probe/1

Path: `~/.agents/.local/state/vcs-workflow/compat-probe.json`
(host-level, not repo-level -- toolchain drift is a property of the
machine).
Emitted by: `scripts/compat_probe.sh` (no arguments).
Exit: `0` when `verdict` is `"green"`, `1` when `"drift"`.  There is
no usage-error path; the script takes no flags.

```
schema         "vcs-compat-probe/1"
probed_at      UTC ISO-8601, `date -u +%Y-%m-%dT%H:%M:%SZ`
tools          {jj, ast-grep, difftastic} -> raw first line of
               `<bin> --version`
claims         {passed: <int>, failed: [<claim-name>, ...]}
pins_behind[]  "<owner/repo>:pinned=<X>,latest=<Y>"
verdict        "green" | "drift"
probe_version  "1"
```

- `verdict` is `"drift"` iff `claims.failed[]` is non-empty.
  `pins_behind[]` never affects `verdict` -- it is populated from
  `gh release view` against the three GH-released repos (`jj-vcs/jj`,
  `ast-grep/ast-grep`, `Wilfred/difftastic`) and is silently skipped
  entirely when `gh` is absent.  Staleness is a choice; drift is a
  defect (per the script's own header comment).

**7-day staleness, D1.10 vs. shipped**: D1.10 specifies that
`vcs-handoff/1`'s copy of `probe_verdict` carries "a staleness warning
past 7 days."  **This is not implemented in `emit_handoff.sh`.**  The
script copies `probe_at` into `toolchain.probe_at` verbatim and only
ever warns on `probe_verdict != "green"` (see vcs-handoff/1 above); no
code path compares `probe_at` against the current time.  A probe
receipt that is 30 days old and still says `"green"` produces a
silent, warning-free `ready=true`.  Check staleness yourself before
trusting an old `"green"`:

```sh
_age=$(( $(date -u +%s) - $(date -u -d "$probe_at" +%s) ))
[ "$_age" -lt 604800 ]   # 7 days, in seconds
```

## vcs-compat-recover/1

Path: `~/.agents/.local/state/vcs-workflow/compat-recover.json`
Emitted by: `scripts/gh_recover.sh [ARGS...]` (forwarded verbatim to
`bootstrap_work.sh`, e.g. `--with-cocogitto`).
Exit: `0` when `verdict` is `"recovered"`, `1` when `"not-recovered"`.

```
schema           "vcs-compat-recover/1"
recovered_at     UTC ISO-8601
bootstrap_exit   raw exit code of bootstrap_work.sh
probe_exit       raw exit code of the closing compat_probe.sh re-run
verdict          "recovered" | "not-recovered"
```

- `verdict` is `"recovered"` iff **both** `bootstrap_exit == 0` and
  `probe_exit == 0`.
- **This is much smaller than D1.5's draft schema.**  The draft lists
  per-tool granularity -- `tool`, `pinned_version`,
  `installed_version_before/after`, `probe_before{verdict, drift[]}`,
  `source{owner_repo, tag, asset, browser_download_url}`,
  `integrity{method, verified, sha256}`,
  `install{staged_path, live_path, symlinks_updated[],
  mise_network_used}`, `probe_after{verdict, drift[]}`,
  `ready`, `fails[]`, `warns[]`.  None of that ships.  The shipped
  receipt is the five fields above: two raw exit codes and a derived
  verdict.  Per-tool install detail, if you need it, is only in
  `bootstrap_work.sh`'s own stdout/stderr -- capture that separately.
- `gh_recover.sh` does not snapshot the **prior** probe state before
  running `bootstrap_work.sh`; it runs `compat_probe.sh` exactly once,
  at the end, as the closing check.  There is no `probe_before` to
  read.  If you need a before/after `claims.failed[]` diff, copy
  `compat-probe.json` aside yourself before invoking `gh_recover.sh`.

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
only runs `jj run` locally and never pushes; `emit_handoff.sh`,
`compat_probe.sh`, and `gh_recover.sh` touch no remote either.  None
of those four can hit this hook.

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
