#!/bin/sh
# onboard.sh -- record and apply the per-repository jj conversion
# decision.  The decision lives in `git config --local`: never pushed,
# invisible to reviewers, and no file appears in the working tree.
#
# Usage: onboard.sh <status|record|apply|reset> [OPTIONS]
#   status             print the recorded decision; exit 0 in every shape
#   record --decline   record a decline (only a user invocation re-asks)
#   record --level L   record a conversion at level L
#   apply --level L    run the prechecks, create the colocated store,
#                      run preflight.sh --level L, record the decision
#   reset              remove the recorded keys; never touches the store
#   --dry-run          with apply: run the prechecks, change nothing
#
# Keys written with `git config --local`:
#   vcs-workflow.onboarding  converted | declined
#   vcs-workflow.level       oplog | standard | full
#   vcs-workflow.decided     ISO date, UTC
#
# Every precheck runs BEFORE the store is created, so a refusal never
# leaves a half-converted repo.  Two of them can be downgraded to a
# warning by the caller:
#   ONBOARD_ALLOW_INDEX=1       accept a non-empty git index; any jj
#       working-copy update erases it (warns index-flattened)
#   ONBOARD_ALLOW_SUBMODULES=1  accept a .gitmodules repo; jj does not
#       track submodule contents (warns submodules)
#
# At level standard or full the store's first snapshot must not swallow
# the agent scratch trees, so `.local/` and `.cache/` are ensured
# ignored through .git/info/exclude -- local, never .gitignore, because
# the repo may not be ours.  Appending warns exclude-added.
#
# Receipts (stdout, single lines):
#   ONBOARD-STATUS shape=<s> onboarding=<converted|declined|undecided> level=<L|->
#   ONBOARD-OK level=<L> shape=<s> store=<id> protected=[a b] warns=[w]
#   ONBOARD-OK onboarding=<converted|declined> level=<L|->   (record)
#   ONBOARD-OK reset
#   ONBOARD-DRY-RUN level=<L> shape=<s> init=<yes|no> warns=[w]
#   ONBOARD-SKIP reason=<jj-absent|linked-worktree main=<p>>
#   ONBOARD-REFUSE reason=<...>            detail and remedies on stderr
#       reasons: worktree-shadowed, no-vcs, no-git-config level=<L|->,
#       jj-editor, non-colocated-store, git-in-progress, index-not-empty,
#       identity, no-protected-bookmark, protected-bookmark-name,
#       snapshot-hygiene, submodules, nested-worktrees, init-failed, and
#       `preflight`, `exclude-write`, and `config-write`, each carrying
#       store-created=<yes|no>: whether this run left a store behind.
#
# `status` reports a secondary workspace's decision from its PRIMARY,
# where the keys live; `record` refuses what it cannot store -- any
# decision in a repository-less directory, and a decline or a level
# other than full in a jj-only repo.
# Exit: 0 ok or skip, 1 refuse or failure, 2 usage or no VCS,
#       3 worktree-shadowed.

set -o nounset
# PREFLIGHT_PROTECTED_BOOKMARKS is word-split on purpose; -f keeps a
# name such as '*' a literal (and refused) instead of a directory
# listing.  Nothing here relies on pathname expansion.
set -f

SCRIPTDIR=$(dirname "$0")
# shellcheck source=_lib.sh disable=SC1091
. "$SCRIPTDIR/_lib.sh"

CMD=''
LEVEL=''
DECLINE=0
DRY_RUN=0
SHAPE=''
ROOT=''
WARNS=''
STORE_CREATED='no'

_usage() {
	sed -n '6,13p' "$0" | sed 's/^# \{0,1\}//'
}

_bail() {
	_usage >&2
	exit 2
}

_skip() {
	printf 'ONBOARD-SKIP reason=%s\n' "$*"
	exit 0
}

# _refuse REASON [DETAIL...] -- receipt on stdout, detail on stderr.
_refuse() {
	_reason=$1
	shift
	[ "$#" -eq 0 ] || printf '%s\n' "$@" >&2
	printf 'ONBOARD-REFUSE reason=%s\n' "$_reason"
	exit 1
}

# _cfg KEY DEFAULT -- read a git config key across merged scopes, the
# form every other reader of these keys uses.
_cfg() {
	_v=$(git config --get "$1" 2> /dev/null) || _v=''
	[ -n "$_v" ] || _v=$2
	printf '%s' "$_v"
}

_parse_args() {
	CMD=${1:-}
	[ -n "$CMD" ] || return 1
	shift
	while [ "$#" -gt 0 ]; do
		case "$1" in
			--level)
				[ "$#" -ge 2 ] || return 1
				LEVEL=$2
				shift 2
				;;
			--decline) DECLINE=1 && shift ;;
			--dry-run) DRY_RUN=1 && shift ;;
			*) return 1 ;;
		esac
	done
}

_validate_level() {
	case "$LEVEL" in
		oplog | standard | full) ;;
		*) _bail ;;
	esac
}

# Shape is structural, not a mutation; status reports it in every shape,
# worktree-shadowed included, so the entry gate can call status first.
_read_shape() {
	SHAPE=$("$SCRIPTDIR/detect_shape.sh" 2> /dev/null) || :
	[ -n "$SHAPE" ] || SHAPE='none'
}

# git-toplevel first, not vcs_primary_root: this is the checkout being
# converted, and `git worktree list` reports physical paths the
# nested-worktree check compares by prefix.
_resolve_root() {
	ROOT=$(git rev-parse --show-toplevel 2> /dev/null) \
		|| ROOT=$(jj root 2> /dev/null) \
		|| ROOT=$PWD
	ROOT=$(vcs_physical "$ROOT") || ROOT=$PWD
}

# --- prechecks, in order, all before any store is created -------------

_ck_jj() {
	command -v jj > /dev/null 2>&1 || _skip 'jj-absent'
}

_ck_shape() {
	_read_shape
	if [ "$SHAPE" = 'worktree-shadowed' ]; then
		printf 'jj resolves to a different root than git here; use plain git\n' >&2
		printf 'ONBOARD-REFUSE reason=worktree-shadowed\n'
		exit 3
	fi
	case "$SHAPE" in
		git-only | colocated | jj-only) ;;
		*)
			printf 'ONBOARD-REFUSE reason=no-vcs shape=%s\n' "$SHAPE"
			exit 2
			;;
	esac
}

# Both paths are asked for in the same form: git answers --git-dir
# relative to the caller's directory and --git-common-dir absolutely
# from a subdirectory, so comparing the raw answers calls every
# subdirectory a linked worktree.
_ck_linked_worktree() {
	_gd=$(git rev-parse --path-format=absolute --git-dir 2> /dev/null) || return 0
	_cd=$(git rev-parse --path-format=absolute --git-common-dir 2> /dev/null) || return 0
	[ "$_gd" = "$_cd" ] && return 0
	_skip "linked-worktree main=$(dirname "$_cd")"
}

# JJ_EDITOR outranks the --repo ui.editor key preflight persists, so a
# set JJ_EDITOR fails preflight -- and would fail it after the store
# already existed.
_ck_editor() {
	[ -n "${JJ_EDITOR:-}" ] || return 0
	[ "$JJ_EDITOR" = ':true' ] && return 0
	_refuse 'jj-editor' \
		"JJ_EDITOR is set ('$JJ_EDITOR') and outranks --repo ui.editor;" \
		"unset it or set it to ':true'."
}

# A jj-only repo has no git config to record a decision in, and every
# reader resolves its level as full; any other level, and a decline,
# would record nothing and report success.
_ck_level_shape() {
	[ "$SHAPE" = 'jj-only' ] || return 0
	[ "$LEVEL" = 'full' ] && [ "$DECLINE" -eq 0 ] && return 0
	_refuse "no-git-config level=${LEVEL:--}" \
		'a jj-only repo has no git config to record the decision in;' \
		'its level is full by definition and a decline has nowhere to go.' \
		'Convert with --level full, or leave the repository as it is.'
}

# jj-only also reports "not colocated"; only a store sharing a directory
# with git is the refusal.  Enabling colocation is the user's call.
_ck_colocation() {
	[ "$SHAPE" = 'colocated' ] || return 0
	jj git colocation status 2> /dev/null | grep -q 'not colocated' || return 0
	_refuse 'non-colocated-store' \
		'a jj store exists here but is not colocated with git.' \
		'Run "jj git colocation enable" yourself, then re-run onboarding;' \
		'this script never runs it for you.'
}

_ck_git_state() {
	_gd=$(git rev-parse --git-dir 2> /dev/null) || return 0
	for _f in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD BISECT_LOG; do
		[ -e "$_gd/$_f" ] \
			&& _refuse 'git-in-progress' "$_gd/$_f exists; finish or abort it first."
	done
	git diff --cached --quiet 2> /dev/null && return 0
	if [ "${ONBOARD_ALLOW_INDEX:-0}" = '1' ]; then
		WARNS="$WARNS index-flattened"
		return 0
	fi
	_refuse 'index-not-empty' \
		'the git index carries staged changes; any jj working-copy update' \
		'erases it.  Commit or reset the index, or set ONBOARD_ALLOW_INDEX=1.'
}

# jj never falls back to the git identity, so a placeholder identity
# would author every captured commit.
_ck_identity() {
	_name=$(jj config get user.name 2> /dev/null) || _name=''
	_email=$(jj config get user.email 2> /dev/null) || _email=''
	[ -n "$_name" ] && [ -n "$_email" ] \
		|| _refuse 'identity' 'jj user.name or user.email is empty; set both first.'
	# Addresses are case-insensitive, so the patterns match the folded
	# form: A@EXAMPLE.COM is the same placeholder as a@example.com.
	_folded=$(printf '%s' "$_email" | tr '[:upper:]' '[:lower:]')
	case "$_folded" in
		*.invalid | *@example | *@example.* | *.example.com)
			_refuse 'identity' "jj user.email '$_email' is a placeholder."
			;;
	esac
}

# preflight.sh interpolates each name into a revset string literal and
# refuses a name that could close it -- but only once the store exists.
# The same character set is enforced here, before anything is created.
_ck_bookmark_names() {
	for _b in ${PREFLIGHT_PROTECTED_BOOKMARKS:-}; do
		case $_b in
			*[!A-Za-z0-9._/+-]*)
				_refuse 'protected-bookmark-name' \
					"PREFLIGHT_PROTECTED_BOOKMARKS names '$_b';" \
					'allowed characters are A-Za-z0-9._/+- and preflight' \
					'refuses anything else.'
				;;
		esac
	done
}

# Resolvable with git alone: the store does not exist yet, so preflight's
# jj-side resolution cannot be asked.
_ck_protected() {
	if [ -n "${PREFLIGHT_PROTECTED_BOOKMARKS:-}" ]; then
		_ck_bookmark_names
		return 0
	fi
	git rev-parse --git-dir > /dev/null 2>&1 || return 0
	git symbolic-ref -q refs/remotes/origin/HEAD > /dev/null 2>&1 && return 0
	for _b in main master trunk; do
		git show-ref -q --verify "refs/heads/$_b" && return 0
	done
	_refuse 'no-protected-bookmark' \
		'no origin/HEAD and no local main, master, or trunk bookmark.' \
		'Set PREFLIGHT_PROTECTED_BOOKMARKS to the branch to protect.'
}

# Listed and measured at ROOT, not at the caller's directory: apply from
# a subdirectory must scan the whole working copy jj will snapshot, and
# report paths the user can act on.
_big_untracked() {
	git -C "$ROOT" ls-files --others --exclude-standard 2> /dev/null \
		| while IFS= read -r _p; do
			[ -f "$ROOT/$_p" ] || continue
			[ "$(wc -c < "$ROOT/$_p")" -gt 1048576 ] && printf '%s/%s\n' "$ROOT" "$_p"
		done
}

_odd_nodes() {
	find "$ROOT" \( -name .git -o -name .jj \) -prune -o \
		! -type d ! -type f ! -type l -print 2> /dev/null
}

# jj snapshots the whole working copy; a 1 MiB+ untracked file is
# silently skipped and a fifo or device node stalls or errors the
# snapshot.  Both are the user's to resolve.
_ck_hygiene() {
	_bad=$(
		_big_untracked
		_odd_nodes
	)
	[ -n "$_bad" ] || return 0
	_refuse 'snapshot-hygiene' \
		'these untracked paths block a clean first snapshot:' \
		"$_bad" \
		'Remedy: list them in .git/info/exclude (local, never .gitignore in' \
		'a repo you do not own), or raise snapshot.max-new-file-size with' \
		'"jj config set --repo snapshot.max-new-file-size <bytes>".'
}

_ck_submodules() {
	[ -f "$ROOT/.gitmodules" ] || return 0
	if [ "${ONBOARD_ALLOW_SUBMODULES:-0}" = '1' ]; then
		WARNS="$WARNS submodules"
		return 0
	fi
	_refuse 'submodules' \
		'.gitmodules is present; jj does not track submodule contents.' \
		'Set ONBOARD_ALLOW_SUBMODULES=1 to convert the superproject anyway.'
}

# A nested git worktree is the worktree-shadowed shape waiting to happen:
# jj there would read and mutate the parent checkout.
_ck_nested_worktrees() {
	_nested=$(git worktree list --porcelain 2> /dev/null \
		| sed -n 's/^worktree //p' | awk -v r="$ROOT/" 'index($0, r) == 1')
	[ -n "$_nested" ] || return 0
	_refuse 'nested-worktrees' \
		'these git worktrees live under the repo root and would be shadowed:' \
		"$_nested" \
		'Move them beside the root, or remove them, before converting.'
}

_ck_hooks() {
	case "$LEVEL" in
		standard | full) ;;
		*) return 0 ;;
	esac
	if [ -f "$ROOT/hk.pkl" ] || [ -f "$ROOT/.hk.pkl" ] \
		|| [ -f "$ROOT/.git/hooks/pre-commit" ]; then
		WARNS="$WARNS git-hooks-bypassed"
	fi
}

_run_prechecks() {
	_ck_jj
	_ck_shape
	_ck_level_shape
	_resolve_root
	_ck_linked_worktree
	_ck_editor
	_ck_colocation
	_ck_git_state
	_ck_identity
	_ck_protected
	_ck_hygiene
	_ck_submodules
	_ck_nested_worktrees
	_ck_hooks
}

# --- application ------------------------------------------------------

# A concurrent apply can win the race and leave our init failing
# against a store that now exists; re-reading the shape tells that
# apart from a real failure.
_init_raced() {
	_read_shape
	[ "$SHAPE" = 'colocated' ] \
		|| _refuse 'init-failed' '"jj git init --colocate" failed.'
}

_init_store() {
	[ "$SHAPE" = 'git-only' ] || return 0
	if jj git init --colocate "$ROOT" > /dev/null; then
		STORE_CREATED='yes'
	else
		_init_raced
	fi
	SHAPE='colocated'
}

# jj snapshots the whole working copy, so the agent scratch trees are
# ignored before any further jj command runs.  .git/info/exclude is
# local and unpushed; .gitignore belongs to the repo's owner.
_append_exclude() {
	mkdir -p "$ROOT/.git/info" \
		|| _refuse "exclude-write store-created=$STORE_CREATED" \
			"cannot create $ROOT/.git/info."
	printf '%s/\n' "$1" >> "$ROOT/.git/info/exclude" \
		|| _refuse "exclude-write store-created=$STORE_CREATED" \
			"cannot append to $ROOT/.git/info/exclude."
	case "$WARNS" in
		*exclude-added*) ;;
		*) WARNS="$WARNS exclude-added" ;;
	esac
}

_ensure_excluded() {
	[ "$SHAPE" = 'colocated' ] || return 0
	case "$LEVEL" in
		standard | full) ;;
		*) return 0 ;;
	esac
	for _d in .local .cache; do
		git -C "$ROOT" check-ignore -q "$_d/x" || _append_exclude "$_d"
	done
}

# preflight.sh owns the --repo keys; its receipt is the store id and the
# protected set, so it is printed verbatim and then quoted.
_run_preflight() {
	_receipt=$("$SCRIPTDIR/preflight.sh" --level "$LEVEL")
	_rc=$?
	printf '%s\n' "$_receipt"
	if [ "$_rc" -ne 0 ]; then
		printf 'ONBOARD-REFUSE reason=preflight store-created=%s\n' "$STORE_CREATED"
		exit 1
	fi
	_store=$(printf '%s' "$_receipt" | sed -n 's/.*store=\([^ ]*\).*/\1/p')
	_protected=$(printf '%s' "$_receipt" | sed -n 's/.*protected=\[\([^]]*\)\].*/\1/p')
}

# A jj-only shape has no git config to record in; its level is full by
# definition (preflight.sh and gate.sh resolve it the same way).
_record() {
	[ "$SHAPE" = 'jj-only' ] && return 0
	git config --local vcs-workflow.onboarding "$1" || return 1
	if [ -n "$LEVEL" ]; then
		git config --local vcs-workflow.level "$LEVEL" || return 1
	fi
	git config --local vcs-workflow.decided "$(date -u +%Y-%m-%d)" || return 1
	return 0
}

# A secondary workspace holds no configuration of its own: the decision
# belongs to the primary, and reading it anywhere else reports full for
# a repository recorded oplog.  An unresolvable primary keeps the
# structural answer a workspace always had.
_status_workspace() {
	_lvl='full'
	_on='converted'
	if _p=$(vcs_primary_root); then
		_lvl=$(vcs_level "$_p")
		_on=$(git -C "$_p" config --get vcs-workflow.onboarding 2> /dev/null) \
			|| _on='converted'
	fi
	printf 'ONBOARD-STATUS shape=jj-workspace onboarding=%s level=%s\n' \
		"${_on:-converted}" "$_lvl"
}

_cmd_status() {
	_read_shape
	case "$SHAPE" in
		jj-workspace)
			_status_workspace
			return 0
			;;
		jj-only)
			printf 'ONBOARD-STATUS shape=jj-only onboarding=converted level=full\n'
			return 0
			;;
		none)
			printf 'ONBOARD-STATUS shape=none onboarding=undecided level=-\n'
			return 0
			;;
	esac
	# A store already exists in a colocated shape, and every reader
	# resolves an absent level key there as full; only a git-only repo
	# is genuinely undecided about its level.
	_lvl='-'
	[ "$SHAPE" = 'colocated' ] && _lvl='full'
	printf 'ONBOARD-STATUS shape=%s onboarding=%s level=%s\n' "$SHAPE" \
		"$(_cfg vcs-workflow.onboarding undecided)" "$(_cfg vcs-workflow.level "$_lvl")"
}

# `record` writes git config, so the shape decides whether there is
# anywhere to write: without it a decision is reported recorded and the
# next status call still reads undecided.
_ck_record_shape() {
	_read_shape
	[ "$SHAPE" = 'none' ] || return 0
	printf 'ONBOARD-REFUSE reason=no-vcs shape=none\n'
	exit 2
}

_cmd_record() {
	_ck_record_shape
	if [ "$DECLINE" -eq 1 ]; then
		[ -z "$LEVEL" ] || _bail
		_ck_level_shape
		_record declined || _refuse "config-write store-created=$STORE_CREATED" \
			'git config --local failed.'
		printf 'ONBOARD-OK onboarding=declined level=-\n'
		return 0
	fi
	[ -n "$LEVEL" ] || _bail
	_validate_level
	_ck_level_shape
	_record converted || _refuse "config-write store-created=$STORE_CREATED" \
		'git config --local failed.'
	printf 'ONBOARD-OK onboarding=converted level=%s\n' "$LEVEL"
}

_cmd_reset() {
	git config --local --remove-section vcs-workflow 2> /dev/null || true
	printf 'ONBOARD-OK reset\n'
}

_cmd_apply() {
	[ -n "$LEVEL" ] || _bail
	_validate_level
	_run_prechecks
	if [ "$DRY_RUN" -eq 1 ]; then
		[ "$SHAPE" = 'git-only' ] && _init='yes' || _init='no'
		printf 'ONBOARD-DRY-RUN level=%s shape=%s init=%s warns=[%s]\n' \
			"$LEVEL" "$SHAPE" "$_init" "${WARNS# }"
		return 0
	fi
	_init_store
	_ensure_excluded
	_run_preflight
	_record converted || _refuse "config-write store-created=$STORE_CREATED" \
		'git config --local failed.'
	printf 'ONBOARD-OK level=%s shape=%s store=%s protected=[%s] warns=[%s]\n' \
		"$LEVEL" "$SHAPE" "$_store" "$_protected" "${WARNS# }"
}

main() {
	_parse_args "$@" || _bail
	case "$CMD" in
		status) _cmd_status ;;
		record) _cmd_record ;;
		apply) _cmd_apply ;;
		reset) _cmd_reset ;;
		*) _bail ;;
	esac
}

main "$@"
