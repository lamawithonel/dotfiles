#!/bin/sh
# emit_handoff.sh -- assemble the vcs-handoff/2 receipt: the record of
# what this skill prepared, read at serialization time by this skill.
# git-commit does not consume it.  Read-only aggregation; every value
# is a command exit code, a `jj log -T` projection, or a parsed receipt
# -- never agent prose.
#
# Usage: emit_handoff.sh [--range REVSET]
#   (default range: '(trunk()::@-) ~ root()' -- the promotable stack,
#    excluding the open working-copy commit)
#
# Sources: detect_shape.sh, a fresh idempotent preflight.sh run,
# gate.json (gate.sh's receipt), compat-probe.json (probe receipt),
# and jj template projections.  Output (under the PRIMARY workspace
# root, never an ephemeral secondary workspace):
#   <primary-root>/.local/state/agents/vcs/handoff.json
# Exit: 0 ready, 1 not ready, 2 usage, 3 worktree-shadowed,
#       5 git-only or none, 6 level-blocked.

set -o nounset

_scriptdir=$(dirname "$0")
# shellcheck source=_lib.sh disable=SC1091
. "$_scriptdir/_lib.sh"

RANGE='(trunk()::@-) ~ root()'

_usage_exit() {
	printf 'Usage: emit_handoff.sh [--range REVSET]\n' >&2
	exit 2
}

_parse_args() {
	if [ "${1:-}" = '--range' ]; then
		[ "$#" -ge 2 ] || _usage_exit
		RANGE=$2
	elif [ "$#" -gt 0 ]; then
		_usage_exit
	fi
}

_check_shape() {
	_shape=$("$_scriptdir/detect_shape.sh")
	if [ "$?" -eq 3 ]; then
		printf 'HANDOFF-FAIL shape=worktree-shadowed\n'
		exit 3
	fi
	# No store, nothing to hand off: refuse before any jj command runs.
	if [ "$_shape" = 'git-only' ] || [ "$_shape" = 'none' ]; then
		printf 'HANDOFF-FAIL shape=%s\n' "$_shape"
		exit 5
	fi
}

# The workspace is ephemeral, so the receipt belongs to the primary
# root (_lib.sh resolves it through the .jj/repo pointer file).
#
# The workspace name comes from that same pointer file, not from the
# `working_copies` template field: that field is multi-valued and names
# every workspace parked on the commit, so it cannot say which one we
# are in.  A workspace added under an explicit --name that differs from
# its directory is reported by its directory.
_resolve_workspace() {
	_jj_root=$(jj root)
	_root=$(vcs_primary_root) || _root=$_jj_root
	if [ -f "$_jj_root/.jj/repo" ]; then
		_is_secondary=true
		_ws_name=$(basename "$_jj_root")
	else
		_is_secondary=false
		_ws_name='default'
	fi
}

# At level oplog the pipeline stops at capture: there is nothing to hand
# off, and the receipt directory itself would surface as an untracked
# path in a third-party checkout.  Refuse before creating anything.
_check_level() {
	_level=$(vcs_level "$_root")
	if [ "$_level" = 'oplog' ]; then
		printf 'HANDOFF-FAIL LEVEL-BLOCKED level=oplog\n'
		exit 6
	fi
	_origin=$(git -C "$_root" config --get remote.origin.url 2> /dev/null)
}

_run_preflight() {
	_pre=$("$_scriptdir/preflight.sh")
	_pre_rc=$?
	_pre_ok=false
	[ "$_pre_rc" -eq 0 ] && _pre_ok=true
	_protected=$(printf '%s' "$_pre" | sed -n 's/.*protected=\[\([^]]*\)\].*/\1/p')
	_store=$(printf '%s' "$_pre" | sed -n 's/.*store=\([^ ]*\).*/\1/p')
}

_read_receipts() {
	_gate_file="$_state_dir/gate.json"
	_probe_file="$HOME/.agents/.local/state/vcs-workflow/compat-probe.json"
	_gate_json='null'
	[ -f "$_gate_file" ] && _gate_json=$(cat "$_gate_file")
	_probe_verdict='missing'
	_probe_at=''
	if [ -f "$_probe_file" ]; then
		_probe_verdict=$(jq -r '.verdict' "$_probe_file" 2> /dev/null || echo 'unreadable')
		_probe_at=$(jq -r '.probed_at' "$_probe_file" 2> /dev/null || echo '')
	fi
}

# Stack entries: one JSON object per revision.  One projection per
# field keeps every value quote-safe (a first_line may contain spaces,
# quotes, or anything else a description can hold).
_collect_stack() {
	_base_commit=$(jj log -r 'trunk()' --no-graph -T 'commit_id' 2> /dev/null | head -c 40)
	_op_id=$(jj op log -n1 --no-graph -T 'id.short()' 2> /dev/null)
	_stack_tmp=$(mktemp "${TMPDIR:-/tmp}/handoff-stack.XXXXXX")
	for _rev in $(jj log -r "$RANGE" --no-graph -T 'change_id.short() ++ "\n"' 2> /dev/null); do
		_commit=$(jj log -r "$_rev" --no-graph -T 'commit_id.short()' 2> /dev/null)
		_first=$(jj log -r "$_rev" --no-graph -T 'description.first_line()' 2> /dev/null)
		_files=$(jj diff -r "$_rev" --summary 2> /dev/null | awk '{print $2}')
		jq -n --arg c "$_rev" --arg k "$_commit" --arg f "$_first" \
			--arg files "$_files" \
			'{change_id: $c, commit_id: $k, first_line: $f,
			  files: ($files | split("\n") | map(select(length > 0)))}' >> "$_stack_tmp"
	done
	_stack_json=$(jq -s '.' "$_stack_tmp")
	rm -f "$_stack_tmp"
	_conflicts=$(jj log -r "conflicts() & ($RANGE)" --no-graph -T 'change_id.short() ++ "\n"' 2> /dev/null)
}

# message_hints.scope: the common leading path segment across every
# changed file in the stack, else the shared file stem, else "".
_collect_scope() {
	_all_files=$(printf '%s' "$_stack_json" | jq -r '.[].files[]' | sort -u)
	_scope=$(printf '%s\n' "$_all_files" \
		| awk -F/ 'NF>1{print $1; next}{split($1,a,"."); print a[1]}' | sort -u \
		| awk 'NR==1{s=$0} NR>1{s=""} END{print s}')
}

_collect_readiness() {
	_gate_verdict=$(printf '%s' "$_gate_json" | jq -r '.verdict // "missing"')
	_ready=false
	_fails=''
	[ "$_pre_ok" = true ] || _fails="$_fails preflight"
	[ "$_gate_verdict" = 'pass' ] || _fails="$_fails gate"
	[ -z "$_conflicts" ] || _fails="$_fails conflicts"
	[ -z "$_fails" ] && _ready=true

	_warns=''
	[ "$_probe_verdict" = 'green' ] || _warns="$_warns probe-$_probe_verdict"
	# R6: warn when the probe receipt is older than 7 days (or undated).
	if [ ! -f "$_probe_file" ] || [ -z "$(find "$_probe_file" -mtime -7 2> /dev/null)" ]; then
		_warns="$_warns probe-stale"
	fi
	_warns="$_warns fetch-not-run"
}

_write_receipt() {
	_receipt="$_state_dir/handoff.json"
	_tmp="$_receipt.tmp"
	jq -n \
		--arg shape "$_shape" \
		--arg level "$_level" \
		--arg ws_name "$_ws_name" \
		--arg is_secondary "$_is_secondary" \
		--arg root "$_root" \
		--arg origin "$_origin" \
		--arg probe_verdict "$_probe_verdict" \
		--arg probe_at "$_probe_at" \
		--arg pre_ok "$_pre_ok" \
		--arg protected "$_protected" \
		--arg store "$_store" \
		--arg range "$RANGE" \
		--arg base_commit "$_base_commit" \
		--arg op_id "$_op_id" \
		--arg conflicts "$_conflicts" \
		--arg scope "$_scope" \
		--arg ready "$_ready" \
		--arg fails "${_fails# }" \
		--arg warns "${_warns# }" \
		--argjson stack "$_stack_json" \
		--argjson gate "$_gate_json" \
		'{
		  schema: "vcs-handoff/2",
		  shape: $shape,
		  level: $level,
		  toolchain: {probe_verdict: $probe_verdict, probe_at: $probe_at},
		  preflight: {
		    ok: ($pre_ok == "true"),
		    protected: ($protected | split(" ") | map(select(length > 0))),
		    store_id: $store,
		    editor_guard: ($pre_ok == "true")
		  },
		  base: {
		    revset: "trunk()", commit_id: $base_commit, op_id: $op_id,
		    fetched: {ran: false, op_id: null}
		  },
		  stack: $stack,
		  gate: $gate,
		  absorb: {ran: false, op_id: null, destinations: [], residual: null, renames_blocked: false},
		  partition: {grain: "file", splits: [], refused: []},
		  conflicts: ($conflicts | split("\n") | map(select(length > 0))),
		  message_hints: {scope: $scope},
		  workspace: {
		    name: $ws_name, is_secondary: ($is_secondary == "true"),
		    primary_root: $root
		  },
		  repo: {
		    root: $root,
		    origin_url: (if $origin == "" then null else $origin end)
		  },
		  ready: ($ready == "true"),
		  fails: ($fails | split(" ") | map(select(length > 0))),
		  warns: ($warns | split(" ") | map(select(length > 0)))
		}' > "$_tmp" \
		&& mv "$_tmp" "$_receipt" && return 0
	rm -f "$_tmp"
	printf 'HANDOFF-FAIL jq assembly failed\n'
	exit 1
}

main() {
	_parse_args "$@"
	_check_shape
	_resolve_workspace
	_check_level
	_state_dir=$(vcs_state_dir "$_root")
	mkdir -p "$_state_dir"
	_run_preflight
	_read_receipts
	_collect_stack
	_collect_scope
	_collect_readiness
	_write_receipt
	if [ "$_ready" = true ]; then
		printf 'HANDOFF-OK ready=true receipt=%s\n' "$_receipt"
		exit 0
	fi
	printf 'HANDOFF-NOT-READY fails=[%s] receipt=%s\n' "${_fails# }" "$_receipt"
	exit 1
}

main "$@"
