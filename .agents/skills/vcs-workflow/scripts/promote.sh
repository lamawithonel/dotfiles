#!/bin/sh
# promote.sh -- move a bookmark to a verified revision and push it.
# The autonomy ceiling is the PR: this script pushes a branch; it never
# merges anything.
#
# Usage: promote.sh BOOKMARK [REV]     (REV defaults to @-)
#
# Ordered checks, each fail-silent without this script:
#   1. gate receipt: <repo>/.local/state/agents/vcs/gate.json must
#      exist with verdict=pass (verification happens BEFORE promotion,
#      never after -- P-GATE-ORDER).
#   2. RED scan: no commit in trunk()..REV may carry the
#      'Verification-Status: red-expected' trailer (durable red must be
#      an xfail; the trailer is an intra-session checkpoint only).
#   3. undescribed scan: `jj git push` rejects ANY undescribed commit
#      in the pushed range, not just the bookmark target -- catch it
#      here with attribution instead of a mid-push refusal.
#   4. bookmark move, --dry-run push, then the real push.  On ANY push
#      failure, re-query remote_bookmarks() before retrying: a failing
#      reference-transaction hook can make the exit code lie AFTER the
#      remote has already updated.
#
# No --allow-conflicts, --allow-empty-description, or
# --allow-private -- ever.  jj git push has no force flag to avoid.
# Exit: 0 ok, 1 fail, 2 usage, 3 worktree-shadowed, 5 wrong shape.

set -o nounset

RED_TRAILER='Verification-Status: red-expected'

_fail() {
	printf 'PROMOTE-FAIL %s\n' "$*"
	exit 1
}

_revlist() {
	jj log -r "$1" --no-graph -T 'change_id.short() ++ "\n"' 2> /dev/null
}

_check_shape() {
	_shape=$("$(dirname "$0")/detect_shape.sh")
	if [ "$?" -eq 3 ]; then
		printf 'PROMOTE-FAIL shape=worktree-shadowed\n'
		exit 3
	fi
	case "$_shape" in
		colocated | jj-only | jj-workspace) : ;;
		*)
			printf 'PROMOTE-FAIL shape=%s (jj shapes only)\n' "$_shape"
			exit 5
			;;
	esac
}

_check_gate_receipt() {
	_receipt="$(jj root)/.local/state/agents/vcs/gate.json"
	[ -f "$_receipt" ] || _fail "no gate receipt at $_receipt (run gate.sh first)"
	_verdict=$(jq -r '.verdict' "$_receipt" 2> /dev/null) \
		|| _fail "unreadable gate receipt $_receipt"
	[ "$_verdict" = 'pass' ] || _fail "gate receipt verdict is '$_verdict', not pass"
}

_check_range() {
	# $1 = target rev
	_range="trunk()..$1"
	_red=$(_revlist "description(substring:\"$RED_TRAILER\") & ($_range)")
	[ -z "$_red" ] \
		|| _fail "RED trailer in promoted range (convert to xfail first): $(printf '%s' "$_red" | tr '\n' ' ')"
	_undescribed=$(_revlist "description(exact:\"\") & ($_range) ~ root()")
	[ -z "$_undescribed" ] \
		|| _fail "undescribed commits in range (push would reject the whole range): $(printf '%s' "$_undescribed" | tr '\n' ' ')"
}

_push() {
	# $1 = bookmark
	if [ -z "$(jj git remote list 2> /dev/null)" ]; then
		printf 'PROMOTE-PARTIAL bookmark=%s moved; no git remote configured, push skipped\n' "$1"
		exit 0
	fi
	jj git push --bookmark "$1" --dry-run > /dev/null 2>&1 \
		|| _fail "push --dry-run refused for bookmark $1"
	if ! _out=$(jj git push --bookmark "$1" 2>&1); then
		printf '%s\n' "$_out" >&2
		printf 'promote: push failed; remote state may STILL have changed (reference-transaction hooks lie).  Re-query before retrying:\n' >&2
		jj log -r 'remote_bookmarks()' --no-graph \
			-T 'commit_id.short() ++ " " ++ bookmarks ++ "\n"' >&2 || true
		_fail "jj git push failed for bookmark $1"
	fi
}

main() {
	[ "$#" -ge 1 ] || {
		printf 'Usage: promote.sh BOOKMARK [REV]\n' >&2
		exit 2
	}
	_bookmark=$1
	_rev=${2:-@-}
	_check_shape
	_check_gate_receipt
	_check_range "$_rev"
	jj bookmark set "$_bookmark" -r "$_rev" 2>&1 \
		|| _fail "bookmark set $_bookmark -r $_rev refused (immutable target?)"
	_push "$_bookmark"
	printf 'PROMOTE-OK bookmark=%s rev=%s pushed\n' "$_bookmark" "$_rev"
}

main "$@"
