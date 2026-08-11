# Work-machine bootstrap: locked host, gh-first

Scope: any host where `gh` sits in `sandbox.excludedCommands`.  Covers
`scripts/bootstrap_work.sh` (first install) and `scripts/gh_recover.sh`
(drift remediation).  Toolchain of record: jj 0.44.0, ast-grep 0.45.1,
difftastic 0.70.0 (cocogitto 7.0.0, opt-in).  Pins live in
`bootstrap_work.sh`'s `bootstrap_tool` calls and in
`compat_probe.sh`'s `*_PIN` variables -- both are the source of truth;
this file is not.  A host where `gh` is NOT sandbox-excluded falls
back to the wf2 allowlist-request bootstrap instead; that path is not
this file's scope.

## 1. Why `gh`, not `mise install` (R1)

- `gh`, `pip`, `pip3`, and `sbt` run unsandboxed at work
  (`sandbox.excludedCommands`).  `gh`'s own HTTPS traffic to GitHub
  never touches the sandbox's domain allowlist at all -- there is
  nothing to allowlist.
- `gh` is already authenticated on the work host; no separate TLS or
  credential setup is needed (first-party, not a proxied path).
- No egress-allowlist request is made or needed: `mise install`'s
  aqua downloader is the only thing that would have needed
  `release-assets.githubusercontent.com`, and the gh-first path never
  runs it.
- No mise security feature is ever disabled to route around the
  above.  `MISE_AQUA_GITHUB_ATTESTATIONS=false` is forbidden,
  unconditionally, by R1 -- not weighed case by case.
- Net effect: prior open items 1.11a/6.7-1 (allowlist the attestation
  CDN host, or disable the mise toggle?) and 1.11b/6.7-2 (exact host
  or wildcard?) are both MOOT here, not resolved by picking a branch.
  The mise/aqua network path they argued about is simply never
  invoked by this bootstrap.  (D1.11)

## 2. The integrity ladder

0 of the 4 upstream repos (jj-vcs/jj, ast-grep/ast-grep,
Wilfred/difftastic, cocogitto/cocogitto) publish a checksums asset, a
checksum line in the release body, or a GitHub Artifact Attestation,
confirmed live on 2026-08-10 (`gh attestation verify` returned HTTP
404 for all four, both `--repo`- and `--owner`-scoped).  Given that,
`bootstrap_work.sh` runs a fixed ladder per tool, never skipped, never
reordered:

| Rung | Mechanism | Script behavior |
| :-- | :-- | :-- |
| 1 | `gh attestation verify <file> --repo <owner>/<repo>` | Best-effort.  `verify_attestation()` treats an output matching `*"HTTP 404"*"attestations/sha256:"*` as the known no-attestation-published gap and continues; ANY other failure shape is `die`-fatal.  The day one of these projects starts publishing attestations, this rung starts actually gating on it -- no script change needed. |
| 2 | TOFU sha256 pinned in `bootstrap_tool`'s call site | `sha256_of "$_dl_file"` compared against the literal hex in the call; mismatch is fatal: `die "... P-FAIL-CLOSED, refusing to install"`.  This pin, not the attestation check, is the real integrity anchor today. |
| 3 | Releases-API server-computed `digest` | NOT invoked by the shipped script.  It is a manual cross-check available to whoever bumps a pin: `gh api repos/<owner>/<repo>/releases/tags/<tag> --jq '.assets[]|select(.name=="<asset>").digest'`, verified byte-identical to a local `sha256sum` of the 10.6MB jj tarball during the wave-4 dive.  Run it by hand before pasting a new hash into `bootstrap_tool`; the "MANIFEST CAPTURE" header comment in the script only lists `gh release view` / `gh release download` / `sha256sum` and does not call this out, so it is easy to skip -- don't. |
| 4 | Hard fail closed | If a rung above is neither satisfiable nor a confirmed non-fatal gap, the script exits 1 with nothing partially installed.  Never "proceed and record what we got." |

Undo: a corrupted or rejected download leaves no partial install --
`bootstrap_tool` downloads to a scratch dir (`$STATE_ROOT/.download/`)
and only `mv`s into the live `$STATE_ROOT/<name>/<version>/` path
after every check above passes.  Nothing to roll back on a fail-closed
exit.

This is invariant 23: no portable-core tool is installed or recovered
without passing this ladder; `pip install jj|jujutsu|cog` is never
run; no mise security feature is ever disabled.  Tool-enforced in
`bootstrap_work.sh` and `gh_recover.sh`, prompt-enforced everywhere
else this skill talks about installing tools.  (R1, D1.11)

## 3. Registration: `mise link` + `mise config set`

Two calls per tool, both network-free, both proven live under a
deliberately poisoned proxy:

- `mise link --force "${name}@${version}" "$install_dir"` -- mise's
  own documented mechanism for a binary built outside mise.  Pure
  filesystem symlink; 0.02-0.03s per tool in the wave-4 dive, zero
  warnings, zero retries.
- `mise config set --file "$GLOBAL_MISE_CFG" "tools.${name}"
  "$version"` -- writes TOML directly, ~0.015s, idempotent.

**Rejected: `mise use -g <tool>@<version>`.**  It unconditionally
probes `mise-versions.jdx.dev` then `api.github.com` with three
retries and exponential backoff, even when the version is already
linked.  Non-fatal, but pure latency, and it burns the org's shared
unauthenticated `api.github.com` rate limit for nothing.

**Rejected: `mise use --locked` / `MISE_LOCKED=1`.**  Hard-fails with
`No lockfile URL found for ... (--locked mode)`: it needs a
pre-existing `mise.lock` entry with a resolved URL and checksum, which
a gh-fetched-and-linked install never produces.

This generalizes past this one script: any future tool-version pin in
this skill uses `mise config set`, never `mise use`.  (D1.11)

Undo, a version bump: `bootstrap_tool` keys its install path by
`$STATE_ROOT/<name>/<version>/` (name+version tuple), so bumping a pin
to a new version never deletes the old one's directory -- it lands
beside it.  Reverting a bad bump is a single, network-free command:
`mise config set --file "$GLOBAL_MISE_CFG" tools.<name> <old-version>`
flips the active pin back immediately, because the old linked install
still exists.  Only re-running the SAME pinned version through
`gh_recover.sh` overwrites that version's directory (`rm -rf
"$_install_dir"` before the `mv`) -- that is deliberate drift-recovery
behavior, not a bump, and it has no separate undo beyond re-running
the ladder again.

## 4. The pip channel: `ast-grep-cli` only

`pip install ast-grep-cli` is the one working secondary channel: a
real wheel-bundled native binary at 0.45.1, exact version parity with
the GitHub release, no secondary runtime fetch.  Undo:
`pip uninstall ast-grep-cli`.

No PyPI package exists for difftastic or cocogitto under any obvious
name -- `difftastic`, `difftastic-bin`, `cocogitto`, and
`cocogitto-cli` all 404.  Don't spend a turn guessing at names.

**PYPI NAMESQUAT WARNING -- hard never-do (invariant 23).**  These
three `pip install` calls each silently install an unrelated package,
with no error to signal the mistake:

| Command | What actually installs |
| :-- | :-- |
| `pip install jj` | "Remote HTTP Mock" v2.14.1 |
| `pip install jujutsu` | a dubious v0.0.1 CLI claiming the aliases jujutsu/jutsu/jjz/jj2 |
| `pip install cog` | Replicate's ML container tool, v0.21.0 |

This is a real supply-chain trap reachable by pattern-matching "try
`pip install <toolname>`" -- treat it as forbidden vocabulary, not a
judgment call.  (D1.11)

`uv` is structurally dead for this purpose at work: `Bash(uv:*)` is
permission-allowed, but `uv` is absent from
`sandbox.excludedCommands`, so it runs sandboxed, and `pypi.org` is
explicitly in `deniedDomains`.  Permission-to-run and
sandbox-network-exemption are two independent systems; `uv` has only
the first.

## 5. `gh` is pre-provisioned

Treat `gh` as already present at work (IT image or system package
manager), consistent with it being sandbox-excluded and already
authenticated.  It is never installed via `mise install` there --
that path needs either the declined Azure attestation host or the
forbidden `MISE_AQUA_GITHUB_ATTESTATIONS=false` toggle, and both are
closed by R1.  If `gh` is ever actually missing at work, that is a
fresh USER-CALL -- raise it, don't route around it.  (D1.11)

## 6. Two invocation modes, equal standing (R5)

`bootstrap_work.sh` and `gh_recover.sh` run either agent-issued (where
the permission profile allows) or manually by the user in a plain
terminal (`!` prefix or otherwise) for one-off installs and occasional
updates.  Both scripts are mode-agnostic on purpose: same receipts,
same fail-closed verification, and neither mode may assume the other
ran first.  Nothing in either script branches on who invoked it.

## 7. Scheduled drift checks: pitchfork cron (R6)

`compat_probe.sh` (drift arm plus the bootstrap-freshness arm) is
registered as a user-session pitchfork cron on each host, with
`notify-send` on drift -- the same pattern as `benchmarks-refresh`.
This skill's `preflight.sh` reads the probe's LAST RECEIPT rather than
re-running the probe inline.  A missing or stale receipt, or a host
without pitchfork at all, degrades to an on-demand probe run --
pitchfork is an accelerator here, never load-bearing.

Receipt: `vcs-compat-probe/1` at
`~/.agents/.local/state/vcs-workflow/compat-probe.json` (host state,
not repo state -- toolchain drift is a property of the machine).
Fields, exactly as `compat_probe.sh` writes them: `schema`,
`probed_at`, `tools` (`jj`/`ast-grep`/`difftastic` -> version string),
`claims` (`passed` count, `failed` array), `pins_behind` (array of
`<repo>:pinned=<tag>,latest=<tag>`), `verdict` (`green`/`drift`),
`probe_version`.  `preflight.sh` treats the receipt as `ok` inside 7
days and `stale` past it (`find ... -mtime -7`); a stale or missing
receipt is `probe=missing`/`stale` in `preflight.sh`'s own one-line
output, not a hard failure.

On drift, remediation is `scripts/gh_recover.sh`, never
`mise install` -- the latter is sandboxed at work, blocked on the
release-asset CDN, and both workarounds around that are forbidden by
R1.  `gh_recover.sh` re-runs `bootstrap_work.sh` (full ladder from
section 2), then re-runs `compat_probe.sh` as the closing check, and
writes its OWN receipt, `vcs-compat-recover/1`, at
`~/.agents/.local/state/vcs-workflow/compat-recover.json`.  Its actual
fields, as shipped, are narrower than a full audit trail:
`schema`, `recovered_at`, `bootstrap_exit`, `probe_exit`, `verdict`
(`recovered`/`not-recovered`).  It does not itself record which tool
or version triggered the recovery -- that detail lives in the
`bootstrap_work.sh` log output and in the probe receipt's own
`pins_behind`/`failed` fields, not duplicated here.  Undo: recovery
has none beyond re-running the ladder (section 2/3's version-flip
undo applies if a specific bump is the problem, not the recovery
itself).  (D1.10)

## 8. Egress probing: `dig` / `nslookup`, never `curl`

Use `dig` / `nslookup` / `ping` to answer "can this host be reached at
all" -- all three are allow-tier at work, zero prompts, and DNS
resolution or ICMP reachability answers the question that matters
before a real fetch.  Example: `dig +short api.github.com` or
`nslookup release-assets.githubusercontent.com`.  Reserve `curl` for
the rare case a full TLS handshake plus an HTTP-200 body check is
genuinely required -- it is ask-tier, and reaching for it by default
spends a prompt the DNS check would have avoided.

## 9. First session at work: the prompt walkthrough

`jj` appears zero times in the work machine's `deny`, `allow`, `ask`,
and `sandbox.excludedCommands` arrays.  Standard mode forces
`disableBypassPermissionsMode` and `disableAutoMode` both to
`disable`, so bypass/auto cannot be enabled at all: every distinct jj
invocation prompts, with no session-persistent auto-allow, and (absent
a shipped allowlist) the whole tally resets to zero on the next fresh
session.

Walked against the CURRENT shipped pipeline (`preflight -> capture ->
absorb -> partition -> fetch -> restack -> verify -> promote ->
handoff`, `SKILL.md` ## The pipeline), a first, clean, happy-path run
issues 11 distinct first-time commands -- 5 script invocations (each
collapses its internal jj/git calls into ONE prompt, since the
permission layer only sees the top-level Bash string) and 6 raw jj
commands:

| # | Command | Pipeline step | Why it prompts |
| :-- | :-- | :-- | :-- |
| 1 | `scripts/detect_shape.sh` | Entry gate | Unlisted script; wraps `git rev-parse` + `jj root` into one prompt |
| 2 | `scripts/preflight.sh` | Preflight | Unlisted script; wraps 4x `jj config set --repo` + the closing assertion query |
| 3 | `jj status` | Capture (turn-boundary force-snapshot) | No jj subcommand is listed at all |
| 4 | `jj absorb <paths>` | Absorb | Same; distinct `jj absorb` prefix |
| 5 | `jj op show -p --summary` | Mandatory post-absorb audit | Same; distinct `jj op` prefix |
| 6 | `jj split <paths> -m '...'` | Partition | Same; distinct `jj split` prefix |
| 7 | `jj git fetch` | Fetch | Same; distinct `jj git` prefix |
| 8 | `jj rebase -d 'trunk()'` | Restack | Same; distinct `jj rebase` prefix |
| 9 | `scripts/gate.sh -- <cmd>` | Verify | Unlisted script; wraps the `conflicts()` check, the `jj run`, and the receipt emit |
| 10 | `scripts/promote.sh BOOKMARK [REV]` | Promote | Unlisted script; wraps the gate-receipt check, the RED/undescribed scans, `jj bookmark set`, `--dry-run` push, and the real push into one prompt |
| 11 | `scripts/emit_handoff.sh` | Handoff | Unlisted script |

`scripts/compat_probe.sh` adds a conditional 12th prompt only if the
pitchfork receipt (section 7) is missing or stale this session, not on
every run.  Conflict handling (`jj resolve --list`, etc.) adds more on
the branches that hit it; this table is the happy path only.

Two open questions the wave-4 dive could not close from the JSON
alone, carried forward rather than guessed at: whether the Bash
permission matcher keys on a two-token prefix (`jj op` covering both
`jj op show` and `jj op log`) or the full literal command string per
invocation, and whether this specific enterprise-managed settings
layer even accepts project- or user-level `permissions` additions at
all, or whether that needs an administrator.  Verify both live before
trusting the count above past a first session.

**Note on the count of 12.**  The design-decisions doc frames the
suggested allowlist as removing 2 of 12 distinct first-run prompts
(`jj status`, `jj op show`), roughly 17%.  That 12 was measured before
`promote.sh` existed as a single script wrapping the bookmark-move,
dry-run, and push calls that were previously three separate raw-jj
prompts (rows 10-12 in the earlier draft); folded into row 10 above,
the happy-path total is 11, and the same two removable prompts (rows
3 and 5) are now roughly 18% of the total instead of 17% -- the
removal, not the base count, is the number to trust.  Rows 3 and 5 are
the ones worth allowlisting: they recur every turn and every absorb
respectively, unlike the other 9 which fire once per session.

**The allowlist itself is not reproduced here.**  It lives in
`design-decisions-final.md` section 4 ("SUGGESTED WORK PERMISSIONS
SNIPPET") and is summarized in `SKILL.md`'s `## Toolchain` section --
read it there so this file never drifts out of sync with the ratified
JSON.  Undo: it is a `permissions.allow`/`permissions.ask` merge into
existing `settings.json` arrays; reverting is deleting the added
entries.

## 10. Adjacent gap: npm/yarn/pnpm are network-DOA

`npm install`, `yarn`, and `pnpm` are permission-allowed at work, but
their registries (`www.npmjs.com`, `registry.yarnpkg.com`, and
everything else by omission under `allowManagedDomainsOnly: true`)
are network-denied.  Permission-to-run and network-egress are the same
two independent systems as `uv` in section 4: allowed to execute,
denied on the wire.  Relevant to `gate.sh` on any JS/TS repo at
work -- expect a silent network failure, not a permission prompt, and
don't burn a turn diagnosing it as something else.  (D1.11)
