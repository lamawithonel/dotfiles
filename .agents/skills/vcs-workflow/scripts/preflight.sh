#!/bin/sh
# preflight.sh -- write the jj safety net at --repo scope and assert it
# closed.  Idempotent; re-run freely.  MUST re-run after any fresh
# `jj git clone` or `jj git init`: --repo config is keyed by
# .jj/repo/config-id and does not survive into a new store.
#
# What it writes (exactly four keys, the R3-sanctioned exception to the
# no-config-mutation rule; announced in the receipt):
#   revset-aliases."immutable_heads()"  builtin union of explicit
#       bookmarks(exact:"...") clauses -- NEVER trunk(): builtin
#       trunk() resolves through remote bookmarks and cannot see a
#       local-only trunk, so protecting via trunk() protects nothing.
#   ui.editor = ":true"          }  editor guard parts 1+2; part 3 is
#   ui.diff-editor = ":true"     }  the JJ_EDITOR env assertion below
#       (JJ_EDITOR OUTRANKS persisted --repo config -- wave-3 A7 --
#       so a set JJ_EDITOR is a hard failure, not a courtesy).
#   merge-tools.difftastic.program = "difft"   (jj's builtin preset
#       invokes a binary literally named "difftastic"; every
#       mainstream install names it "difft").
#
# Protected bookmarks: $PREFLIGHT_PROTECTED_BOOKMARKS (space-separated)
# or auto-resolved from the remote HEAD / conventional names.  FAILS
# CLOSED when unresolvable: silently protecting nothing is the exact
# failure mode this script exists to prevent.
#
# Receipt (stdout, single line):
#   PREFLIGHT-OK shape=<s> store=<id> protected=[a b] probe=<state>
#   PREFLIGHT-SKIP shape=git-only
# Exit: 0 ok/skip, 1 failure, 3 worktree-shadowed (propagated).

set -o nounset

_die() {
	printf 'PREFLIGHT-FAIL %s\n' "$*"
	exit 1
}

_scriptdir=$(dirname "$0")
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

_alias='builtin_immutable_heads()'
for _b in $_protected; do
	_alias="$_alias | bookmarks(exact:\"$_b\")"
done

jj config set --repo 'revset-aliases."immutable_heads()"' "$_alias" \
	|| _die 'jj config set immutable_heads failed'
jj config set --repo ui.editor ':true' || _die 'jj config set ui.editor failed'
jj config set --repo ui.diff-editor ':true' || _die 'jj config set ui.diff-editor failed'
jj config set --repo merge-tools.difftastic.program 'difft' \
	|| _die 'jj config set merge-tools failed'

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
_repo_dir=$(jj root)/.jj/repo
[ -f "$_repo_dir" ] && _repo_dir=$(cat "$_repo_dir")
_store=$(cat "$_repo_dir/config-id" 2> /dev/null) || _store='unknown'

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

printf 'PREFLIGHT-OK shape=%s store=%s protected=[%s] probe=%s\n' \
	"$_shape" "$_store" "$_protected" "$_probe"
