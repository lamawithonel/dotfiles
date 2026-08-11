#!/bin/sh
# compat_probe.sh -- verify the installed toolchain still matches every
# command, flag, and revset this skill documents, and that the
# bootstrap pins are not silently aging.  Exit nonzero on drift.
#
# Two arms:
#   DRIFT     -- re-execute the documented command surface against the
#                installed binaries (flag presence, revset parses,
#                --repo config round-trip in a throwaway store).
#   FRESHNESS -- `gh release view` the pinned repos and report pins
#                that have fallen behind upstream.  Advisory: never
#                fails the probe (gh may be absent; staleness is a
#                choice, drift is a defect).
#
# Receipt: vcs-compat-probe/1 JSON at
#   ~/.agents/.local/state/vcs-workflow/compat-probe.json
# Runs standalone, from a pitchfork cron (R6), or on demand; preflight
# reads the receipt rather than re-running this.
#
# Pins are the single source of truth here; SKILL.md's frontmatter
# cites them and the step-15 validation gate cross-checks the two.

set -o nounset

JJ_PIN='0.44.0'
AST_GREP_PIN='0.45.1'
DIFFT_PIN='0.70.0'
JJ_TAG_PIN='v0.44.0'
AST_GREP_TAG_PIN='0.45.1'
DIFFT_TAG_PIN='0.70.0'

OUT_DIR="$HOME/.agents/.local/state/vcs-workflow"
OUT="$OUT_DIR/compat-probe.json"
PASSED=0
FAILED=''
PINS_BEHIND=''

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

_version_of() {
	"$1" --version 2> /dev/null | head -1
}

_tool_version_claim() {
	# _tool_version_claim <name> <bin> <pin>
	_name=$1
	_bin=$2
	_pin=$3
	case "$(_version_of "$_bin")" in
		*"$_pin"*) _pass ;;
		*) _fail "$_name" ;;
	esac
}

_freshness() {
	# _freshness <repo> <pinned-tag>
	command -v gh > /dev/null 2>&1 || return 0
	_latest=$(gh release view --repo "$1" --json tagName -q .tagName 2> /dev/null) || return 0
	[ "$_latest" = "$2" ] || PINS_BEHIND="$PINS_BEHIND $1:pinned=$2,latest=$_latest"
}

_revset_claims() {
	# Parse-check the documented revsets in a throwaway store, plus
	# the --repo config round-trip.  Store is discarded afterward.
	_tmp=$(mktemp -d "${TMPDIR:-/tmp}/compat-probe.XXXXXX")
	(
		cd "$_tmp" || exit 1
		jj git init . > /dev/null 2>&1 || exit 1
	) || {
		_fail 'tmp-store-init'
		rm -rf "$_tmp"
		return 0
	}
	_claim 'revset-conflicts' \
		jj -R "$_tmp" log -r 'conflicts() & ~::remote_bookmarks()' --no-graph -T 'commit_id'
	_claim 'revset-description-substring' \
		jj -R "$_tmp" log -r 'description(substring:"x")' --no-graph -T 'commit_id'
	_claim 'revset-bookmarks-exact' \
		jj -R "$_tmp" log -r 'bookmarks(exact:"main") & ~immutable()' --no-graph -T 'commit_id'
	_claim 'config-repo-roundtrip' \
		jj -R "$_tmp" config set --repo ui.editor ':true'
	rm -rf "$_tmp"
}

_tool_version_claim 'jj-version' jj "$JJ_PIN"
_tool_version_claim 'ast-grep-version' ast-grep "$AST_GREP_PIN"
_tool_version_claim 'difft-version' difft "$DIFFT_PIN"

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

_revset_claims

_freshness jj-vcs/jj "$JJ_TAG_PIN"
_freshness ast-grep/ast-grep "$AST_GREP_TAG_PIN"
_freshness Wilfred/difftastic "$DIFFT_TAG_PIN"

if [ -n "$FAILED" ]; then
	_verdict='drift'
else
	_verdict='green'
fi

mkdir -p "$OUT_DIR"
_failed_json=$(printf '%s' "$FAILED" | awk '{for(i=1;i<=NF;i++)printf "%s\"%s\"",(i>1?",":""),$i}')
_pins_json=$(printf '%s' "$PINS_BEHIND" | awk '{for(i=1;i<=NF;i++)printf "%s\"%s\"",(i>1?",":""),$i}')
_tmp_out="$OUT.tmp"
cat > "$_tmp_out" <<- EOF
	{
	  "schema": "vcs-compat-probe/1",
	  "probed_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
	  "tools": {
	    "jj": "$(_version_of jj)",
	    "ast-grep": "$(_version_of ast-grep)",
	    "difftastic": "$(_version_of difft)"
	  },
	  "claims": { "passed": $PASSED, "failed": [$_failed_json] },
	  "pins_behind": [$_pins_json],
	  "verdict": "$_verdict",
	  "probe_version": "1"
	}
EOF
if command -v jq > /dev/null 2>&1 && ! jq . "$_tmp_out" > /dev/null 2>&1; then
	printf 'PROBE-FAIL malformed receipt left at %s\n' "$_tmp_out"
	exit 1
fi
mv "$_tmp_out" "$OUT"

printf 'PROBE-%s passed=%d failed=[%s] pins_behind=[%s] receipt=%s\n' \
	"$(printf '%s' "$_verdict" | tr '[:lower:]' '[:upper:]')" \
	"$PASSED" "${FAILED# }" "${PINS_BEHIND# }" "$OUT"
[ "$_verdict" = 'green' ]
