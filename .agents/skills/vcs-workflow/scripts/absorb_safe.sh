#!/bin/sh
# absorb_safe.sh -- the enforced form of `jj absorb`.  Makes invariants
# 10-11 tool-enforced instead of aspirational:
#   - a pending rename (`R ` row) blocks BARE absorb: rename collateral
#     silently rewrites an ancestor's file inventory (single-owner
#     EMPTIES the ancestor's file; split-ownership plants conflict
#     markers) with nothing visible in the final diff.  Route renames
#     explicitly: absorb_safe.sh --into <rev> <paths>.
#   - destinations are always confined to
#     mutable() & ~::remote_bookmarks() -- never rewrite a commit a
#     reviewer has seen.  A caller --into is intersected with that set.
#   - every real absorb is followed by the mandatory pair: residual
#     check + `jj op show -p --summary` routing review.
#
# Usage: absorb_safe.sh [--dry-run] [--from REV] [--into REVSET] [PATHS...]
#   --dry-run   uses --no-integrate-operation; prints the resulting op
#               id for inspection via `jj --at-op`; repo state untouched
#
# Receipt line: ABSORB-OK op=<id> residual=<n> | ABSORB-BLOCKED ...
# Exit: 0 ok, 1 blocked/failed, 2 usage, 3 worktree-shadowed, 5 shape.

set -o nounset

CONFINE='mutable() & ~::remote_bookmarks()'
DRY=0
FROM=''
INTO="$CONFINE"
NPATHS=0

_check_shape() {
	_shape=$("$(dirname "$0")/detect_shape.sh")
	if [ "$?" -eq 3 ]; then
		printf 'ABSORB-BLOCKED shape=worktree-shadowed\n'
		exit 3
	fi
	case "$_shape" in
		colocated | jj-only | jj-workspace) : ;;
		*)
			printf 'ABSORB-BLOCKED shape=%s (jj shapes only)\n' "$_shape"
			exit 5
			;;
	esac
}

_parse_args() {
	while [ "$#" -gt 0 ]; do
		case "$1" in
			--dry-run)
				DRY=1
				shift
				;;
			--from)
				[ "$#" -ge 2 ] || return 1
				FROM=$2
				shift 2
				;;
			--into)
				[ "$#" -ge 2 ] || return 1
				INTO="($2) & $CONFINE"
				shift 2
				;;
			--*) return 1 ;;
			*) break ;;
		esac
	done
	NPATHS=$#
}

_rename_gate() {
	if [ "$NPATHS" -eq 0 ] && jj status 2> /dev/null | grep -q '^R '; then
		printf 'ABSORB-BLOCKED pending rename (R row) and no explicit paths -- route the rename via: absorb_safe.sh --into <rev> <paths>\n'
		exit 1
	fi
}

_dry_run() {
	_out=$(jj absorb --no-integrate-operation --into "$INTO" "$@" 2>&1)
	_rc=$?
	printf '%s\n' "$_out" >&2
	_op=$(printf '%s\n' "$_out" | sed -n 's/.*operation[: ]*\([0-9a-f]\{8,\}\).*/\1/p' | head -1)
	[ -n "$_op" ] || _op=$(printf '%s\n' "$_out" | grep -oE '\b[0-9a-f]{12,}\b' | head -1)
	printf 'ABSORB-DRY-RUN op=%s (inspect: jj --at-op=%s log; apply by re-running without --dry-run)\n' \
		"${_op:-unknown}" "${_op:-<id>}"
	exit "$_rc"
}

_real_run() {
	_out=$(jj absorb --into "$INTO" "$@" 2>&1)
	_rc=$?
	printf '%s\n' "$_out" >&2
	if [ "$_rc" -ne 0 ]; then
		printf 'ABSORB-BLOCKED jj absorb failed (exit %d)\n' "$_rc"
		exit 1
	fi
	_op=$(jj op log -n1 --no-graph -T 'id.short()' 2> /dev/null)
	_residual=$(jj diff -r @ --summary 2> /dev/null | wc -l)
	printf -- '--- routing review (jj op show -p --summary) ---\n' >&2
	jj op show -p --summary >&2 2> /dev/null || true
	if [ "$_residual" -gt 0 ]; then
		printf 'absorb: %d path(s) left in @ (ambiguity residual -- route explicitly or keep as new work):\n' "$_residual" >&2
		jj diff -r @ --summary >&2 2> /dev/null
	fi
	printf 'ABSORB-OK op=%s residual=%d\n' "$_op" "$_residual"
}

main() {
	_check_shape
	_parse_args "$@" || {
		printf 'Usage: absorb_safe.sh [--dry-run] [--from REV] [--into REVSET] [PATHS...]\n' >&2
		exit 2
	}
	# Keep only the path arguments (they are the trailing NPATHS args).
	while [ "$#" -gt "$NPATHS" ]; do
		shift
	done
	_rename_gate
	if [ -n "$FROM" ]; then
		set -- --from "$FROM" "$@"
	fi
	if [ "$DRY" -eq 1 ]; then
		_dry_run "$@"
	fi
	_real_run "$@"
}

main "$@"
