#!/usr/bin/env bats
# Characterization of scripts/detect_shape.sh: one token on stdout per
# shape, exit 0 / 2 / 3 as documented in its header.

load test_helper

@test "detect_shape: git-only repo prints git-only, exit 0" {
	local d
	d="$(fx_git_only r)"
	run env -C "$d" "$SCRIPTS/detect_shape.sh"
	[ "$status" -eq 0 ]
	[ "$output" = "git-only" ]
}

@test "detect_shape: colocated repo prints colocated, exit 0" {
	local d
	d="$(fx_colocated r)"
	assert_repo_config_isolated "$d"
	run env -C "$d" "$SCRIPTS/detect_shape.sh"
	[ "$status" -eq 0 ]
	[ "$output" = "colocated" ]
}

@test "detect_shape: jj-only repo prints jj-only, exit 0" {
	local d
	d="$(fx_jj_only r)"
	run env -C "$d" "$SCRIPTS/detect_shape.sh"
	[ "$status" -eq 0 ]
	[ "$output" = "jj-only" ]
}

@test "detect_shape: secondary jj workspace prints jj-workspace, exit 0" {
	local w
	w="$(fx_jj_workspace r)"
	run env -C "$w" "$SCRIPTS/detect_shape.sh"
	[ "$status" -eq 0 ]
	[ "$output" = "jj-workspace" ]
}

@test "detect_shape: nested linked worktree prints worktree-shadowed, exit 3" {
	local w
	w="$(fx_shadowed r)"
	run env -C "$w" "$SCRIPTS/detect_shape.sh"
	[ "$status" -eq 3 ]
	[ "$output" = "worktree-shadowed" ]
}

@test "detect_shape: sibling linked worktree prints git-only, exit 0" {
	local w
	w="$(fx_linked_worktree r)"
	run env -C "$w" "$SCRIPTS/detect_shape.sh"
	[ "$status" -eq 0 ]
	[ "$output" = "git-only" ]
}

@test "detect_shape: symlinked repo root prints colocated, exit 0" {
	local l
	l="$(fx_symlinked_root r)"
	run env -C "$l" "$SCRIPTS/detect_shape.sh"
	[ "$status" -eq 0 ]
	[ "$output" = "colocated" ]
}

@test "detect_shape: jj absent prints git-only, note on stderr, exit 0" {
	local d nobin
	d="$(fx_git_only r)"
	nobin="$(path_without jj)"
	run --separate-stderr env -C "$d" PATH="$nobin" "$SCRIPTS/detect_shape.sh"
	[ "$status" -eq 0 ]
	[ "$output" = "git-only" ]
	[[ "$stderr" == *"detect_shape: jj not on PATH"* ]]
}

@test "detect_shape: directory with no VCS prints none, exit 2" {
	mkdir -p "$BATS_TEST_TMPDIR/plain"
	run env -C "$BATS_TEST_TMPDIR/plain" "$SCRIPTS/detect_shape.sh"
	[ "$status" -eq 2 ]
	[ "$output" = "none" ]
}
