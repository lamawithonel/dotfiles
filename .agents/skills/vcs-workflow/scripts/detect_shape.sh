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

set -o nounset

_git_top=$(git rev-parse --show-toplevel 2> /dev/null) || _git_top=''
_jj_root=$(jj root 2> /dev/null) || _jj_root=''

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
