#!/usr/bin/env bats
# Failure contract of ~/.local/bin/harness-settings-apply: a step that
# fails must fail the run, print no success line, and leave the target
# file as it was.

setup() {
	SCRIPT="${HARNESS_SETTINGS_APPLY:-${BATS_TEST_DIRNAME}/../../../.local/bin/harness-settings-apply}"
	export HOME="${BATS_TEST_TMPDIR}/home"
	TARGET="${HOME}/.claude/settings.json"
	mkdir -p "${HOME}/.config/agents/claude" "${HOME}/.claude"
	printf '{"autoCompactWindow": 400000}\n' \
		> "${HOME}/.config/agents/claude/portable.json"
	printf '{"model": "x"}\n' > "$TARGET"
}

@test "apply: merges the portable keys and keeps the others" {
	run "$SCRIPT" claude
	[ "$status" -eq 0 ]
	[[ "$output" == *'claude: applied'* ]]
	[ "$(jq -r .autoCompactWindow "$TARGET")" = '400000' ]
	[ "$(jq -r .model "$TARGET")" = 'x' ]
}

@test "apply: a failed move fails the run and leaves the target alone" {
	mkdir -p "${BATS_TEST_TMPDIR}/bin"
	printf '#!/bin/sh\nexit 1\n' > "${BATS_TEST_TMPDIR}/bin/mv"
	chmod +x "${BATS_TEST_TMPDIR}/bin/mv"
	PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" run "$SCRIPT" claude
	[ "$status" -ne 0 ]
	[[ "$output" != *'applied'* ]]
	[[ "$output" == *'write failed'* ]]
	[ "$(cat "$TARGET")" = '{"model": "x"}' ]
	[ "$(find "${HOME}/.claude" -type f | wc -l)" -eq 1 ]
}

@test "apply: a target that is not JSON fails the run" {
	printf 'not json\n' > "$TARGET"
	run "$SCRIPT" claude
	[ "$status" -ne 0 ]
	[[ "$output" != *'in sync'* ]]
	[[ "$output" != *'applied'* ]]
	[ "$(cat "$TARGET")" = 'not json' ]
}

@test "apply: an unknown tool fails the run" {
	run "$SCRIPT" nosuchtool
	[ "$status" -ne 0 ]
	[[ "$output" == *'unknown tool'* ]]
}

@test "check: drift exits 1 and writes nothing" {
	run "$SCRIPT" --check claude
	[ "$status" -eq 1 ]
	[[ "$output" == *'claude: drift'* ]]
	[ "$(cat "$TARGET")" = '{"model": "x"}' ]
}

@test "check: a target in sync exits 0" {
	"$SCRIPT" claude
	run "$SCRIPT" --check claude
	[ "$status" -eq 0 ]
	[[ "$output" == *'claude: in sync'* ]]
}
