#!/usr/bin/env bats
# End-to-end scenarios E1-E7 from the revision plan, plus the receipt
# contract assertions.  Each test drives the shipped scripts over a
# scratch repo and a local bare remote, exactly as a session would: no
# script internals are inspected, only receipts, exit codes, and the
# state the repo and the remote end up in.

load test_helper

# wire_origin DIR NAME -- give DIR a local bare remote named origin with
# main pushed and origin/HEAD set, so the protected bookmark resolves
# through the remote HEAD the way it does in a real checkout.  Prints
# the bare repository path.
wire_origin() {
	local remote
	remote="$(fx_bare_remote "$2")"
	env -C "$1" git remote add origin "$remote"
	env -C "$1" git push -q -u origin main
	env -C "$1" git remote set-head origin main
	printf '%s' "$remote"
}

# fx_onboarded NAME LEVEL -- a git repo with one tracked file and a
# wired origin, converted at LEVEL.  Prints the repository directory.
fx_onboarded() {
	local d
	d="$(fx_git_only_file "$1")"
	wire_origin "$d" "$1-remote" > /dev/null
	env -C "$d" sh "$SCRIPTS/onboard.sh" apply --level "$2" > /dev/null
	printf '%s' "$d"
}

# hook EVENT CWD WORKTREE_PATH -- feed workspace_hook.sh one hook JSON
# object, keeping its stdout (the directory) apart from its receipts.
hook() {
	run --separate-stderr sh "$SCRIPTS/workspace_hook.sh" <<- EOF
		{"session_id":"s1","hook_event_name":"$1","cwd":"$2","worktree_path":"$3"}
	EOF
}

# assert_schema FILE SCHEMA -- the receipt exists, is non-empty, and
# carries the schema its contract names.
assert_schema() {
	[ -s "$1" ]
	run jq -e --arg s "$2" '.schema == $s' "$1"
	[ "$status" -eq 0 ]
}

@test "E1: git-only converts at full, describes, gates, and promotes to the remote" {
	local d remote state
	d="$(fx_git_only_file e1)"
	remote="$(wire_origin "$d" e1-remote)"

	run --separate-stderr env -C "$d" sh "$SCRIPTS/onboard.sh" apply --level full
	[ "$status" -eq 0 ]
	[[ "$output" == *'ONBOARD-OK level=full shape=colocated'* ]]
	[[ "$output" == *'protected=[main]'* ]]

	printf 'two\n' >> "$d/a.txt"
	env -C "$d" jj describe --stdin > /dev/null 2>&1 <<- 'EOF'
		feat(e1): describe from a here-doc

		Body line.
	EOF

	run env -C "$d" "$SCRIPTS/gate.sh" --cheap --range '@' -- true
	[ "$status" -eq 0 ]
	[[ "$output" == GATE-PASS* ]]

	# promote.sh merges `jj bookmark set` chatter into its own stdout,
	# so the receipt is the last line, not the only one.
	run env -C "$d" "$SCRIPTS/promote.sh" feat/e1 @
	[ "$status" -eq 0 ]
	[ "${lines[-1]}" = 'PROMOTE-OK bookmark=feat/e1 rev=@ pushed' ]
	run git -C "$remote" show-ref --verify --quiet refs/heads/feat/e1
	[ "$status" -eq 0 ]

	run --separate-stderr env -C "$d" "$SCRIPTS/emit_handoff.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == 'HANDOFF-OK ready=true receipt='* ]]

	# Receipt contract: schema, and the gated range as gate.sh saw it.
	state="$d/.local/state/agents/vcs"
	assert_schema "$state/gate.json" 'vcs-gate/1'
	run jq -r '.range' "$state/gate.json"
	[ "$output" = '@' ]
	assert_schema "$state/handoff.json" 'vcs-handoff/2'
	run jq -e '.ready == true and .fails == [] and .level == "full"' "$state/handoff.json"
	[ "$status" -eq 0 ]
}

@test "E2: a hook workspace pushes a bookmark the primary still sees after removal" {
	local d remote ws
	d="$(fx_git_only_file e2)"
	remote="$(wire_origin "$d" e2-remote)"
	env -C "$d" sh "$SCRIPTS/onboard.sh" apply --level full > /dev/null

	hook WorktreeCreate "$d" '/proposed/feat-e2'
	[ "$status" -eq 0 ]
	ws="$output"

	printf 'workspace change\n' > "$ws/w.txt"
	run jj -R "$ws" describe -m 'feat(e2): from a workspace'
	[ "$status" -eq 0 ]
	run jj -R "$ws" bookmark set feat/e2 -r @
	[ "$status" -eq 0 ]
	run jj -R "$ws" git push --bookmark feat/e2
	[ "$status" -eq 0 ]

	hook WorktreeRemove "$d" "$ws"
	[ "$status" -eq 0 ]
	[ ! -e "$ws" ]

	run git -C "$remote" show-ref --verify --quiet refs/heads/feat/e2
	[ "$status" -eq 0 ]
	run jj -R "$d" log -r 'bookmarks()' --no-graph \
		-T 'bookmarks ++ " " ++ description.first_line() ++ "\n"'
	[[ "$output" == *'feat/e2 feat(e2): from a workspace'* ]]
}

@test "E3: a nested git worktree hard-stops every script with exit 3" {
	local w
	w="$(fx_shadowed e3)"

	run env -C "$w" "$SCRIPTS/detect_shape.sh"
	[ "$status" -eq 3 ]
	[ "$output" = 'worktree-shadowed' ]

	run env -C "$w" "$SCRIPTS/preflight.sh"
	[ "$status" -eq 3 ]

	run env -C "$w" "$SCRIPTS/gate.sh" --cheap --range '@' -- true
	[ "$status" -eq 3 ]

	run env -C "$w" "$SCRIPTS/promote.sh" feat/e3
	[ "$status" -eq 3 ]

	run env -C "$w" "$SCRIPTS/absorb_safe.sh"
	[ "$status" -eq 3 ]

	run env -C "$w" "$SCRIPTS/emit_handoff.sh"
	[ "$status" -eq 3 ]

	run --separate-stderr env -C "$w" sh "$SCRIPTS/onboard.sh" apply --level full
	[ "$status" -eq 3 ]
	[ "$output" = 'ONBOARD-REFUSE reason=worktree-shadowed' ]

	[ ! -e "$w/.jj" ]
}

@test "E4: with jj off the PATH onboarding skips and the plain-git read still works" {
	local d nobin
	d="$(fx_git_only_file e4)"
	nobin="$(path_without jj)"
	printf 'two\n' >> "$d/a.txt"

	run --separate-stderr env -C "$d" PATH="$nobin" sh "$SCRIPTS/onboard.sh" apply --level full
	[ "$status" -eq 0 ]
	[ "$output" = 'ONBOARD-SKIP reason=jj-absent' ]
	[ ! -e "$d/.jj" ]

	run env -C "$d" PATH="$nobin" "$SCRIPTS/git_diff_safe.sh" diff --name-only
	[ "$status" -eq 0 ]
	[ "$output" = 'a.txt' ]
}

@test "E5: removing a dirty workspace leaves its content recoverable from the primary" {
	local d ws
	d="$(fx_onboarded e5 full)"

	hook WorktreeCreate "$d" '/proposed/feat-e5'
	[ "$status" -eq 0 ]
	ws="$output"
	awk 'BEGIN { print "MARKER-E5"; for (i = 0; i < 64; i++) print "0123456789abcdef" }' \
		> "$ws/big.txt"
	[ "$(wc -c < "$ws/big.txt")" -ge 1024 ]

	hook WorktreeRemove "$d" "$ws"
	[ "$status" -eq 0 ]
	[ ! -e "$ws" ]

	run jj -R "$d" op log --no-graph -T 'description ++ "\n"'
	[[ "$output" == *'snapshot working copy'* ]]
	run jj -R "$d" log -r 'all()' -p --no-graph
	[[ "$output" == *'MARKER-E5'* ]]
}

@test "E6: a fresh clone carries none of the safety keys; the handoff re-runs preflight" {
	local d clone
	d="$(fx_onboarded e6 full)"
	clone="$BATS_TEST_TMPDIR/e6-clone"
	env -C "$BATS_TEST_TMPDIR" jj git clone --colocate "$d" "$clone" > /dev/null 2>&1

	# --repo config is keyed by store id, so preflight's keys do not
	# survive the clone.  `jj git clone` writes its own trunk() alias,
	# so the scope is not empty -- only the safety net is missing.
	run jj -R "$clone" config list --repo
	[ "$status" -eq 0 ]
	[[ "$output" != *'immutable_heads'* ]]
	[[ "$output" != *'ui.editor'* ]]
	[[ "$output" != *'ui.diff-editor'* ]]

	run --separate-stderr env -C "$clone" "$SCRIPTS/emit_handoff.sh"
	[ "$status" -eq 1 ]
	[[ "$output" == 'HANDOFF-NOT-READY fails=[gate] receipt='* ]]
	run jq -e '.preflight.ok == true' "$clone/.local/state/agents/vcs/handoff.json"
	[ "$status" -eq 0 ]
	run jj -R "$clone" config list --repo
	[[ "$output" == *'immutable_heads'* ]]
}

@test "E6: a clone whose protected bookmark cannot resolve fails preflight closed" {
	local e clone
	e="$BATS_TEST_TMPDIR/e6b"
	git init -q -b devel "$e"
	printf 'one\n' > "$e/a.txt"
	env -C "$e" git add a.txt
	env -C "$e" git commit -q -m init
	env -C "$e" PREFLIGHT_PROTECTED_BOOKMARKS=devel \
		sh "$SCRIPTS/onboard.sh" apply --level full > /dev/null
	clone="$BATS_TEST_TMPDIR/e6b-clone"
	env -C "$BATS_TEST_TMPDIR" jj git clone --colocate "$e" "$clone" > /dev/null 2>&1

	run --separate-stderr env -C "$clone" "$SCRIPTS/emit_handoff.sh"
	[ "$status" -eq 1 ]
	[[ "$output" == 'HANDOFF-NOT-READY fails=[preflight gate] receipt='* ]]
	run jq -e '.preflight.ok == false' "$clone/.local/state/agents/vcs/handoff.json"
	[ "$status" -eq 0 ]
}

@test "E7: level oplog serializes with git, rolls back with jj, and blocks the pipeline" {
	local d
	d="$(fx_git_only_file e7)"

	run --separate-stderr env -C "$d" sh "$SCRIPTS/onboard.sh" apply --level oplog
	[ "$status" -eq 0 ]
	[[ "$output" == *'ONBOARD-OK level=oplog shape=colocated'* ]]

	printf 'two\n' >> "$d/a.txt"
	printf 'fix(e7): serialize with plain git\n\nBody line.\n' > "$BATS_TEST_TMPDIR/e7-msg"
	env -C "$d" git add a.txt
	env -C "$d" git commit -q -F "$BATS_TEST_TMPDIR/e7-msg"

	run jj -R "$d" log --no-graph -r 'all() ~ root()' \
		-T 'description.first_line() ++ "\n"'
	[ "$status" -eq 0 ]
	[[ "$output" == *'fix(e7): serialize with plain git'* ]]

	printf 'GARBAGE\n' > "$d/a.txt"
	jj -R "$d" status > /dev/null 2>&1
	run jj -R "$d" undo
	[ "$status" -eq 0 ]
	run cat "$d/a.txt"
	[ "${#lines[@]}" -eq 2 ]
	[ "${lines[0]}" = 'one' ]
	[ "${lines[1]}" = 'two' ]

	run env -C "$d" "$SCRIPTS/gate.sh" --cheap --range '@' -- true
	[ "$status" -eq 6 ]
	[ "$output" = 'GATE-FAIL LEVEL-BLOCKED level=oplog' ]
	run env -C "$d" "$SCRIPTS/promote.sh" feat/e7
	[ "$status" -eq 6 ]
	[ "$output" = 'PROMOTE-FAIL LEVEL-BLOCKED level=oplog' ]
	run env -C "$d" "$SCRIPTS/absorb_safe.sh"
	[ "$status" -eq 6 ]
	[ "$output" = 'ABSORB-BLOCKED LEVEL-BLOCKED level=oplog' ]

	run env -C "$d" git status --porcelain
	[ -z "$output" ]
}

@test "contract: the probe writes a vcs-compat-probe/2 receipt" {
	local receipt="$HOME/.agents/.local/state/vcs-workflow/compat-probe.json"

	run --separate-stderr env PATH="$(path_without gh)" "$SCRIPTS/compat_probe.sh"
	[ "$status" -eq 0 ]

	assert_schema "$receipt" 'vcs-compat-probe/2'
	run jq -e '.verdict == "green" and .claims.failed == []' "$receipt"
	[ "$status" -eq 0 ]
}
