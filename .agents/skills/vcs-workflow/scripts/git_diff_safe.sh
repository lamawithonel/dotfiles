#!/bin/sh
# git_diff_safe.sh -- the single sanctioned entry point for hardened
# `git diff` / `git show` / `git log` reads.
#
# Usage: git_diff_safe.sh (diff|show|log) [GIT_ARGS...]
#
# Why it exists (wave-3/4 receipts):
#   - core.quotePath=true (git's default) octal-escapes non-ASCII
#     filenames and silently breaks downstream patch parsers; every
#     hardened read carries -c core.quotePath=false.
#   - `git diff <jj-revset>` exits 128 -- but one call site above, an
#     unchecked return code turned that into "empty diff, nothing to
#     do".  This wrapper asserts the return code so the failure is
#     loud at the source.
#   - At work, `git diff`/`git show`/`git log` are allow-listed as
#     two-token prefixes; `git -c ... diff` may not match them.  One
#     approved script path replaces N ambiguous `git -c` invocations.
#
# Never pass a jj revset as a git revision: resolve it first
# (jj log -r <revset> --no-graph -T commit_id).
# Exit: git's own exit code on success paths; 1 on any nonzero git
# exit, with the code named on stderr; 2 on usage.

set -o nounset

case "${1:-}" in
	diff | show | log) : ;;
	*)
		printf 'Usage: git_diff_safe.sh (diff|show|log) [GIT_ARGS...]\n' >&2
		exit 2
		;;
esac
_sub=$1
shift

git -c core.quotePath=false "$_sub" "$@"
_rc=$?
if [ "$_rc" -ne 0 ]; then
	printf 'git_diff_safe: git %s exited %d (a jj revset passed as a git revision exits 128 -- resolve to a commit id first)\n' \
		"$_sub" "$_rc" >&2
	exit 1
fi
