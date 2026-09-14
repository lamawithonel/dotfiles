#!/bin/sh
# compat_probe.sh -- re-execute the command surface this skill
# documents against the installed binaries and report drift.
#
# Feature claims only.  A claim asserts that a tool is present, or that
# a command, flag, revset, or config key still behaves as documented.
# No claim asserts a version: versions move on their own schedule and
# behaviour is the contract, so a pinned number only ever produced
# false drift.
#
# A missing tool fails its presence claim AND every claim that needed
# it, each by name.  An absence claim (push-no-force-flag) must never
# pass vacuously because the binary is gone.
#
# Receipt: vcs-compat-probe/2 JSON at
#   ~/.agents/.local/state/vcs-workflow/compat-probe.json
# written via temp file + mv.  Runs standalone, from a pitchfork cron,
# or on demand; preflight reads the receipt's mtime rather than
# re-running this.
#
# Exit: 0 green, 1 drift.

set -o nounset

OUT_DIR="$HOME/.agents/.local/state/vcs-workflow"
OUT="$OUT_DIR/compat-probe.json"
PASSED=0
FAILED=''

# Claims that need the throwaway jj store.  Named here so they can be
# failed individually when the store cannot be built.
STORE_CLAIMS='revset-conflicts revset-description-substring revset-bookmarks-exact config-repo-roundtrip snapshot-auto-track'

_fail() {
	FAILED="$FAILED $1"
	printf 'probe: FAIL %s\n' "$1" >&2
}

_pass() {
	PASSED=$((PASSED + 1))
}

_claim() {
	# _claim <name> <cmd...>: pass iff the command exits 0.
	_name=$1
	shift
	if "$@" > /dev/null 2>&1; then
		_pass
	else
		_fail "$_name"
	fi
}

_flag_claim() {
	# _flag_claim <name> <needle> <cmd...>: pass iff help text
	# contains the needle.  Never gate on grep alone: the help
	# command itself failing is also a drift signal.
	_name=$1
	_needle=$2
	shift 2
	if "$@" 2> /dev/null | grep -q -- "$_needle"; then
		_pass
	else
		_fail "$_name"
	fi
}

_jj() {
	# jj against the throwaway store, with a throwaway config home: jj
	# keys --repo config by store id under $XDG_CONFIG_HOME/jj/repos, so
	# without the redirect every probe run leaves a dead directory behind
	# in the real config tree.  env scopes the redirect to the child, so
	# the probe never mutates its own environment and the redirect cannot
	# outlive the temp tree.  Callable only from _revset_claims, which
	# owns $_tmp.  The redirect costs the user config, which the claims
	# below do not need.
	env XDG_CONFIG_HOME="$_tmp/config" jj "$@"
}

_revset_claims() {
	# Parse-check the documented revsets in a throwaway store, plus the
	# --repo config round-trips.  Store and config are discarded
	# together afterward.
	# An unchecked mktemp would leave $_tmp empty, aiming the store at
	# /store and the throwaway config home at /config; the emptiness test
	# short-circuits so _jj is never reached with those.
	_tmp=$(mktemp -d "${TMPDIR:-/tmp}/compat-probe.XXXXXX") || _tmp=''
	_store="$_tmp/store"
	if [ -z "$_tmp" ] || ! _jj git init "$_store" > /dev/null 2>&1; then
		_fail 'tmp-store-init'
		for _name in $STORE_CLAIMS; do
			_fail "$_name"
		done
		[ -z "$_tmp" ] || rm -rf "$_tmp"
		return 0
	fi
	_pass
	_claim 'revset-conflicts' \
		_jj -R "$_store" log -r 'conflicts() & ~::remote_bookmarks()' --no-graph -T 'commit_id'
	_claim 'revset-description-substring' \
		_jj -R "$_store" log -r 'description(substring:"x")' --no-graph -T 'commit_id'
	_claim 'revset-bookmarks-exact' \
		_jj -R "$_store" log -r 'bookmarks(exact:"main") & ~immutable()' --no-graph -T 'commit_id'
	_claim 'config-repo-roundtrip' \
		_jj -R "$_store" config set --repo ui.editor ':true'
	# The set is deliberately unchecked: the read-back is the claim,
	# and it fails by name when the write did not land.
	_jj -R "$_store" config set --repo snapshot.auto-track 'none' > /dev/null 2>&1 || :
	_flag_claim 'snapshot-auto-track' 'none' \
		_jj -R "$_store" config list --repo snapshot.auto-track
	rm -rf "$_tmp"
}

_receipt_json() {
	# Receipt body on stdout; the caller redirects, so a failed write is
	# visible in this function's exit status.  Reads the counters and
	# $_verdict the claims above leave behind.
	cat <<- EOF
		{
		  "schema": "vcs-compat-probe/2",
		  "probed_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
		  "claims": { "passed": $PASSED, "failed": [$_failed_json] },
		  "verdict": "$_verdict"
		}
	EOF
}

_claim 'jj-present' command -v jj
_claim 'git-present' command -v git
_claim 'jq-present' command -v jq

_flag_claim 'run-ignore-changes' '--ignore-changes' jj run --help
_flag_claim 'run-jobs' '--jobs' jj run --help
_flag_claim 'absorb-into' '--into' jj absorb --help
_flag_claim 'absorb-from' '--from' jj absorb --help
_flag_claim 'split-tool' '--tool' jj split --help
_flag_claim 'split-message' '--message' jj split --help
_flag_claim 'describe-stdin' '--stdin' jj describe --help
_flag_claim 'push-dry-run' '--dry-run' jj git push --help
_flag_claim 'restore-from' '--from' jj restore --help
# Absence claim: jj git push must define NO force flag.  Match flag
# definition lines only (help prose mentions git's --force-with-lease
# by analogy; that is not a flag).  Guarded on help availability: an
# absence claim must never pass vacuously because jj itself is absent.
if ! jj git push --help > /dev/null 2>&1; then
	_fail 'push-no-force-flag'
elif jj git push --help 2> /dev/null | grep -qE '^[[:space:]]*(-f, )?--force'; then
	_fail 'push-no-force-flag'
else
	_pass
fi
_claim 'bisect-run' jj bisect run --help
_claim 'fix' jj fix --help
_claim 'op-restore' jj op restore --help
_claim 'workspace-update-stale' jj workspace update-stale --help
_claim 'workspace-forget' jj workspace forget --help
_claim 'git-colocation' jj git colocation --help

_revset_claims

if [ -n "$FAILED" ]; then
	_verdict='drift'
else
	_verdict='green'
fi

mkdir -p "$OUT_DIR" || {
	printf 'PROBE-FAIL receipt-dir\n'
	exit 1
}
_failed_json=$(printf '%s' "$FAILED" | awk '{for(i=1;i<=NF;i++)printf "%s\"%s\"",(i>1?",":""),$i}')
_tmp_out="$OUT.tmp"
# Write and rename are chained: a half-written or unrenamable receipt is
# removed and reported, never left beside a stale one under a green line.
if ! _receipt_json > "$_tmp_out" || ! mv "$_tmp_out" "$OUT"; then
	rm -f "$_tmp_out"
	printf 'PROBE-FAIL receipt-write\n'
	exit 1
fi

printf 'PROBE-%s passed=%d failed=[%s] receipt=%s\n' \
	"$(printf '%s' "$_verdict" | tr '[:lower:]' '[:upper:]')" \
	"$PASSED" "${FAILED# }" "$OUT"
[ "$_verdict" = 'green' ]
