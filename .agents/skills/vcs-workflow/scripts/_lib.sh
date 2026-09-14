#!/bin/sh
# _lib.sh -- the resolution helpers every script in this directory
# shares.  DOT-SOURCED, never executed:
#
#   # shellcheck source=_lib.sh
#   . "$(dirname "$0")/_lib.sh"
#
# The shebang is there for the linters, which classify a shell file by
# it; nothing runs this file.  Sourcing it defines functions and sets
# no options, so a caller's `set` flags and positional parameters
# survive untouched.
#
# Why it exists: a secondary jj workspace has no `.git` of its own and
# holds `.jj/repo` as a plain-text POINTER FILE naming the primary's
# `.jj/repo`, relative to the workspace's own `.jj` directory.  Both
# the recorded level and the state directory belong to the primary, so
# a read taken where the command happens to run answers `full` for a
# repo recorded `oplog`, and writes receipts into a directory that dies
# with the workspace.  One resolution, used by every caller, is what
# keeps those answers from drifting apart.
#
# Functions (all print to stdout, none mutate the filesystem):
#   vcs_physical PATH       physical path of PATH; 1 when unresolvable
#   vcs_primary_root [DIR]  primary jj root seen from DIR (default .);
#                           1 when DIR is not inside a jj repo
#   vcs_level ROOT          vcs-workflow.level at ROOT, else `full`
#   vcs_state_dir ROOT      the state directory path; does not mkdir
#
# Local variables carry a `_vcs_` prefix: a sourced function shares the
# caller's variable namespace, and every caller here uses `_`-led names.
#
# Callers locate this file with `dirname "$0"`, so they must be invoked
# by their real path or through a symlinked DIRECTORY (the documented
# ~/.claude/skills -> ../.agents/skills).  A symlink to an individual
# script is not supported: `$0` would name the link's directory.

vcs_physical() {
	(cd -P "$1" 2> /dev/null && pwd -P) || return 1
}

vcs_primary_root() {
	_vcs_root=$(env -C "${1:-.}" jj root 2> /dev/null) || return 1
	_vcs_ptr="$_vcs_root/.jj/repo"
	if [ -f "$_vcs_ptr" ]; then
		_vcs_target=$(cat "$_vcs_ptr") || return 1
		case $_vcs_target in
			/*) ;;
			*) _vcs_target="$_vcs_root/.jj/$_vcs_target" ;;
		esac
		_vcs_root="$_vcs_target/../.."
	fi
	vcs_physical "$_vcs_root"
}

# An absent key -- including a jj-only shape, which has no git config to
# read -- means level full.  The .git test comes first because git
# walks up the tree: a jj-only root nested inside some other repository
# must not inherit that repository's key.
vcs_level() {
	[ -e "$1/.git" ] || {
		printf 'full'
		return 0
	}
	_vcs_level=$(git -C "$1" config --get vcs-workflow.level 2> /dev/null) \
		|| _vcs_level='full'
	printf '%s' "${_vcs_level:-full}"
}

vcs_state_dir() {
	printf '%s' "$1/.local/state/agents/vcs"
}
