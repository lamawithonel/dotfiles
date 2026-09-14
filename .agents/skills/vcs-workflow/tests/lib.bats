#!/usr/bin/env bats
# Unit contract of scripts/_lib.sh, the dot-sourced helpers every
# script shares.

load test_helper

@test "lib: vcs_physical fails on a path that does not resolve" {
	. "$SCRIPTS/_lib.sh"
	run vcs_physical "$BATS_TEST_TMPDIR/missing"
	[ "$status" -eq 1 ]
}

@test "lib: vcs_primary_root from a secondary workspace is the primary" {
	local w
	w="$(fx_jj_workspace r)"
	. "$SCRIPTS/_lib.sh"
	run vcs_primary_root "$w"
	[ "$status" -eq 0 ]
	[ "$output" = "$(readlink -f "$BATS_TEST_TMPDIR/r")" ]
}

@test "lib: vcs_primary_root fails outside any jj repo" {
	mkdir -p "$BATS_TEST_TMPDIR/plain"
	. "$SCRIPTS/_lib.sh"
	run vcs_primary_root "$BATS_TEST_TMPDIR/plain"
	[ "$status" -eq 1 ]
}

@test "lib: vcs_level reads the key recorded at the root" {
	local d
	d="$(fx_colocated r)"
	git -C "$d" config vcs-workflow.level oplog
	. "$SCRIPTS/_lib.sh"
	run vcs_level "$d"
	[ "$output" = "oplog" ]
}

@test "lib: vcs_level is full when the root has no key" {
	local d
	d="$(fx_colocated r)"
	. "$SCRIPTS/_lib.sh"
	run vcs_level "$d"
	[ "$output" = "full" ]
}

@test "lib: vcs_level is full for a root without its own git repo, even inside one" {
	local d
	d="$(fx_colocated r)"
	git -C "$d" config vcs-workflow.level oplog
	mkdir -p "$d/nested"
	env -C "$d/nested" jj git init --no-colocate > /dev/null 2>&1
	[ -d "$d/nested/.jj" ]
	. "$SCRIPTS/_lib.sh"
	run vcs_level "$d/nested"
	[ "$output" = "full" ]
}

@test "lib: vcs_state_dir is the primary's state directory" {
	. "$SCRIPTS/_lib.sh"
	run vcs_state_dir /tmp/x
	[ "$output" = "/tmp/x/.local/state/agents/vcs" ]
}
