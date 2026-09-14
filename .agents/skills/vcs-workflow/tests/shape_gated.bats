#!/usr/bin/env bats
# Characterization of the shape gates in gate.sh, promote.sh, and
# absorb_safe.sh, plus gate.sh's pass, conflict, and usage paths.

load test_helper

@test "gate: usage without -- exits 2" {
	local d
	d="$(fx_colocated r)"
	run env -C "$d" "$SCRIPTS/gate.sh"
	[ "$status" -eq 2 ]
}

@test "gate: git-only exits 5" {
	local d
	d="$(fx_git_only r)"
	run env -C "$d" "$SCRIPTS/gate.sh" -- true
	[ "$status" -eq 5 ]
	[[ "$output" == "GATE-FAIL shape=git-only"* ]]
}

@test "gate: worktree-shadowed exits 3" {
	local w
	w="$(fx_shadowed r)"
	run env -C "$w" "$SCRIPTS/gate.sh" -- true
	[ "$status" -eq 3 ]
}

@test "gate: passing command writes a vcs-gate/1 receipt with verdict pass" {
	local d
	d="$(fx_colocated r)"
	run env -C "$d" "$SCRIPTS/gate.sh" --cheap --range '@' -- true
	[ "$status" -eq 0 ]
	[[ "$output" == GATE-PASS* ]]
	run jq -e '.schema == "vcs-gate/1" and .verdict == "pass" and .range == "@"' "$d/.local/state/agents/vcs/gate.json"
	[ "$status" -eq 0 ]
}

@test "gate: failing command exits 1 with verdict fail" {
	local d
	d="$(fx_colocated r)"
	run --separate-stderr env -C "$d" "$SCRIPTS/gate.sh" --cheap --range '@' -- false
	[ "$status" -eq 1 ]
	[[ "$output" == GATE-FAIL* ]]
	run jq -r '.verdict' "$d/.local/state/agents/vcs/gate.json"
	[ "$output" = "fail" ]
}

@test "gate: conflicted range is CONFLICT-BLOCKED, exit 4" {
	local d
	d="$(fx_colocated r)"
	env -C "$d" jj new main -m x > /dev/null 2>&1
	printf 'x\n' > "$d/a.txt"
	env -C "$d" jj new main -m y > /dev/null 2>&1
	printf 'y\n' > "$d/a.txt"
	env -C "$d" jj rebase -r 'description(exact:"y\n")' -d 'description(exact:"x\n")' > /dev/null 2>&1
	run env -C "$d" "$SCRIPTS/gate.sh" --cheap --range 'all() ~ root()' -- true
	[ "$status" -eq 4 ]
	[[ "$output" == CONFLICT-BLOCKED* ]]
}

@test "promote: usage without a bookmark exits 2" {
	local d
	d="$(fx_colocated r)"
	run env -C "$d" "$SCRIPTS/promote.sh"
	[ "$status" -eq 2 ]
}

@test "promote: git-only exits 5" {
	local d
	d="$(fx_git_only r)"
	run env -C "$d" "$SCRIPTS/promote.sh" feat/x
	[ "$status" -eq 5 ]
}

@test "promote: refuses without a gate receipt, exit 1" {
	local d
	d="$(fx_colocated r)"
	run env -C "$d" "$SCRIPTS/promote.sh" feat/x
	[ "$status" -eq 1 ]
	[[ "$output" == "PROMOTE-FAIL no gate receipt"* ]]
}

@test "absorb_safe: git-only exits 5" {
	local d
	d="$(fx_git_only r)"
	run env -C "$d" "$SCRIPTS/absorb_safe.sh"
	[ "$status" -eq 5 ]
	[[ "$output" == "ABSORB-BLOCKED shape=git-only"* ]]
}

@test "absorb_safe: worktree-shadowed exits 3" {
	local w
	w="$(fx_shadowed r)"
	run env -C "$w" "$SCRIPTS/absorb_safe.sh"
	[ "$status" -eq 3 ]
}

# Level gate: at oplog the gate, promote, and absorb steps are not part
# of the recorded level, so each refuses with its own receipt prefix.

@test "gate: level oplog is LEVEL-BLOCKED, exit 6" {
	local d
	d="$(fx_colocated r)"
	env -C "$d" git config --local vcs-workflow.level oplog
	run env -C "$d" "$SCRIPTS/gate.sh" --cheap --range '@' -- true
	[ "$status" -eq 6 ]
	[ "$output" = "GATE-FAIL LEVEL-BLOCKED level=oplog" ]
}

@test "promote: level oplog is LEVEL-BLOCKED, exit 6" {
	local d
	d="$(fx_colocated r)"
	env -C "$d" git config --local vcs-workflow.level oplog
	run env -C "$d" "$SCRIPTS/promote.sh" feat/x
	[ "$status" -eq 6 ]
	[ "$output" = "PROMOTE-FAIL LEVEL-BLOCKED level=oplog" ]
}

@test "absorb_safe: level oplog is LEVEL-BLOCKED, exit 6" {
	local d
	d="$(fx_colocated r)"
	env -C "$d" git config --local vcs-workflow.level oplog
	run env -C "$d" "$SCRIPTS/absorb_safe.sh"
	[ "$status" -eq 6 ]
	[ "$output" = "ABSORB-BLOCKED LEVEL-BLOCKED level=oplog" ]
}

@test "gate: level standard still gates and passes" {
	local d
	d="$(fx_colocated r)"
	env -C "$d" git config --local vcs-workflow.level standard
	run env -C "$d" "$SCRIPTS/gate.sh" --cheap --range '@' -- true
	[ "$status" -eq 0 ]
	[[ "$output" == GATE-PASS* ]]
}

@test "promote: level standard still refuses without a gate receipt" {
	local d
	d="$(fx_colocated r)"
	env -C "$d" git config --local vcs-workflow.level standard
	run env -C "$d" "$SCRIPTS/promote.sh" feat/x
	[ "$status" -eq 1 ]
	[[ "$output" == "PROMOTE-FAIL no gate receipt"* ]]
}

@test "absorb_safe: level standard is not level-blocked" {
	local d
	d="$(fx_colocated r)"
	env -C "$d" git config --local vcs-workflow.level standard
	run --separate-stderr env -C "$d" "$SCRIPTS/absorb_safe.sh"
	[ "$status" -ne 6 ]
	[[ "$output" != *LEVEL-BLOCKED* ]]
}

# A secondary workspace has no `.git` of its own, so a level read taken
# where the command runs falls through to global scope and answers
# `full` for a repo recorded oplog.  Every level read anchors on the
# primary root instead.

@test "gate: a workspace of an oplog primary is LEVEL-BLOCKED, exit 6" {
	local w
	w="$(fx_jj_workspace r)"
	git -C "$BATS_TEST_TMPDIR/r" config --local vcs-workflow.level oplog
	run env -C "$w" "$SCRIPTS/gate.sh" --cheap --range '@' -- true
	[ "$status" -eq 6 ]
	[ "$output" = "GATE-FAIL LEVEL-BLOCKED level=oplog" ]
}

@test "promote: a workspace of an oplog primary is LEVEL-BLOCKED, exit 6" {
	local w
	w="$(fx_jj_workspace r)"
	git -C "$BATS_TEST_TMPDIR/r" config --local vcs-workflow.level oplog
	run env -C "$w" "$SCRIPTS/promote.sh" feat/x
	[ "$status" -eq 6 ]
	[ "$output" = "PROMOTE-FAIL LEVEL-BLOCKED level=oplog" ]
}

@test "absorb_safe: a workspace of an oplog primary is LEVEL-BLOCKED, exit 6" {
	local w
	w="$(fx_jj_workspace r)"
	git -C "$BATS_TEST_TMPDIR/r" config --local vcs-workflow.level oplog
	run env -C "$w" "$SCRIPTS/absorb_safe.sh"
	[ "$status" -eq 6 ]
	[ "$output" = "ABSORB-BLOCKED LEVEL-BLOCKED level=oplog" ]
}

# The gate receipt is the primary's: promote.sh run from a workspace
# reads the receipt gate.sh wrote from that same workspace, or the two
# halves of one pipeline disagree about where state lives.

@test "gate: a workspace writes gate.json under the primary root" {
	local w primary
	w="$(fx_jj_workspace r)"
	primary="$BATS_TEST_TMPDIR/r"
	run env -C "$w" "$SCRIPTS/gate.sh" --cheap --range '@' -- true
	[ "$status" -eq 0 ]
	[[ "$output" == GATE-PASS* ]]
	[ ! -e "$w/.local/state/agents/vcs/gate.json" ]
	run jq -e '.verdict == "pass"' "$primary/.local/state/agents/vcs/gate.json"
	[ "$status" -eq 0 ]
}

@test "promote: a workspace finds the gate receipt under the primary root" {
	local w primary
	w="$(fx_jj_workspace r)"
	primary="$BATS_TEST_TMPDIR/r"
	env -C "$w" "$SCRIPTS/gate.sh" --cheap --range '@' -- true > /dev/null
	[ -s "$primary/.local/state/agents/vcs/gate.json" ]
	run --separate-stderr env -C "$w" "$SCRIPTS/promote.sh" feat/x
	[[ "$output" != *'no gate receipt'* ]]
}
