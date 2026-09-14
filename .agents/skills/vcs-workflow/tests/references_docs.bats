#!/usr/bin/env bats
# Contract for the reference files this lane owns: the retired tooling
# is gone from the prose, the retired trap numbers are recorded rather
# than reused, and every receipt field documented in receipts.md exists
# in the script that emits it.

load test_helper

REFS="$SKILL_DIR/references"

# Terms that must not survive anywhere in the documentation.  The one
# sanctioned exception is traps.md's retirement note, which names the
# retired tooling on purpose; strip that paragraph before sweeping.
FORBIDDEN='difftastic|ast-grep|ast_grep|Serena|Verified-against|bootstrap|gh_recover|git_only_hunks|pins_behind|compat-recover|0\.44\.0|0\.45\.1|0\.70\.0'

# Scripts that never shipped, or shipped and were withdrawn.  Naming one
# sends a reader after a file that does not exist.
RETIRED_NAMES='bootstrap_work|gh_recover|git_only_hunks|bootstrap-locked'

# flat FILE -- the file as one line, so an assertion is not hostage to
# where a sentence happens to wrap.
flat() {
	tr '\n' ' ' < "$1" | tr -s ' '
}

@test "sweep: no retired tooling in any reference file or SKILL.md" {
	local f hits
	for f in "$REFS"/*.md "$SKILL_DIR/SKILL.md"; do
		hits="$(awk '/^Numbers are stable identifiers/{skip=1} skip&&/^$/{skip=0} !skip' \
			"$f" | grep -n -i -E "$FORBIDDEN" || true)"
		[ -z "$hits" ] || {
			echo "$f still carries: $hits" >&2
			return 1
		}
	done
}

@test "sweep: no retired script name in any reference file or SKILL.md" {
	local f hits
	for f in "$REFS"/*.md "$SKILL_DIR/SKILL.md"; do
		hits="$(grep -n -E "$RETIRED_NAMES" "$f" || true)"
		[ -z "$hits" ] || {
			echo "$f names a retired script: $hits" >&2
			return 1
		}
	done
}

@test "traps: retired entries are gone and their numbers are recorded" {
	local n
	for n in 2 3 8 15 20 21; do
		run grep -c "^$n\. \*\*" "$REFS/traps.md"
		[ "$output" = '0' ]
	done
	run grep -q 'Numbers are stable identifiers, not positions' "$REFS/traps.md"
	[ "$status" -eq 0 ]
	flat "$REFS/traps.md" | grep -q '2, 3, 8, 15, 20, and 21 retired with the'
	flat "$REFS/traps.md" | grep -q 'those numbers are not reused'
}

@test "traps: every surviving entry number is still present exactly once" {
	local n
	for n in 1 4 5 6 7 9 10 11 12 13 14 16 17 18 19 22 23 24 25 26 27; do
		run grep -cE "^ *$n\. \*\*" "$REFS/traps.md"
		[ "$output" = '1' ] || {
			echo "entry $n appears $output times" >&2
			return 1
		}
	done
}

@test "traps: reworded entries carry their new claims" {
	flat "$REFS/traps.md" | grep -q 'isolate with jj workspaces instead'
	flat "$REFS/traps.md" | grep -q 'refuses inside any linked git worktree, loudly'
	flat "$REFS/traps.md" | grep -q 'never from pip'
	flat "$REFS/traps.md" | grep -q "PyPI's .cog. is an unrelated project"
	flat "$REFS/traps.md" | grep -q 'Applies to any .git rebase --exec. run outside this skill'
	# 25-27 cite the claim name, never a line range in compat_probe.sh.
	run grep -c 'push-no-force-flag' "$REFS/traps.md"
	[ "$output" -ge 3 ]
	run grep -cE 'compat_probe\.sh:[0-9]' "$REFS/traps.md"
	[ "$output" = '0' ]
}

@test "traps: the entry-count claim matches the entries that remain" {
	local claimed actual
	claimed="$(grep -oE 'catalogue carries [0-9]+ live entries' "$REFS/traps.md" \
		| grep -oE '[0-9]+')"
	actual="$(grep -cE '^ *[0-9]+\. \*\*' "$REFS/traps.md")"
	[ -n "$claimed" ]
	[ "$claimed" = "$actual" ] || {
		echo "claims $claimed live entries, carries $actual" >&2
		return 1
	}
}

@test "partition: v1 file grain survives, the classifier is a pointer" {
	run grep -q 'jj split <paths...> -m' "$REFS/partition.md"
	[ "$status" -eq 0 ]
	run grep -q 'refused\[\]' "$REFS/partition.md"
	[ "$status" -eq 0 ]
	run grep -q 'design-decisions-final.md' "$REFS/partition.md"
	[ "$status" -eq 0 ]
	run grep -q 'section 8.2' "$REFS/partition.md"
	[ "$status" -eq 0 ]
	# The kind table and the two dropped v2 rules are gone.
	run grep -ciE 'kind table|export_statement|function_definition' "$REFS/partition.md"
	[ "$output" = '0' ]
}

@test "receipts: compat-recover is gone and the live schemas are named" {
	run grep -ciE 'vcs-compat-recover|four schemas' "$REFS/receipts.md"
	[ "$output" = '0' ]
	run grep -q 'vcs-compat-probe/2' "$REFS/receipts.md"
	[ "$status" -eq 0 ]
	run grep -q 'vcs-handoff/2' "$REFS/receipts.md"
	[ "$status" -eq 0 ]
	# The consumer statement: this skill and serialization.md read it.
	flat "$REFS/receipts.md" | grep -q 'pre-serialization checklist in .serialization.md'
	flat "$REFS/receipts.md" | grep -q '.git-commit. does not'
}

@test "receipts: every documented handoff/2 field exists in the script" {
	local k
	for k in schema shape level toolchain preflight base stack gate absorb \
		partition conflicts message_hints workspace repo ready fails warns; do
		run grep -qE "^$k(\[\])?([ ,]|$)" "$REFS/receipts.md"
		[ "$status" -eq 0 ] || {
			echo "receipts.md does not document handoff field '$k'" >&2
			return 1
		}
		run grep -qE "^\s+$k[:,]" "$SCRIPTS/emit_handoff.sh"
		[ "$status" -eq 0 ] || {
			echo "emit_handoff.sh does not emit '$k'" >&2
			return 1
		}
	done
}

@test "receipts: the handoff exit table carries the oplog level block" {
	run grep -qE '^\| 6 \|.*LEVEL-BLOCKED level=oplog' "$REFS/receipts.md"
	[ "$status" -eq 0 ]
	run grep -qE '^\| 6 \|.*\| no \|' "$REFS/receipts.md"
	[ "$status" -eq 0 ]
}

@test "receipts: probe/2 documents the receipt failures the script emits" {
	local m
	for m in receipt-dir receipt-write; do
		run grep -q "PROBE-FAIL $m" "$SCRIPTS/compat_probe.sh"
		[ "$status" -eq 0 ] || {
			echo "compat_probe.sh does not emit PROBE-FAIL $m" >&2
			return 1
		}
		run grep -q "PROBE-FAIL $m" "$REFS/receipts.md"
		[ "$status" -eq 0 ] || {
			echo "receipts.md does not document PROBE-FAIL $m" >&2
			return 1
		}
	done
}

@test "receipts: probe/2 fields match compat_probe.sh" {
	local k
	for k in schema probed_at claims verdict; do
		run grep -q "\"$k\"" "$SCRIPTS/compat_probe.sh"
		[ "$status" -eq 0 ]
		run grep -qE "^$k " "$REFS/receipts.md"
		[ "$status" -eq 0 ]
	done
	# Fields the rewrite dropped must not be documented any more.
	run grep -ciE '^(tools|probe_version) ' "$REFS/receipts.md"
	[ "$output" = '0' ]
}

@test "safety-net: three keys plus snapshot.auto-track at standard" {
	run grep -q 'snapshot.auto-track' "$REFS/safety-net.md"
	[ "$status" -eq 0 ]
	run grep -ciE 'four keys|four `--repo`' "$REFS/safety-net.md"
	[ "$output" = '0' ]
	run grep -q 'merge-tools' "$REFS/safety-net.md"
	[ "$status" -eq 1 ]
	# Identity assertion documented beside the editor guard.
	run grep -q 'never falls back' "$REFS/safety-net.md"
	[ "$status" -eq 0 ]
	run grep -q 'PREFLIGHT-FAIL identity' "$REFS/safety-net.md"
	[ "$status" -eq 0 ]
}

@test "safety-net: the documented receipt matches a real preflight run" {
	local d
	d="$(fx_colocated sn)"
	env -C "$d" git config --local vcs-workflow.level standard
	# A fresh probe receipt, so the run reports probe=ok.
	mkdir -p "$HOME/.agents/.local/state/vcs-workflow"
	printf '{"verdict":"green"}\n' \
		> "$HOME/.agents/.local/state/vcs-workflow/compat-probe.json"
	run env -C "$d" "$SCRIPTS/preflight.sh"
	[ "$status" -eq 0 ]
	assert_repo_config_isolated "$d"
	# The documented line and the emitted one share every token but
	# the opaque store id.
	local doc emitted
	doc="$(grep -o 'PREFLIGHT-OK shape=.*probe=[a-z]*' "$REFS/safety-net.md" | head -1)"
	emitted="$output"
	[ "${doc/store=*protected/store=X protected}" = "${emitted/store=*protected/store=X protected}" ] || {
		echo "doc:     $doc" >&2
		echo "emitted: $emitted" >&2
		return 1
	}
}

@test "safety-net: the documented key set matches what preflight writes" {
	local d
	d="$(fx_colocated sn2)"
	env -C "$d" git config --local vcs-workflow.level standard
	run env -C "$d" "$SCRIPTS/preflight.sh"
	[ "$status" -eq 0 ]
	run env -C "$d" jj config list --repo
	[ "$(printf '%s\n' "$output" | wc -l)" -eq 4 ]
	printf '%s\n' "$output" | grep -q 'snapshot.auto-track = "none"'
	printf '%s\n' "$output" | grep -q 'ui.editor = ":true"'
	printf '%s\n' "$output" | grep -q 'ui.diff-editor = ":true"'
	printf '%s\n' "$output" | grep -q 'immutable_heads'
}

@test "serialization: level decides the serializing command" {
	run grep -q 'git commit -F' "$REFS/serialization.md"
	[ "$status" -eq 0 ]
	run grep -qE 'level `oplog`' "$REFS/serialization.md"
	[ "$status" -eq 0 ]
	run grep -q 'jj describe --stdin' "$REFS/serialization.md"
	[ "$status" -eq 0 ]
	run grep -q 'cog verify --file' "$REFS/serialization.md"
	[ "$status" -eq 0 ]
}

@test "serialization: at oplog there is no handoff receipt to read" {
	run grep -q 'LEVEL-BLOCKED' "$REFS/serialization.md"
	[ "$status" -eq 0 ]
	flat "$REFS/serialization.md" | grep -q 'exists only at .standard. and .full.'
	flat "$REFS/serialization.md" | grep -q 'read nothing'
}

@test "verify: the --cheap example no longer names ast-grep" {
	run grep -n -- '--cheap' "$REFS/verify.md"
	[ "$status" -eq 0 ]
	run grep -q 'Sub-second command (lint, fast unit tests)' "$REFS/verify.md"
	[ "$status" -eq 0 ]
}
