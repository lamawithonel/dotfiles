#!/usr/bin/env bats
# Host-local overlay contract of harness-settings-apply: an untracked
# ~/.config/agents/<tool>/portable.local.json adds its array entries to
# the tracked portable.json before the RFC 7386 merge, so an apply never
# deletes a host-local entry.  Every test runs on temporary files under a
# fake HOME; the live settings are only ever read (last test).

# Staged layout: S/tests next to S/home.  Installed layout: the repository
# test directory next to ~/.local/bin and ~/.config/agents.
S_ROOT="${BATS_TEST_DIRNAME}/.."

setup() {
	REAL_HOME="$HOME"
	if [ -x "${S_ROOT}/home/.local/bin/harness-settings-apply" ]; then
		DEFAULT_SCRIPT="${S_ROOT}/home/.local/bin/harness-settings-apply"
		DEFAULT_OVERLAY="${S_ROOT}/home/.config/agents/claude/portable.local.json"
	else
		DEFAULT_SCRIPT="${REAL_HOME}/.local/bin/harness-settings-apply"
		DEFAULT_OVERLAY="${REAL_HOME}/.config/agents/claude/portable.local.json"
	fi
	SCRIPT="${HARNESS_SETTINGS_APPLY:-${DEFAULT_SCRIPT}}"
	export HOME="${BATS_TEST_TMPDIR}/home"
	CFG="${HOME}/.config/agents/claude"
	TARGET="${HOME}/.claude/settings.json"
	SRT="${HOME}/.srt-settings.json"
	mkdir -p "$CFG" "${HOME}/.claude"
	jq -n '{
		sandbox: {
			failIfUnavailable: true,
			filesystem: {denyRead: [], allowWrite: [], denyWrite: []},
			network: {
				strictAllowlist: true,
				tlsTerminate: {},
				allowedDomains: ["a.example", "b.example"],
				deniedDomains: ["bad.example"]
			}
		}
	}' > "${CFG}/portable.json"
	printf '{"model": "x"}\n' > "$TARGET"
}

_overlay() {
	printf '%s\n' "$1" > "${CFG}/portable.local.json"
}

_result() {
	jq -c "$1" "$TARGET"
}

@test "overlay: arrays union in stable order with no duplicates" {
	_overlay '{"sandbox":{"network":{"allowedDomains":["b.example","c.example","c.example"]}}}'
	run "$SCRIPT" claude
	[ "$status" -eq 0 ]
	[ "$(_result .sandbox.network.allowedDomains)" = '["a.example","b.example","c.example"]' ]
}

@test "overlay: the deny list unions too" {
	_overlay '{"sandbox":{"network":{"deniedDomains":["worse.example"]}}}'
	run "$SCRIPT" claude
	[ "$status" -eq 0 ]
	[ "$(_result .sandbox.network.deniedDomains)" = '["bad.example","worse.example"]' ]
}

@test "overlay: a host-local entry already in the target survives an apply" {
	jq '.sandbox.network.allowedDomains = ["z.example"]' "$TARGET" > "${TARGET}.new"
	mv "${TARGET}.new" "$TARGET"
	_overlay '{"sandbox":{"network":{"allowedDomains":["z.example"]}}}'
	run "$SCRIPT" claude
	[ "$status" -eq 0 ]
	[ "$(_result '.sandbox.network.allowedDomains | index("z.example") != null')" = 'true' ]
}

@test "overlay: without it a host-local entry is deleted (the bug)" {
	jq '.sandbox.network.allowedDomains = ["z.example"]' "$TARGET" > "${TARGET}.new"
	mv "${TARGET}.new" "$TARGET"
	run "$SCRIPT" claude
	[ "$status" -eq 0 ]
	[ "$(_result '.sandbox.network.allowedDomains | index("z.example")')" = 'null' ]
}

@test "overlay: a missing file changes nothing" {
	run "$SCRIPT" claude
	[ "$status" -eq 0 ]
	[ "$(_result .sandbox.network.allowedDomains)" = '["a.example","b.example"]' ]
	run "$SCRIPT" --check claude
	[ "$status" -eq 0 ]
	[[ "$output" == *'claude: in sync'* ]]
}

@test "overlay: a key only the overlay names is added" {
	_overlay '{"extraKey":{"list":["q"]}}'
	run "$SCRIPT" claude
	[ "$status" -eq 0 ]
	[ "$(_result .extraKey)" = '{"list":["q"]}' ]
}

@test "overlay: a second apply is a no-op" {
	_overlay '{"sandbox":{"network":{"allowedDomains":["c.example"]}}}'
	"$SCRIPT" claude
	run "$SCRIPT" claude
	[ "$status" -eq 0 ]
	[[ "$output" == *'claude: in sync'* ]]
}

@test "overlay: --check reports in sync once the overlay is applied" {
	_overlay '{"sandbox":{"network":{"allowedDomains":["c.example"]}}}'
	"$SCRIPT" claude
	run "$SCRIPT" --check claude
	[ "$status" -eq 0 ]
}

@test "overlay: a file that is not JSON fails the run and leaves the target" {
	printf 'not json\n' > "${CFG}/portable.local.json"
	run "$SCRIPT" claude
	[ "$status" -ne 0 ]
	[[ "$output" != *'applied'* ]]
	[ "$(cat "$TARGET")" = '{"model": "x"}' ]
}

@test "overlay: a top-level array fails the run and leaves the target" {
	_overlay '["a.example"]'
	run "$SCRIPT" claude
	[ "$status" -ne 0 ]
	[[ "$output" != *'applied'* ]]
	[ "$(cat "$TARGET")" = '{"model": "x"}' ]
}

@test "overlay: the pi tool honours its own overlay" {
	mkdir -p "${HOME}/.config/agents/pi" "${HOME}/.pi/agent"
	printf '{"list":["p"]}\n' > "${HOME}/.config/agents/pi/portable.json"
	printf '{"list":["l"]}\n' > "${HOME}/.config/agents/pi/portable.local.json"
	run "$SCRIPT" pi
	[ "$status" -eq 0 ]
	[ "$(jq -c .list "${HOME}/.pi/agent/settings.json")" = '["p","l"]' ]
}

@test "srt: the derived file follows the overlay and srt accepts it" {
	command -v srt > /dev/null || skip 'srt not installed'
	_overlay '{"sandbox":{"network":{"allowedDomains":["c.example"]}}}'
	run "$SCRIPT" claude srt
	[ "$status" -eq 0 ]
	[ "$(jq -c .network.allowedDomains "$SRT")" = '["a.example","b.example","c.example"]' ]
	# srt validates before it runs; a nested bwrap may fail afterwards.
	run srt --settings "$SRT" true
	[[ "$output" != *'does not hold a valid config'* ]]
}

@test "srt: an injectHosts entry only the overlay allows stays valid" {
	command -v srt > /dev/null || skip 'srt not installed'
	jq '.sandbox.credentials.envVars = [{name: "TOKEN", mode: "mask", injectHosts: ["c.example"]}]' \
		"${CFG}/portable.json" > "${CFG}/p.new"
	mv "${CFG}/p.new" "${CFG}/portable.json"
	_overlay '{"sandbox":{"network":{"allowedDomains":["c.example"]}}}'
	run "$SCRIPT" claude srt
	[ "$status" -eq 0 ]
	run srt --settings "$SRT" true
	[[ "$output" != *'does not hold a valid config'* ]]
	[[ "$output" != *'not reachable via network.allowedDomains'* ]]
}

@test "simulated apply: a copy of the live settings loses no value" {
	LIVE="${REAL_HOME}/.claude/settings.json"
	LIVE_CFG="${REAL_HOME}/.config/agents/claude"
	[ -f "$LIVE" ] || skip 'no live settings'
	[ -f "$DEFAULT_OVERLAY" ] || skip 'no overlay'
	cp "${LIVE_CFG}/portable.json" "${CFG}/portable.json"
	cp "$DEFAULT_OVERLAY" "${CFG}/portable.local.json"
	cp "$LIVE" "$TARGET"
	cp "$TARGET" "${BATS_TEST_TMPDIR}/before.json"
	run "$SCRIPT" claude
	[ "$status" -eq 0 ]
	# Count scalar leaves of the old file that are absent from the new one,
	# treating arrays as sets.  Print the count only, never the values.
	lost="$(jq -n \
		--slurpfile a "${BATS_TEST_TMPDIR}/before.json" \
		--slurpfile b "$TARGET" '
		def leaves: [paths(scalars) as $p | {p: ($p | map(if type == "number" then "#" else . end)), v: getpath($p)}];
		($b[0] | leaves) as $after
		| [($a[0] | leaves)[] | select(. as $x | $after | index([$x]) | not)] | length')"
	[ "$lost" = '0' ]
}
