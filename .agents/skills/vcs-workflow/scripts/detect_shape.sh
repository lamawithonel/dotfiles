#!/bin/sh
# detect_shape.sh -- classify the working directory's VCS shape.
#
# Prints exactly one shape on stdout:
#   colocated | jj-only | jj-workspace | git-only   with exit 0
#   none              with exit 2  (no git or jj repo here)
#   worktree-shadowed with exit 3  (HARD STOP: jj resolves to a
#     DIFFERENT root than git -- typically a nested git worktree of a
#     colocated repo, where jj silently reads and mutates the PARENT
#     checkout.  No jj command, reads included, may run in this state;
#     use plain git.)
#
# Detection is structural (wave-2/4 receipts): `jj root` disagreeing
# with `git rev-parse --show-toplevel` is the shadow signature; a
# secondary jj workspace has `.jj/repo` as a pointer FILE and no
# `.git`; a `--no-colocate` primary has `.jj/repo` as a directory.
# Both roots are resolved to PHYSICAL paths before the comparison, so a
# symlinked repo root is not a false worktree-shadowed.
#
# When `jj` is not on PATH a note goes to stderr; stdout still carries
# exactly one token, and the exit codes are unchanged.

set -o nounset

# Deliberately not _lib.sh's vcs_physical: a shape probe must always
# emit one token, so an unresolvable path falls back to the input
# instead of failing.  This is the one script that does not source the
# lib, because it runs before anything else is known to work.
_physical() {
	(cd -P "$1" 2> /dev/null && pwd -P) || printf '%s\n' "$1"
}

command -v jj > /dev/null 2>&1 || printf 'detect_shape: jj not on PATH\n' >&2

_git_top=$(git rev-parse --show-toplevel 2> /dev/null) || _git_top=''
_jj_root=$(jj root 2> /dev/null) || _jj_root=''
[ -z "$_git_top" ] || _git_top=$(_physical "$_git_top")
[ -z "$_jj_root" ] || _jj_root=$(_physical "$_jj_root")

if [ -n "$_jj_root" ] && [ -n "$_git_top" ] && [ "$_jj_root" != "$_git_top" ]; then
	echo 'worktree-shadowed'
	exit 3
fi

if [ -n "$_jj_root" ]; then
	if [ -e "$_jj_root/.git" ]; then
		echo 'colocated'
	elif [ -f "$_jj_root/.jj/repo" ]; then
		echo 'jj-workspace'
	else
		echo 'jj-only'
	fi
	exit 0
fi

if [ -n "$_git_top" ]; then
	echo 'git-only'
	exit 0
fi

echo 'none'
exit 2
