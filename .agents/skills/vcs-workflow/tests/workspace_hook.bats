#!/usr/bin/env bats
# scripts/workspace_hook.sh -- the Claude Code WorktreeCreate /
# WorktreeRemove hook.  Create prints exactly one stdout line (the jj
# workspace directory); remove prints none.  Every receipt, warning,
# and jj message goes to stderr.

load test_helper

WS_ROOT_REL='agents/jj-workspaces'

# hook EVENT CWD WORKTREE_PATH -- feed the hook one JSON object on
# stdin, keeping stdout and stderr apart.
hook() {
	run --separate-stderr sh "$SCRIPTS/workspace_hook.sh" <<- EOF
		{"session_id":"s1","hook_event_name":"$1","cwd":"$2","worktree_path":"$3"}
	EOF
}

@test "workspace_hook: create prints one jj-workspace directory under the root" {
	local d dir
	d="$(fx_colocated r)"

	hook WorktreeCreate "$d" "$d/.claude/worktrees/feat-x"

	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 1 ]
	dir="$output"
	[ -d "$dir" ]
	[[ "$dir" == "$XDG_DATA_HOME/$WS_ROOT_REL/"* ]]
	[[ "$dir" == */feat-x ]]
	[[ "$stderr" == *"WORKSPACE-CREATE-OK"*"name=feat-x"* ]]
	run env -C "$dir" "$SCRIPTS/detect_shape.sh"
	[ "$status" -eq 0 ]
	[ "$output" = 'jj-workspace' ]
}

@test "workspace_hook: create refuses a git-only primary" {
	local d
	d="$(fx_git_only r)"

	hook WorktreeCreate "$d" "$d/.claude/worktrees/feat-x"

	[ "$status" -eq 1 ]
	[[ "$stderr" == *'WORKSPACE-HOOK-FAIL reason=needs-onboarding'* ]]
	[ ! -d "$XDG_DATA_HOME/$WS_ROOT_REL" ]
}

@test "workspace_hook: create refuses at level oplog" {
	local d
	d="$(fx_colocated r)"
	git -C "$d" config --local vcs-workflow.level oplog

	hook WorktreeCreate "$d" "$d/.claude/worktrees/feat-x"

	[ "$status" -eq 1 ]
	[[ "$stderr" == *'WORKSPACE-HOOK-FAIL reason=level-oplog'* ]]
}

@test "workspace_hook: create on a registered workspace resumes the same directory" {
	local d first
	d="$(fx_colocated r)"
	hook WorktreeCreate "$d" "/ignored/feat-x"
	[ "$status" -eq 0 ]
	first="$output"

	hook WorktreeCreate "$d" "/ignored/feat-x"

	[ "$status" -eq 0 ]
	[ "$output" = "$first" ]
	run env -C "$d" jj workspace list
	[ "$(printf '%s\n' "$output" | grep -c '^feat-x:')" -eq 1 ]
}

@test "workspace_hook: create refuses a directory jj does not know about" {
	local d dir
	d="$(fx_colocated r)"
	hook WorktreeCreate "$d" "/ignored/feat-x"
	dir="$output"
	env -C "$d" jj workspace forget feat-x > /dev/null 2>&1

	hook WorktreeCreate "$d" "/ignored/feat-x"

	[ "$status" -eq 1 ]
	[[ "$stderr" == *'WORKSPACE-HOOK-FAIL reason=orphan-directory'* ]]
	[ -d "$dir" ]
}

@test "workspace_hook: primaries sharing a basename get different slugs" {
	local a b da db
	a="$(fx_colocated p1/repo)"
	b="$(fx_colocated p2/repo)"

	hook WorktreeCreate "$a" "/ignored/w"
	[ "$status" -eq 0 ]
	da="$output"
	hook WorktreeCreate "$b" "/ignored/w"
	[ "$status" -eq 0 ]
	db="$output"

	[ "$da" != "$db" ]
	[[ "$(basename "$(dirname "$da")")" == repo-* ]]
	[[ "$(basename "$(dirname "$db")")" == repo-* ]]
	[ "$(dirname "$da")" != "$(dirname "$db")" ]
}

@test "workspace_hook: worktreeinclude entries are symlinked, missing ones warn" {
	local d dir
	d="$(fx_colocated r)"
	printf '.envrc\nnope.txt\n' > "$d/.gitignore"
	printf 'secret\n' > "$d/.envrc"
	printf '.envrc\nnope.txt\n' > "$d/.worktreeinclude"

	hook WorktreeCreate "$d" "/ignored/w"

	[ "$status" -eq 0 ]
	dir="$output"
	[ -L "$dir/.envrc" ]
	[ "$(cat "$dir/.envrc")" = 'secret' ]
	[[ "$stderr" == *'nope.txt'* ]]
}

@test "workspace_hook: remove snapshots, forgets, and deletes" {
	local d dir
	d="$(fx_colocated r)"
	hook WorktreeCreate "$d" "/ignored/w"
	dir="$output"
	printf 'dirty\n' > "$dir/dirty.txt"

	hook WorktreeRemove "$d" "$dir"

	[ "$status" -eq 0 ]
	[ -z "$output" ]
	[ ! -e "$dir" ]
	[[ "$stderr" == *'WORKSPACE-REMOVE-OK'* ]]
	run env -C "$d" jj workspace list
	[[ "$output" != *'w:'* ]]
	run env -C "$d" jj log -r 'all()' --no-graph -s
	[[ "$output" == *'dirty.txt'* ]]
}

@test "workspace_hook: remove never deletes the path it was handed" {
	local d
	d="$(fx_colocated r)"

	hook WorktreeRemove "$d" "$d"

	[ "$status" -eq 0 ]
	[[ "$stderr" == *'state=absent'* ]]
	[ -d "$d/.jj" ]
}

@test "workspace_hook: remove refuses when no primary can be resolved" {
	hook WorktreeRemove "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR/elsewhere"

	[ "$status" -eq 1 ]
	[[ "$stderr" == *'WORKSPACE-HOOK-FAIL reason=refused-path'* ]]
}

@test "workspace_hook: remove recomputes the proposed in-repo path" {
	local d dir
	d="$(fx_colocated r)"
	hook WorktreeCreate "$d" "$d/.claude/worktrees/w"
	dir="$output"

	hook WorktreeRemove "$d" "$d/.claude/worktrees/w"

	[ "$status" -eq 0 ]
	[ ! -e "$dir" ]
	[[ "$stderr" == *"WORKSPACE-REMOVE-OK name=w dir=$dir"* ]]
	run env -C "$d" jj workspace list
	[[ "$output" != *'w:'* ]]
}

@test "workspace_hook: remove of a vanished directory frees the name" {
	local d dir again
	d="$(fx_colocated r)"
	hook WorktreeCreate "$d" "/ignored/w"
	dir="$output"
	rm -rf "$dir"

	hook WorktreeRemove "$d" "$dir"

	[ "$status" -eq 0 ]
	[[ "$stderr" == *'state=absent'* ]]
	hook WorktreeCreate "$d" "/ignored/w"
	[ "$status" -eq 0 ]
	again="$output"
	[ "$again" = "$dir" ]
	run env -C "$d" jj workspace list
	[ "$(printf '%s\n' "$output" | grep -c '^w:')" -eq 1 ]
}

@test "workspace_hook: remove keeps the directory when forget fails" {
	local d dir stub
	d="$(fx_colocated r)"
	hook WorktreeCreate "$d" "/ignored/w"
	dir="$output"
	stub="$BATS_TEST_TMPDIR/stub"
	mkdir -p "$stub"
	cat > "$stub/jj" <<- EOF
		#!/bin/sh
		case " \$* " in
			*' workspace forget '*) exit 1 ;;
		esac
		exec $(command -v jj) "\$@"
	EOF
	chmod +x "$stub/jj"
	PATH="$stub:$PATH"

	hook WorktreeRemove "$d" "$dir"

	[ "$status" -eq 1 ]
	[[ "$stderr" == *'WORKSPACE-HOOK-FAIL reason=forget-failed'* ]]
	[ -d "$dir/.jj" ]
}

@test "workspace_hook: remove deletes the workspace when the primary is gone" {
	local d dir
	d="$(fx_colocated r)"
	hook WorktreeCreate "$d" "/ignored/w"
	dir="$output"
	rm -rf "$d"

	hook WorktreeRemove "$BATS_TEST_TMPDIR" "$dir"

	[ "$status" -eq 0 ]
	[ ! -e "$dir" ]
}

@test "workspace_hook: remove of an absent directory exits 0" {
	local d dir
	d="$(fx_colocated r)"
	hook WorktreeCreate "$d" "/ignored/w"
	dir="$output"
	hook WorktreeRemove "$d" "$dir"
	[ "$status" -eq 0 ]

	hook WorktreeRemove "$d" "$dir"

	[ "$status" -eq 0 ]
}

@test "workspace_hook: remove from inside the workspace follows the relative pointer" {
	local d dir
	d="$(fx_colocated r)"
	hook WorktreeCreate "$d" "/ignored/w"
	dir="$output"
	# jj writes .jj/repo relative to the workspace's own .jj/: the
	# primary is reachable only by joining it there.
	[[ "$(cat "$dir/.jj/repo")" != /* ]]

	hook WorktreeRemove "$dir" "$dir"

	[ "$status" -eq 0 ]
	[ ! -e "$dir" ]
	[[ "$stderr" == *"WORKSPACE-REMOVE-OK name=w dir=$dir"* ]]
	run env -C "$d" jj workspace list
	[[ "$output" != *'w:'* ]]
}

@test "workspace_hook: an unknown hook event exits 2" {
	hook SessionStart "$BATS_TEST_TMPDIR" "/ignored/w"

	[ "$status" -eq 2 ]
	[[ "$stderr" == *'WORKSPACE-HOOK-FAIL reason=bad-input'* ]]
}

@test "workspace_hook: remove refuses a worktree_path whose basename is a dot component" {
	local d dir
	d="$(fx_colocated r)"
	hook WorktreeCreate "$d" "$d/.claude/worktrees/w"
	dir="$output"

	hook WorktreeRemove "$d" "/nonexistent/x/../.."

	[ "$status" -eq 1 ]
	[[ "$stderr" == *'WORKSPACE-HOOK-FAIL reason=refused-path'* ]]
	[ -d "$dir/.jj" ]
	[ -d "$(dirname "$dir")" ]
}
