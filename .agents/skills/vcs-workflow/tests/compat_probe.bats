#!/usr/bin/env bats
# Contract for scripts/compat_probe.sh: feature claims only, receipt
# schema vcs-compat-probe/2, and no leak into the config tree.  Every
# test runs on a PATH without gh -- the probe must never reach for it.

load test_helper

# run_probe [TOOL] -- run the probe on a PATH that hides TOOL (default
# gh) and set RECEIPT to the receipt path under the private HOME.
run_probe() {
	local nobin
	nobin="$(path_without "${1:-gh}")"
	RECEIPT="$HOME/.agents/.local/state/vcs-workflow/compat-probe.json"
	run --separate-stderr env PATH="$nobin" "$SCRIPTS/compat_probe.sh"
}

# assert_failed NAME... -- every NAME is listed in claims.failed.
assert_failed() {
	local c
	for c in "$@"; do
		run jq -e --arg c "$c" '.claims.failed | index($c) != null' "$RECEIPT"
		[ "$status" -eq 0 ] || {
			echo "claim '$c' is not in failed[]" >&2
			return 1
		}
	done
}

# assert_not_failed NAME... -- no NAME is listed in claims.failed.
assert_not_failed() {
	local c
	for c in "$@"; do
		run jq -e --arg c "$c" '.claims.failed | index($c) == null' "$RECEIPT"
		[ "$status" -eq 0 ] || {
			echo "claim '$c' is in failed[]" >&2
			return 1
		}
	done
}

@test "compat_probe: receipt is vcs-compat-probe/2 with no tools or pins_behind" {
	run_probe
	[ -s "$RECEIPT" ]
	run jq -e '
		.schema == "vcs-compat-probe/2"
		and (has("tools") | not)
		and (has("pins_behind") | not)
		and (has("probe_version") | not)
		and (.probed_at | type == "string")
		and (.claims.passed | type == "number")
		and (.claims.failed | type == "array")
		and (.verdict | test("^(green|drift)$"))
	' "$RECEIPT"
	[ "$status" -eq 0 ]
}

@test "compat_probe: no version string survives in the script" {
	run grep -nE '[0-9]+\.[0-9]+\.[0-9]+|_PIN|probe_version|pins_behind|gh release' "$SCRIPTS/compat_probe.sh"
	[ "$status" -ne 0 ]
}

@test "compat_probe: green verdict and exit 0 on the installed jj" {
	run_probe
	[ "$status" -eq 0 ]
	[[ "$output" == "PROBE-GREEN passed="* ]]
	[[ "$output" == *"failed=[]"* ]]
	[[ "$output" == *"receipt=$RECEIPT" ]]
	run jq -r '.verdict' "$RECEIPT"
	[ "$output" = green ]
	run jq -r '.claims.passed' "$RECEIPT"
	[ "$output" -ge 25 ]
}

@test "compat_probe: leaves no repo config under the private config tree" {
	run_probe
	[ "$status" -eq 0 ]
	[ ! -d "$XDG_CONFIG_HOME/jj/repos" ]
}

@test "compat_probe: an unwritable receipt directory is reported, not passed over" {
	# A regular file where the state directory belongs: mkdir -p fails,
	# so no receipt can be written and the probe must say so.
	mkdir -p "$HOME/.agents/.local/state"
	: > "$HOME/.agents/.local/state/vcs-workflow"
	run_probe
	[ "$status" -eq 1 ]
	[[ "$output" == PROBE-FAIL* ]]
	[ -f "$HOME/.agents/.local/state/vcs-workflow" ]
}

@test "compat_probe: a receipt that cannot be written is reported, not passed over" {
	# A read-only state directory: the temp file cannot be created, so
	# the stale receipt must survive untouched and unannounced.
	local dir="$HOME/.agents/.local/state/vcs-workflow"
	mkdir -p "$dir"
	printf 'stale\n' > "$dir/compat-probe.json"
	chmod 500 "$dir"
	run_probe
	chmod 700 "$dir"
	[ "$status" -eq 1 ]
	[ "$output" = 'PROBE-FAIL receipt-write' ]
	[ "$(cat "$dir/compat-probe.json")" = stale ]
	[ ! -e "$dir/compat-probe.json.tmp" ]
}

@test "compat_probe: the throwaway config home never escapes the caller's" {
	local cfg="$BATS_TEST_TMPDIR/caller-config" nobin
	nobin="$(path_without gh)"
	mkdir -p "$cfg"
	RECEIPT="$HOME/.agents/.local/state/vcs-workflow/compat-probe.json"
	run --separate-stderr env PATH="$nobin" XDG_CONFIG_HOME="$cfg" \
		"$SCRIPTS/compat_probe.sh"
	[ "$status" -eq 0 ]
	[ -s "$RECEIPT" ]
	[ -z "$(ls -A "$cfg")" ]
}

@test "compat_probe: every jj claim fails by name when jj is absent" {
	run_probe jj
	[ "$status" -eq 1 ]
	[[ "$output" == "PROBE-DRIFT passed="* ]]
	assert_failed jj-present run-ignore-changes run-jobs absorb-into absorb-from \
		split-tool split-message describe-stdin push-dry-run restore-from \
		push-no-force-flag bisect-run fix op-restore workspace-update-stale \
		workspace-forget git-colocation tmp-store-init revset-conflicts \
		revset-description-substring revset-bookmarks-exact \
		config-repo-roundtrip snapshot-auto-track
	assert_not_failed git-present jq-present
}

@test "compat_probe: an uncreatable temp store fails the store claims by name" {
	# A regular file where TMPDIR points: mktemp -d cannot create under
	# it, so the store claims must fail by name.  An unchecked mktemp
	# leaves the path empty and aims the probe at /store with its config
	# home at /config -- caught here by a jj recording its argv, because
	# on an unwritable root that attempt fails the same claims anyway.
	local fake="$BATS_TEST_TMPDIR/tmpdir-is-a-file" nobin log
	: > "$fake"
	nobin="$(path_without gh)"
	log="$BATS_TEST_TMPDIR/jj-argv.log"
	rm -f "$nobin/jj"
	cat > "$nobin/jj" <<- EOF
		#!/bin/sh
		printf '%s\n' "\$*" >> '$log'
		exec '$(command -v jj)' "\$@"
	EOF
	chmod 755 "$nobin/jj"
	RECEIPT="$HOME/.agents/.local/state/vcs-workflow/compat-probe.json"
	run --separate-stderr env PATH="$nobin" TMPDIR="$fake" "$SCRIPTS/compat_probe.sh"
	[ "$status" -eq 1 ]
	assert_failed tmp-store-init revset-conflicts revset-description-substring \
		revset-bookmarks-exact config-repo-roundtrip snapshot-auto-track
	run grep -F -- '/store' "$log"
	[ "$status" -ne 0 ]
	[ ! -e /store ]
	[ ! -e /config ]
}

@test "compat_probe: presence claims fail by name for the missing tool only" {
	run_probe jq
	[ "$status" -eq 1 ]
	assert_failed jq-present
	assert_not_failed jj-present git-present run-ignore-changes tmp-store-init
}
