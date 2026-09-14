#!/usr/bin/env bats
# scripts/emit_handoff.sh: the vcs-handoff/2 receipt, the shapes it
# refuses, where the receipt lands, and the atomic write.

load test_helper

@test "emit_handoff: bad --range invocation exits 2" {
	local d
	d="$(fx_colocated r)"
	run env -C "$d" "$SCRIPTS/emit_handoff.sh" --range
	[ "$status" -eq 2 ]
}

@test "emit_handoff: worktree-shadowed exits 3 without writing a receipt" {
	local w
	w="$(fx_shadowed r)"
	run --separate-stderr env -C "$w" "$SCRIPTS/emit_handoff.sh"
	[ "$status" -eq 3 ]
	[ "$output" = "HANDOFF-FAIL shape=worktree-shadowed" ]
	[ ! -e "$BATS_TEST_TMPDIR/r/.local/state/agents/vcs/handoff.json" ]
}

@test "emit_handoff: colocated repo with no gate receipt is NOT-READY with fails=[gate]" {
	local d
	d="$(fx_colocated r)"
	run --separate-stderr env -C "$d" "$SCRIPTS/emit_handoff.sh"
	[ "$status" -eq 1 ]
	[[ "$output" == "HANDOFF-NOT-READY fails=[gate] receipt="* ]]
	[ -s "$d/.local/state/agents/vcs/handoff.json" ]
	run jq -e '.schema == "vcs-handoff/2" and .ready == false and (.fails == ["gate"]) and .shape == "colocated"' "$d/.local/state/agents/vcs/handoff.json"
	[ "$status" -eq 0 ]
}

@test "emit_handoff: receipt carries the stack with per-revision files" {
	local d
	d="$(fx_colocated r)"
	printf 'two\n' > "$d/b.txt"
	env -C "$d" jj describe -m 'add b' > /dev/null 2>&1
	env -C "$d" jj new > /dev/null 2>&1
	env -C "$d" "$SCRIPTS/emit_handoff.sh" > /dev/null 2>&1 || true
	run jq -r '.stack[] | select(.first_line == "add b") | .files[0]' "$d/.local/state/agents/vcs/handoff.json"
	[ "$status" -eq 0 ]
	[ "$output" = "b.txt" ]
}

@test "emit_handoff: git-only exits 5 without writing a receipt" {
	local d
	d="$(fx_git_only r)"
	run --separate-stderr env -C "$d" "$SCRIPTS/emit_handoff.sh"
	[ "$status" -eq 5 ]
	[ "$output" = "HANDOFF-FAIL shape=git-only" ]
	[ ! -e "$d/.local/state/agents/vcs/handoff.json" ]
}

@test "emit_handoff: no-VCS directory exits 5 without writing a receipt" {
	local d="$BATS_TEST_TMPDIR/plain"
	mkdir -p "$d"
	run --separate-stderr env -C "$d" "$SCRIPTS/emit_handoff.sh"
	[ "$status" -eq 5 ]
	[ "$output" = "HANDOFF-FAIL shape=none" ]
	[ ! -e "$d/.local/state/agents/vcs/handoff.json" ]
}

@test "emit_handoff: vcs-handoff/2 carries level, workspace, and repo blocks" {
	local d f
	d="$(fx_colocated r)"
	env -C "$d" "$SCRIPTS/emit_handoff.sh" > /dev/null 2>&1 || true
	f="$d/.local/state/agents/vcs/handoff.json"
	[ -s "$f" ]
	run jq -e '.schema == "vcs-handoff/2"
		and .level == "full"
		and .workspace.is_secondary == false
		and .workspace.name == "default"
		and .repo.origin_url == null
		and (.toolchain | keys == ["probe_at", "probe_verdict"])
		and (.message_hints | keys == ["scope"])
		and (.preflight | has("store_id"))
		and (.base.fetched.ran == false)' "$f"
	[ "$status" -eq 0 ]
	run jq -r '.workspace.primary_root + " " + .repo.root' "$f"
	[ "$output" = "$(readlink -f "$d") $(readlink -f "$d")" ]
}

@test "emit_handoff: level comes from the repo's vcs-workflow.level key" {
	local d
	d="$(fx_colocated r)"
	git -C "$d" config vcs-workflow.level standard
	env -C "$d" "$SCRIPTS/emit_handoff.sh" > /dev/null 2>&1 || true
	run jq -r '.level' "$d/.local/state/agents/vcs/handoff.json"
	[ "$output" = "standard" ]
}

@test "emit_handoff: origin url is recorded when a remote exists" {
	local d remote
	d="$(fx_colocated r)"
	remote="$(fx_bare_remote origin)"
	git -C "$d" remote add origin "$remote"
	env -C "$d" "$SCRIPTS/emit_handoff.sh" > /dev/null 2>&1 || true
	run jq -r '.repo.origin_url' "$d/.local/state/agents/vcs/handoff.json"
	[ "$output" = "$remote" ]
}

@test "emit_handoff: a secondary workspace writes the receipt under the primary root" {
	local w primary f
	w="$(fx_jj_workspace r)"
	primary="$BATS_TEST_TMPDIR/r"
	f="$primary/.local/state/agents/vcs/handoff.json"
	run --separate-stderr env -C "$w" "$SCRIPTS/emit_handoff.sh"
	[ "$status" -eq 1 ]
	[ ! -e "$w/.local/state/agents/vcs/handoff.json" ]
	[ -s "$f" ]
	run jq -e '.workspace.is_secondary == true and .workspace.name == "r-ws"' "$f"
	[ "$status" -eq 0 ]
	run jq -r '.workspace.primary_root' "$f"
	[ "$output" = "$(readlink -f "$primary")" ]
}

@test "emit_handoff: level oplog is LEVEL-BLOCKED and leaves the tree untouched" {
	local d
	d="$(fx_colocated r)"
	git -C "$d" config vcs-workflow.level oplog
	run --separate-stderr env -C "$d" "$SCRIPTS/emit_handoff.sh"
	[ "$status" -eq 6 ]
	[ "$output" = "HANDOFF-FAIL LEVEL-BLOCKED level=oplog" ]
	[ ! -e "$d/.local" ]
	run env -C "$d" git status --porcelain
	[ "$output" = "" ]
}

@test "emit_handoff: a secondary workspace sharing its commit still names itself" {
	local w primary shared
	w="$(fx_jj_workspace r)"
	primary="$BATS_TEST_TMPDIR/r"
	# Both workspaces on one commit: `working_copies` then lists every
	# name, "default" first, so the name cannot come from that field.
	shared="$(env -C "$primary" jj log -r @ --no-graph -T 'change_id.short()')"
	env -C "$w" jj edit "$shared" > /dev/null 2>&1
	env -C "$w" "$SCRIPTS/emit_handoff.sh" > /dev/null 2>&1 || true
	run jq -r '.workspace.name' "$primary/.local/state/agents/vcs/handoff.json"
	[ "$output" = "r-ws" ]
}

@test "emit_handoff: a relative .jj/repo pointer resolves to the primary root" {
	local w primary
	w="$(fx_jj_workspace r)"
	primary="$BATS_TEST_TMPDIR/r"
	# jj writes the pointer relative to the workspace's own .jj/, so the
	# resolution has to join it there and nowhere else.
	[[ "$(cat "$w/.jj/repo")" != /* ]]
	env -C "$w" "$SCRIPTS/emit_handoff.sh" > /dev/null 2>&1 || true
	[ ! -e "$w/.local" ]
	run jq -r '.workspace.primary_root' "$primary/.local/state/agents/vcs/handoff.json"
	[ "$output" = "$(readlink -f "$primary")" ]
}

@test "emit_handoff: a jq failure leaves the previous receipt byte-identical" {
	local d f
	d="$(fx_colocated r)"
	env -C "$d" "$SCRIPTS/emit_handoff.sh" > /dev/null 2>&1 || true
	f="$d/.local/state/agents/vcs/handoff.json"
	[ -s "$f" ]
	cp "$f" "$BATS_TEST_TMPDIR/before.json"
	run --separate-stderr env -C "$d" PATH="$(path_without jq)" "$SCRIPTS/emit_handoff.sh"
	[ "$status" -eq 1 ]
	[ "$output" = "HANDOFF-FAIL jq assembly failed" ]
	cmp "$BATS_TEST_TMPDIR/before.json" "$f"
	[ ! -e "$f.tmp" ]
}
