#!/usr/bin/env bats
# Characterization of scripts/git_diff_safe.sh.

load test_helper

@test "git_diff_safe: usage without a subcommand exits 2" {
	run "$SCRIPTS/git_diff_safe.sh"
	[ "$status" -eq 2 ]
}

@test "git_diff_safe: diff on a clean colocated tree exits 0 with no output" {
	local d
	d="$(fx_colocated r)"
	run env -C "$d" "$SCRIPTS/git_diff_safe.sh" diff
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "git_diff_safe: a jj revset handed to git is loud, exit 1" {
	local d
	d="$(fx_colocated r)"
	run --separate-stderr env -C "$d" "$SCRIPTS/git_diff_safe.sh" diff '@-'
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"git diff exited 128"* ]]
}
