#!/bin/sh
# workspace_hook.sh -- the Claude Code WorktreeCreate / WorktreeRemove
# hook.  It answers both events with a jj workspace instead of a git
# worktree: a git worktree of a colocated repo is the worktree-shadowed
# shape, where jj silently reads and mutates the PARENT checkout.
#
# Input: one hook JSON object on stdin,
#   {session_id, hook_event_name, worktree_path, cwd}.
# The workspace NAME is `basename "$worktree_path"`; the rest of the
# proposed path is ignored, because Claude Code proposes a directory
# inside the repo and that is exactly the shape to avoid.  Remove is
# handed that same proposed path, so a path outside the workspaces root
# is recomputed from `cwd` the way create computes it, and only the
# recomputed directory is ever touched.
#
# Output: on create, stdout carries the workspace directory and nothing
# else -- Claude Code enters the directory this script prints.  Receipts,
# warnings, and every jj message go to stderr:
#   WORKSPACE-CREATE-OK repo=<slug> name=<n> dir=<d>
#   WORKSPACE-REMOVE-OK name=<n> dir=<d>
#   WORKSPACE-HOOK-FAIL reason=<r>
# Exit: 0 ok, 1 refusal, 2 unusable stdin or unknown event.
#
# Layout: ${XDG_DATA_HOME:-$HOME/.local/share}/agents/jj-workspaces/
# <slug>/<name>, where <slug> is the primary root's basename plus the
# first eight hex digits of the sha256 of its physical path, so two
# checkouts that share a basename never share a directory.
#
# See references/isolation.md for the hook contract and the cleanup
# order.

set -o nounset

SCRIPTDIR=$(dirname "$0")
# shellcheck source=_lib.sh disable=SC1091
. "$SCRIPTDIR/_lib.sh"

WS_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/agents/jj-workspaces"
JSON=''
SLUG=''

_fail() {
	printf 'WORKSPACE-HOOK-FAIL reason=%s\n' "$1" >&2
	exit "$2"
}

_warn() {
	printf 'workspace_hook: %s\n' "$*" >&2
}

_field() {
	printf '%s' "$JSON" | jq -r --arg k "$1" '.[$k] // empty' 2> /dev/null
}

# Both events anchor on the primary root, which vcs_primary_root
# resolves through the secondary workspace's `.jj/repo` pointer file:
# create builds the slug from it, remove forgets the registration there.
_slug() {
	printf '%s-%s' "$(basename "$1")" \
		"$(printf '%s' "$1" | sha256sum | cut -c1-8)"
}

_check_shape() {
	_shape=$(env -C "$1" "$SCRIPTDIR/detect_shape.sh" 2> /dev/null) || _shape=''
	case "$_shape" in
		colocated | jj-only) ;;
		*) _fail needs-onboarding 1 ;;
	esac
}

# Isolation is a standard/full step: at oplog the pipeline stops at
# capture, and refusing here is louder than a silent git fallback.
_check_level() {
	case "$(vcs_level "$1")" in
		standard | full) ;;
		oplog) _fail level-oplog 1 ;;
		*) _fail needs-onboarding 1 ;;
	esac
}

# jj cannot take a workspace inside a git repo, and Claude Code refuses
# a hook directory inside one; prove it before asking jj.
_check_target() {
	mkdir -p "$1" || _fail target-unwritable 1
	if git -C "$1" rev-parse --show-toplevel > /dev/null 2>&1; then
		_fail target-in-git-repo 1
	fi
}

_registered() {
	jj -R "$1" workspace list 2> /dev/null | cut -d: -f1 | grep -qxF "$2"
}

# Resume is the common case: a session that reconnects to a workspace it
# created must land on the same directory, not a second one.
_add_or_resume() {
	if [ -d "$3/.jj" ] && _registered "$1" "$2"; then
		jj -R "$3" workspace update-stale >&2 || _fail update-stale-failed 1
		return 0
	fi
	[ -e "$3" ] && _fail orphan-directory 1
	jj -R "$1" workspace add --name "$2" "$3" >&2 || _fail add-failed 1
}

_link_entry() {
	if [ ! -e "$1/$3" ]; then
		_warn "worktreeinclude: '$3' does not exist in $1"
		return 0
	fi
	if [ -e "$2/$3" ] || [ -L "$2/$3" ]; then
		return 0
	fi
	mkdir -p "$(dirname "$2/$3")" || {
		_warn "worktreeinclude: cannot create a parent for '$3'"
		return 0
	}
	ln -s "$1/$3" "$2/$3" || _warn "worktreeinclude: cannot link '$3'"
}

# Claude Code processes .worktreeinclude only for worktrees it creates
# itself, so the hook carries the entries over.
_link_includes() {
	[ -f "$1/.worktreeinclude" ] || return 0
	while IFS= read -r _entry || [ -n "$_entry" ]; do
		case "$_entry" in
			'' | '#'*) continue ;;
		esac
		_link_entry "$1" "$2" "$_entry"
	done < "$1/.worktreeinclude"
}

_create() {
	_check_shape "$1"
	_primary=$(vcs_primary_root "$1") || _fail primary-unresolved 1
	_check_level "$_primary"
	SLUG=$(_slug "$_primary")
	_check_target "$WS_ROOT/$SLUG"
	_dir="$WS_ROOT/$SLUG/$2"
	_add_or_resume "$_primary" "$2" "$_dir"
	_link_includes "$_primary" "$_dir"
	printf '%s\n' "$_dir"
	printf 'WORKSPACE-CREATE-OK repo=%s name=%s dir=%s\n' "$SLUG" "$2" "$_dir" >&2
}

# A recomputed directory need not exist yet, and the root itself may
# not either, so the literal prefix stands in when nothing physical
# resolves.
_under_root() {
	_rp=$(vcs_physical "$WS_ROOT") || _rp="$WS_ROOT"
	case "$1" in
		"$_rp"/* | "$WS_ROOT"/*) return 0 ;;
	esac
	return 1
}

# Claude Code proposes `.claude/worktrees/<name>` on remove just as it
# does on create, so a path outside the root is discarded down to its
# basename and rebuilt where create would have put it.
_resolve_remove_dir() {
	_d=$(vcs_physical "$2") || _d="$2"
	if _under_root "$_d"; then
		printf '%s' "$_d"
		return 0
	fi
	_p=$(vcs_primary_root "$1") || return 1
	printf '%s/%s/%s' "$WS_ROOT" "$(_slug "$_p")" "$(basename "$2")"
}

# The directory is gone but the registration is not, and a surviving
# registration keeps the name unusable forever.
_forget_absent() {
	_p=$(vcs_primary_root "$1") || return 0
	jj -R "$_p" workspace forget "$2" > /dev/null 2>&1
	return 0
}

# The snapshot is the point of the remove path: it captures whatever the
# workspace still holds into the repo before the directory dies, so an
# interrupted session is recoverable from the primary's op log.  With
# the primary gone there is nothing left to capture into.
_snapshot_and_forget() {
	_primary=$(vcs_primary_root "$1") || _primary=''
	if [ -z "$_primary" ]; then
		_warn 'primary root is gone; deleting without a snapshot'
		return 0
	fi
	jj -R "$1" status >&2 || _fail snapshot-failed 1
	jj -R "$_primary" workspace forget "$2" >&2 || _fail forget-failed 1
}

# The prefix test in _under_root is lexical, so the directory it sees
# must be physical and must not end in a dot component: a recomputed
# `<root>/<slug>/..` is `<root>` itself.
_safe_dir() {
	_b=$(basename "$1")
	[ "$_b" != '.' ] && [ "$_b" != '..' ] || return 1
	[ -e "$1" ] || {
		printf '%s' "$1"
		return 0
	}
	vcs_physical "$1"
}

_remove() {
	_dir=$(_resolve_remove_dir "$1" "$2") || _fail refused-path 1
	_dir=$(_safe_dir "$_dir") || _fail refused-path 1
	_under_root "$_dir" || _fail refused-path 1
	_name=$(basename "$_dir")
	if [ ! -e "$_dir" ]; then
		_forget_absent "$1" "$_name"
		printf 'WORKSPACE-REMOVE-OK name=%s dir=%s state=absent\n' "$_name" "$_dir" >&2
		return 0
	fi
	[ -d "$_dir/.jj" ] || _fail refused-path 1
	_snapshot_and_forget "$_dir" "$_name"
	rm -rf "$_dir" || _fail remove-failed 1
	printf 'WORKSPACE-REMOVE-OK name=%s dir=%s\n' "$_name" "$_dir" >&2
}

# The documented input carries worktree_path; the mid-session
# EnterWorktree tool sends `name` and no path (measured 2026-09-15).
# Either names the workspace.
_name_from_input() {
	_p=$(_field worktree_path)
	if [ -n "$_p" ]; then
		basename "$_p"
	else
		_field name
	fi
}

_bad_input() {
	_keys=$(printf '%s' "$JSON" | jq -r 'keys | join(" ")' 2> /dev/null)
	printf 'WORKSPACE-HOOK-FAIL reason=bad-input keys=[%s]\n' "$_keys" >&2
	exit 2
}

main() {
	JSON=$(cat)
	_event=$(_field hook_event_name)
	_path=$(_field worktree_path)
	_cwd=$(_field cwd)
	_name=$(_name_from_input)
	[ -n "$_name" ] || _bad_input
	[ -n "$_cwd" ] || _cwd=$PWD
	case "$_event" in
		WorktreeCreate) _create "$_cwd" "$_name" ;;
		WorktreeRemove) _remove "$_cwd" "${_path:-$_name}" ;;
		*) _bad_input ;;
	esac
}

main "$@"
