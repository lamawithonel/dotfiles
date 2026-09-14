#!/usr/bin/env bats
# Behaviour of scripts/preflight.sh: receipt lines, exit codes, the
# editor guard, the identity assertion, fail-closed bookmark
# resolution, and the per-level set of --repo keys it writes.

load test_helper

# set_identity NAME EMAIL -- rewrite the private jj user config.
set_identity() {
	printf '[user]\nname = "%s"\nemail = "%s"\n\n[ui]\npaginate = "never"\n' \
		"$1" "$2" > "$JJ_CONFIG"
}

@test "preflight: git-only repo prints PREFLIGHT-SKIP, exit 0" {
	local d
	d="$(fx_git_only r)"
	run env -C "$d" "$SCRIPTS/preflight.sh"
	[ "$status" -eq 0 ]
	[ "$output" = "PREFLIGHT-SKIP shape=git-only" ]
}

@test "preflight: worktree-shadowed exits 3" {
	local w
	w="$(fx_shadowed r)"
	run env -C "$w" "$SCRIPTS/preflight.sh"
	[ "$status" -eq 3 ]
	[[ "$output" == PREFLIGHT-FAIL*worktree-shadowed* ]]
}

@test "preflight: a set JJ_EDITOR hard-fails, exit 1" {
	local d
	d="$(fx_colocated r)"
	run env -C "$d" JJ_EDITOR=vim "$SCRIPTS/preflight.sh"
	[ "$status" -eq 1 ]
	[[ "$output" == PREFLIGHT-FAIL*JJ_EDITOR* ]]
}

@test "preflight: colocated repo on main prints PREFLIGHT-OK with protected=[main]" {
	local d
	d="$(fx_colocated r)"
	assert_repo_config_isolated "$d"
	run env -C "$d" "$SCRIPTS/preflight.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == "PREFLIGHT-OK shape=colocated level=full store="*" protected=[main] probe=missing" ]]
}

@test "preflight: the receipt reports the recorded level" {
	local d
	d="$(fx_colocated r)"
	env -C "$d" git config vcs-workflow.level oplog
	run env -C "$d" "$SCRIPTS/preflight.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == "PREFLIGHT-OK shape=colocated level=oplog store="* ]]
}

@test "preflight: a jj-only shape has no level key and reports full" {
	local d
	d="$(fx_jj_only r)"
	run env -C "$d" PREFLIGHT_PROTECTED_BOOKMARKS=main "$SCRIPTS/preflight.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == "PREFLIGHT-OK shape=jj-only level=full store="* ]]
}

@test "preflight: --level overrides the recorded level key" {
	local d
	d="$(fx_colocated r)"
	env -C "$d" git config vcs-workflow.level oplog
	run env -C "$d" "$SCRIPTS/preflight.sh" --level standard
	[ "$status" -eq 0 ]
	[[ "$output" == "PREFLIGHT-OK shape=colocated level=standard store="* ]]
}

@test "preflight: a workspace reads the level from the primary root" {
	local w d
	w="$(fx_jj_workspace r)"
	d="$BATS_TEST_TMPDIR/r"
	env -C "$d" git config vcs-workflow.level standard
	env -C "$d" "$SCRIPTS/preflight.sh" > /dev/null
	run env -C "$w" "$SCRIPTS/preflight.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == "PREFLIGHT-OK shape=jj-workspace level=standard store="* ]]
	run env -C "$w" jj config list --repo
	[[ "$output" == *'snapshot.auto-track = "none"'* ]]
}

@test "preflight: the store id seen from a workspace is the primary's" {
	local w d ws_store primary_store
	w="$(fx_jj_workspace r)"
	d="$BATS_TEST_TMPDIR/r"
	primary_store="$(env -C "$d" "$SCRIPTS/preflight.sh" | sed -n 's/.*store=\([^ ]*\).*/\1/p')"
	ws_store="$(env -C "$w" "$SCRIPTS/preflight.sh" | sed -n 's/.*store=\([^ ]*\).*/\1/p')"
	[ "$primary_store" != unknown ]
	[ -n "$primary_store" ]
	[ "$ws_store" = "$primary_store" ]
}

@test "preflight: an unknown level fails closed, exit 1" {
	local d
	d="$(fx_colocated r)"
	run env -C "$d" "$SCRIPTS/preflight.sh" --level paranoid
	[ "$status" -eq 1 ]
	[[ "$output" == PREFLIGHT-FAIL*level* ]]
}

@test "preflight: the fixture identity fails closed before any write" {
	local d
	d="$(fx_colocated r)"
	set_identity 'VCS Research' 'vcs-research@example.invalid'
	run env -C "$d" "$SCRIPTS/preflight.sh"
	[ "$status" -eq 1 ]
	[[ "$output" == PREFLIGHT-FAIL*identity* ]]
	run --separate-stderr env -C "$d" jj config list --repo
	[ -z "$output" ]
}

@test "preflight: placeholder identities fail closed whatever their case or form" {
	local d addr
	d="$(fx_colocated r)"
	for addr in 'A@EXAMPLE.COM' 'a@test.INVALID' 'a@example' 'a@sub.example.com'; do
		set_identity 'Bats Tester' "$addr"
		run env -C "$d" "$SCRIPTS/preflight.sh"
		[ "$status" -eq 1 ]
		[[ "$output" == PREFLIGHT-FAIL*identity*placeholder* ]]
	done
	run --separate-stderr env -C "$d" jj config list --repo
	[ -z "$output" ]
}

@test "preflight: an empty user.email fails closed, exit 1" {
	local d
	d="$(fx_colocated r)"
	set_identity 'Bats Tester' ''
	run env -C "$d" "$SCRIPTS/preflight.sh"
	[ "$status" -eq 1 ]
	[[ "$output" == PREFLIGHT-FAIL*identity* ]]
}

@test "preflight: unresolvable protected bookmark fails closed, exit 1" {
	local d="$BATS_TEST_TMPDIR/r"
	git init -q -b develop "$d"
	env -C "$d" git commit -q --allow-empty -m init
	env -C "$d" jj git init --colocate > /dev/null 2>&1
	run env -C "$d" "$SCRIPTS/preflight.sh"
	[ "$status" -eq 1 ]
	[[ "$output" == PREFLIGHT-FAIL*protected* ]]
}

@test "preflight: PREFLIGHT_PROTECTED_BOOKMARKS overrides resolution" {
	local d="$BATS_TEST_TMPDIR/r"
	git init -q -b develop "$d"
	env -C "$d" git commit -q --allow-empty -m init
	env -C "$d" jj git init --colocate > /dev/null 2>&1
	run env -C "$d" PREFLIGHT_PROTECTED_BOOKMARKS=develop "$SCRIPTS/preflight.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == *"protected=[develop]"* ]]
}

@test "preflight: a bookmark name that could escape the revset fails closed" {
	local d
	d="$(fx_colocated r)"
	run env -C "$d" PREFLIGHT_PROTECTED_BOOKMARKS='main x") | oops(' "$SCRIPTS/preflight.sh"
	[ "$status" -eq 1 ]
	[[ "$output" == PREFLIGHT-FAIL*bookmark*name* ]]
	run --separate-stderr env -C "$d" jj config list --repo
	[ -z "$output" ]
}

@test "preflight: an immutable() that does not parse fails closed" {
	local d
	d="$(fx_colocated r)"
	printf '\n[revset-aliases]\n"builtin_immutable_heads()" = "nope_function()"\n' >> "$JJ_CONFIG"
	run env -C "$d" PREFLIGHT_PROTECTED_BOOKMARKS=main "$SCRIPTS/preflight.sh"
	[ "$status" -eq 1 ]
	[[ "$output" == PREFLIGHT-FAIL*immutable* ]]
}

@test "preflight: standard then oplog removes snapshot.auto-track" {
	local d
	d="$(fx_colocated r)"
	env -C "$d" "$SCRIPTS/preflight.sh" --level standard > /dev/null
	run env -C "$d" "$SCRIPTS/preflight.sh" --level oplog
	[ "$status" -eq 0 ]
	run env -C "$d" jj config list --repo
	[ "${#lines[@]}" -eq 3 ]
	[[ "$output" != *snapshot.auto-track* ]]
}

@test "preflight: level full writes exactly the three safety keys" {
	local d
	d="$(fx_colocated r)"
	env -C "$d" "$SCRIPTS/preflight.sh" --level full > /dev/null
	run env -C "$d" jj config list --repo
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 3 ]
	[[ "$output" == *'revset-aliases."immutable_heads()"'* ]]
	[[ "$output" == *'ui.editor = ":true"'* ]]
	[[ "$output" == *'ui.diff-editor = ":true"'* ]]
}

@test "preflight: level oplog writes exactly the three safety keys" {
	local d
	d="$(fx_colocated r)"
	env -C "$d" "$SCRIPTS/preflight.sh" --level oplog > /dev/null
	run env -C "$d" jj config list --repo
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 3 ]
	[[ "$output" != *snapshot.auto-track* ]]
}

@test "preflight: level standard adds snapshot.auto-track = none" {
	local d
	d="$(fx_colocated r)"
	env -C "$d" "$SCRIPTS/preflight.sh" --level standard > /dev/null
	run env -C "$d" jj config list --repo
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 4 ]
	[[ "$output" == *'snapshot.auto-track = "none"'* ]]
}

@test "preflight: standard then full removes snapshot.auto-track" {
	local d
	d="$(fx_colocated r)"
	env -C "$d" "$SCRIPTS/preflight.sh" --level standard > /dev/null
	run env -C "$d" "$SCRIPTS/preflight.sh" --level full
	[ "$status" -eq 0 ]
	run env -C "$d" jj config list --repo
	[ "${#lines[@]}" -eq 3 ]
	[[ "$output" != *snapshot.auto-track* ]]
}

@test "preflight: protected bookmark is inside immutable() afterwards" {
	local d
	d="$(fx_colocated r)"
	env -C "$d" "$SCRIPTS/preflight.sh" > /dev/null
	run env -C "$d" jj log -r 'bookmarks(exact:"main") & ~immutable()' --no-graph -T 'commit_id ++ "\n"'
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "preflight: second run is idempotent" {
	local d first second
	d="$(fx_colocated r)"
	first="$(env -C "$d" "$SCRIPTS/preflight.sh")"
	second="$(env -C "$d" "$SCRIPTS/preflight.sh")"
	[ "$first" = "$second" ]
	run env -C "$d" jj config list --repo
	[ "${#lines[@]}" -eq 3 ]
}

@test "preflight: a glob in PREFLIGHT_PROTECTED_BOOKMARKS is a literal name and fails closed" {
	local d
	d="$(fx_colocated r)"
	run env -C "$d" PREFLIGHT_PROTECTED_BOOKMARKS='*' "$SCRIPTS/preflight.sh"
	[ "$status" -eq 1 ]
	[[ "$output" == PREFLIGHT-FAIL*illegal* ]]
	run env -C "$d" jj config list --repo
	[[ "$output" != *immutable_heads* ]]
}
