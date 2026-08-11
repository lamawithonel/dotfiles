#!/bin/sh
# gate.sh -- the verification gate.  Wraps `jj run` with the flag
# invariants whose violation is silent, selects GATE vs REPORT shape
# mechanically, and emits a machine-readable receipt.
#
# Usage: gate.sh [--range REVSET] [--cheap] [--report] [--final-clean]
#                -- CMD [ARG...]
#   --range REVSET   revset to gate (default: '(trunk()::@) ~ root()')
#   --cheap          sub-second command: -j$(nproc) unconditionally
#   --report         force per-revision REPORT mode
#   --final-clean    reproducibility-critical final gate: adds --clean
#                    (EXPENSIVE: discards every warm working copy; never
#                    part of the routine loop)
#
# Invariants encoded here (violations are silent without this script):
#   - every run carries --ignore-changes (without it, jj run AMENDS the
#     gated revisions with post-command working-copy state: a test gate
#     silently becomes an auto-fixer)
#   - --ignore-errors is never emitted (zeroes the exit code AND drops
#     the failing-revision attribution)
#   - -j by warmth: cold compiled gates run -j1 (measured: cold -j4 is
#     ~1.8x SLOWER than -j1); a session warm-flag upgrades to -jN
#   - conflicts() pre-flight: jj run executes INSIDE conflict markers
#     and fails indistinguishably from a real test failure, so a
#     conflicted range is CONFLICT-BLOCKED, never "tests failed"
#   - REPORT mode is mandatory when the range carries a RED trailer:
#     a ranged run aborts at the first failure and never reports on
#     later revisions
#
# Receipt: gate JSON at <repo>/.local/state/agents/vcs/gate.json
# Exit: 0 pass, 1 gate failure, 2 usage, 3 worktree-shadowed,
#       4 CONFLICT-BLOCKED, 5 wrong shape.

set -o nounset

RED_TRAILER='Verification-Status: red-expected'
RANGE='(trunk()::@) ~ root()'
CHEAP=0
FORCE_REPORT=0
FINAL_CLEAN=0
MODE='GATE'
JOBS=1
WARM=0
CLEAN_ARG=''
VERDICT='pass'
FAILED_CHANGE=''
EXIT=0
RED_REVS=''
RED_JSON=''
STATE_DIR=''

_usage() {
	sed -n '6,13p' "$0" | sed 's/^# \{0,1\}//'
}

_revlist() {
	jj log -r "$1" --no-graph -T 'change_id.short() ++ "\n"' 2> /dev/null
}

_parse_args() {
	while [ "$#" -gt 0 ]; do
		case "$1" in
			--range)
				[ "$#" -ge 2 ] || return 1
				RANGE=$2
				shift 2
				;;
			--cheap) CHEAP=1 && shift ;;
			--report) FORCE_REPORT=1 && shift ;;
			--final-clean) FINAL_CLEAN=1 && shift ;;
			--)
				shift
				GATE_CMD_N=$#
				break
				;;
			*) return 1 ;;
		esac
	done
	[ "${GATE_CMD_N:-0}" -gt 0 ]
}

_check_shape() {
	_shape=$("$(dirname "$0")/detect_shape.sh")
	if [ "$?" -eq 3 ]; then
		printf 'GATE-FAIL shape=worktree-shadowed\n'
		exit 3
	fi
	case "$_shape" in
		colocated | jj-only | jj-workspace) : ;;
		*)
			printf 'GATE-FAIL shape=%s (jj shapes only; git-only gating is documented in references/git-only.md)\n' "$_shape"
			exit 5
			;;
	esac
}

_check_conflicts() {
	_conflicted=$(_revlist "conflicts() & ($RANGE)")
	if [ -n "$_conflicted" ]; then
		printf 'CONFLICT-BLOCKED revisions: %s\n' "$(printf '%s' "$_conflicted" | tr '\n' ' ')"
		exit 4
	fi
}

_pick_mode_and_jobs() {
	RED_REVS=$(_revlist "description(substring:\"$RED_TRAILER\") & ($RANGE)")
	if [ -n "$RED_REVS" ] || [ "$FORCE_REPORT" -eq 1 ]; then
		MODE='REPORT'
	fi
	_nproc=$(nproc 2> /dev/null || getconf _NPROCESSORS_ONLN 2> /dev/null || echo 1)
	[ -f "$STATE_DIR/gate-warm" ] && WARM=1
	if [ "$CHEAP" -eq 1 ] || [ "$WARM" -eq 1 ]; then
		JOBS=$_nproc
	fi
	if [ "$FINAL_CLEAN" -eq 1 ]; then
		printf 'gate: --final-clean discards every warm working copy (expensive)\n' >&2
		CLEAN_ARG='--clean'
		rm -f "$STATE_DIR/gate-warm"
	fi
}

_run_gate() {
	# shellcheck disable=SC2086  # CLEAN_ARG is empty or one flag
	_out=$(jj run --ignore-changes $CLEAN_ARG -j "$JOBS" -r "$RANGE" -- "$@" 2>&1)
	EXIT=$?
	if [ "$EXIT" -ne 0 ]; then
		VERDICT='fail'
		FAILED_CHANGE=$(printf '%s\n' "$_out" \
			| sed -n 's/.*Failed revision: \([a-z0-9]*\).*/\1/p' | head -1)
		printf '%s\n' "$_out" | tail -20 >&2
	fi
}

_run_report() {
	for _rev in $(_revlist "$RANGE"); do
		# shellcheck disable=SC2086
		if jj run --ignore-changes $CLEAN_ARG -j 1 -r "$_rev" -- "$@" > /dev/null 2>&1; then
			printf 'gate: %s OK\n' "$_rev" >&2
		elif printf '%s\n' "$RED_REVS" | grep -q "^$_rev$"; then
			printf 'gate: %s RED-EXPECTED (marked, tolerated pre-promotion)\n' "$_rev" >&2
			RED_JSON="$RED_JSON\"$_rev\","
		else
			printf 'gate: %s FAIL (unmarked)\n' "$_rev" >&2
			VERDICT='fail'
			FAILED_CHANGE=$_rev
			EXIT=1
		fi
	done
}

_emit_receipt() {
	_cmd_json=$(printf '%s\n' "$@" | awk '{printf "%s\"%s\"",(NR>1?",":""),$0}')
	cat > "$STATE_DIR/gate.json" <<- EOF
		{
		  "schema": "vcs-gate/1",
		  "mode": "$MODE",
		  "cmd": [$_cmd_json],
		  "cmd_source": "argv",
		  "range": "$RANGE",
		  "j": $JOBS,
		  "warm": $WARM,
		  "red_expected": [${RED_JSON%,}],
		  "verdict": "$VERDICT",
		  "failed_change_id": "$FAILED_CHANGE",
		  "exit": $EXIT
		}
	EOF
}

main() {
	_parse_args "$@" || {
		_usage >&2
		exit 2
	}
	# Drop the parsed options; keep only the gate command argv.
	while [ "$#" -gt "$GATE_CMD_N" ]; do
		shift
	done
	_check_shape
	STATE_DIR="$(jj root)/.local/state/agents/vcs"
	mkdir -p "$STATE_DIR"
	_check_conflicts
	_pick_mode_and_jobs
	if [ "$MODE" = 'GATE' ]; then
		_run_gate "$@"
	else
		_run_report "$@"
	fi
	if [ "$VERDICT" = 'pass' ] && [ "$CHEAP" -eq 0 ] && [ "$FINAL_CLEAN" -eq 0 ]; then
		: > "$STATE_DIR/gate-warm"
	fi
	_emit_receipt "$@"
	if [ "$VERDICT" = 'pass' ]; then
		printf 'GATE-PASS mode=%s range=%s j=%s\n' "$MODE" "$RANGE" "$JOBS"
		exit 0
	fi
	printf 'GATE-FAIL mode=%s failed_change=%s\n' "$MODE" "$FAILED_CHANGE"
	exit 1
}

main "$@"
