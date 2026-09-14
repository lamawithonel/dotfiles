#!/bin/sh
# preflight.sh -- write the jj safety net at --repo scope and assert it
# closed.  Idempotent; re-run freely.  MUST re-run after any fresh
# `jj git clone` or `jj git init`: --repo config is keyed by
# .jj/repo/config-id and does not survive into a new store.
#
# Usage: preflight.sh [--level oplog|standard|full]
#   --level L   the conversion level to write keys for.  Without it the
#               level comes from the vcs-workflow.level key read at the
#               PRIMARY root (a secondary workspace has no git config
#               of its own, so _lib.sh resolves the root through the
#               `.jj/repo` pointer first); an absent key, or a jj-only
#               shape, means `full`.
#
# What it writes (the keys the level calls for, the sanctioned
# exception to the no-config-mutation rule; announced in the receipt):
#   revset-aliases."immutable_heads()"  builtin union of explicit
#       bookmarks(exact:"...") clauses -- NEVER trunk(): builtin
#       trunk() resolves through remote bookmarks and cannot see a
#       local-only trunk, so protecting via trunk() protects nothing.
#   ui.editor = ":true"          }  editor guard parts 1+2; part 3 is
#   ui.diff-editor = ":true"     }  the JJ_EDITOR env assertion below
#       (JJ_EDITOR OUTRANKS persisted --repo config, so a set JJ_EDITOR
#       is a hard failure, not a courtesy).
#   snapshot.auto-track = "none"   at level `standard` only: only files
#       explicitly `jj file track`ed can publish.  Levels `full` and
#       `oplog` both UNSET the key so jj's own default (all()) applies
#       -- unsetting, not skipping, because a level change re-runs this
#       script against a store that may already carry the standard key.
#
# Identity fails closed BEFORE any write: jj never falls back to the git
# identity, and a placeholder identity (empty, .invalid, @example.)
# would author every captured commit.
#
# Protected bookmarks: $PREFLIGHT_PROTECTED_BOOKMARKS (space-separated)
# or auto-resolved from the remote HEAD / conventional names.  FAILS
# CLOSED when unresolvable: silently protecting nothing is the exact
# failure mode this script exists to prevent.
#
# Receipt (stdout, single line):
#   PREFLIGHT-OK shape=<s> level=<L> store=<id> protected=[a b] probe=<state>
#   PREFLIGHT-SKIP shape=git-only
# Exit: 0 ok/skip, 1 failure, 3 worktree-shadowed (propagated).

set -o nounset
# The protected-bookmark list is word-split on purpose; -f keeps a name
# such as '*' a literal (and refused) instead of a directory listing.
set -f

LEVEL=''

_die() {
	printf 'PREFLIGHT-FAIL %s\n' "$*"
	exit 1
}

_parse_args() {
	while [ "$#" -gt 0 ]; do
		case "$1" in
			--level)
				[ "$#" -ge 2 ] || return 1
				LEVEL=$2
				shift 2
				;;
			*) return 1 ;;
		esac
	done
}

_parse_args "$@" || _die 'usage: preflight.sh [--level oplog|standard|full]'

_scriptdir=$(dirname "$0")
# shellcheck source=_lib.sh disable=SC1091
. "$_scriptdir/_lib.sh"

_shape=$("$_scriptdir/detect_shape.sh")
_shape_rc=$?
if [ "$_shape_rc" -eq 3 ]; then
	printf 'PREFLIGHT-FAIL shape=worktree-shadowed (no jj command may run here)\n'
	exit 3
fi
if [ "$_shape" = 'git-only' ] || [ "$_shape" = 'none' ]; then
	printf 'PREFLIGHT-SKIP shape=%s\n' "$_shape"
	exit 0
fi

# Editor guard part 3: JJ_EDITOR outranks everything we can persist.
if [ -n "${JJ_EDITOR:-}" ] && [ "${JJ_EDITOR}" != ':true' ]; then
	_die "JJ_EDITOR is set ('${JJ_EDITOR}') and outranks --repo ui.editor; unset it or set it to ':true'"
fi

# Both the level key and the store id belong to the primary root, and
# a secondary workspace reaches it only through its `.jj/repo` pointer
# file (see _lib.sh).
_primary=$(vcs_primary_root) \
	|| _die 'cannot resolve the primary jj root (unreadable workspace pointer file?)'

# A jj-only shape has no git config of its own to record a level in, and
# asking git for the key there would answer out of whatever repository
# encloses the checkout.
_resolve_level() {
	[ -n "$LEVEL" ] && return 0
	if [ "$_shape" = 'jj-only' ]; then
		LEVEL='full'
		return 0
	fi
	LEVEL=$(vcs_level "$_primary")
}

_resolve_level
case "$LEVEL" in
	oplog | standard | full) ;;
	*) _die "level='$LEVEL' is unknown (expected oplog|standard|full)" ;;
esac

_assert_identity() {
	_name=$(jj config get user.name 2> /dev/null) || _name=''
	_email=$(jj config get user.email 2> /dev/null) || _email=''
	[ -n "$_name" ] || _die 'identity user.name is empty'
	[ -n "$_email" ] || _die 'identity user.email is empty'
	# Addresses are case-insensitive, so the patterns match the folded
	# form: A@EXAMPLE.COM is the same placeholder as a@example.com.
	_folded=$(printf '%s' "$_email" | tr '[:upper:]' '[:lower:]')
	case "$_folded" in
		*.invalid | *@example | *@example.* | *.example.com)
			_die "identity user.email '$_email' is a placeholder"
			;;
	esac
}

_assert_identity

_resolve_protected() {
	if [ -n "${PREFLIGHT_PROTECTED_BOOKMARKS:-}" ]; then
		printf '%s' "$PREFLIGHT_PROTECTED_BOOKMARKS"
		return 0
	fi
	# Remote HEAD first (colocated shapes), then conventional names.
	_head=$(git symbolic-ref --short refs/remotes/origin/HEAD 2> /dev/null) \
		&& {
			printf '%s' "${_head#origin/}"
			return 0
		}
	for _cand in main master trunk; do
		if [ -n "$(jj bookmark list "$_cand" 2> /dev/null)" ]; then
			printf '%s' "$_cand"
			return 0
		fi
	done
	return 1
}

_protected=$(_resolve_protected) \
	|| _die 'cannot resolve a protected bookmark (no remote HEAD, no main/master/trunk); set PREFLIGHT_PROTECTED_BOOKMARKS explicitly'

# A name goes into a jj revset string literal, which has no escaping
# this script can rely on: an unchecked name carrying `"` closes the
# literal and the rest of it is persisted as revset code.  Only names
# built from characters that can neither close a literal nor open a
# call are interpolated.
_assert_bookmark_name() {
	case $1 in
		*[!A-Za-z0-9._/+-]*)
			_die "protected bookmark name '$1' has an illegal character (allowed: A-Za-z0-9._/+-)"
			;;
	esac
}

_alias='builtin_immutable_heads()'
for _b in $_protected; do
	_assert_bookmark_name "$_b"
	_alias="$_alias | bookmarks(exact:\"$_b\")"
done

jj config set --repo 'revset-aliases."immutable_heads()"' "$_alias" \
	|| _die 'jj config set immutable_heads failed'
jj config set --repo ui.editor ':true' || _die 'jj config set ui.editor failed'
jj config set --repo ui.diff-editor ':true' || _die 'jj config set ui.diff-editor failed'

# Character-checked names cannot break the literal, but an alias
# redefined anywhere else in the config stack still can -- and an
# unparseable immutable() makes the closing assertion below vacuous
# rather than loud, because every query it runs errors out too.
_assert_parses() {
	_err=$(jj log -r 'immutable()' -n 0 2>&1) && return 0
	_die "immutable() does not parse: $(printf '%s' "$_err" | tr '\n' ' ')"
}

_assert_parses

# `jj config unset` errors when the key is already absent; an absent
# key is the desired end state at levels oplog and full, so the failure
# is ignored.  Unsetting rather than skipping is what makes a downgrade
# from standard actually drop the key.
_write_level_key() {
	case "$LEVEL" in
		standard)
			jj config set --repo snapshot.auto-track 'none' \
				|| _die 'jj config set snapshot.auto-track failed'
			;;
		oplog | full)
			jj config unset --repo snapshot.auto-track 2> /dev/null || true
			;;
	esac
}

_write_level_key

# Closing assertion (invariant 3): every configured protected bookmark
# that exists must sit inside immutable().  Empty output = closed.
for _b in $_protected; do
	[ -n "$(jj bookmark list "$_b" 2> /dev/null)" ] || continue
	_leak=$(jj log -r "bookmarks(exact:\"$_b\") & ~immutable()" --no-graph \
		-T 'commit_id ++ "\n"' 2>&1) \
		|| _die "assertion query failed for bookmark '$_b': $_leak"
	[ -z "$_leak" ] || _die "bookmark '$_b' is NOT protected (mutable commits: $_leak)"
done

# Store id, for callers gating "has preflight run against THIS store".
# One store, one id: a workspace reports its primary's.
_store=$(cat "$_primary/.jj/repo/config-id" 2> /dev/null) || _store='unknown'

# Compat-probe receipt: accelerator only (R6); warn, never fail.
_probe='missing'
_probe_file="$HOME/.agents/.local/state/vcs-workflow/compat-probe.json"
if [ -f "$_probe_file" ]; then
	if [ -n "$(find "$_probe_file" -mtime -7 2> /dev/null)" ]; then
		_probe='ok'
	else
		_probe='stale'
	fi
fi

printf 'PREFLIGHT-OK shape=%s level=%s store=%s protected=[%s] probe=%s\n' \
	"$_shape" "$LEVEL" "$_store" "$_protected" "$_probe"
