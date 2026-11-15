#!/usr/bin/env bats
# Characterization of pact-lint.sh: one problem per output line, exit
# 0 valid, 1 invalid, 2 usage error.  Fully offline.

load test_helper

# -- usage and exit codes ---------------------------------------------

@test "lint: no arguments is a usage error, exit 2" {
	run -2 "$LINT"
	[[ "$output" == *Usage* ]]
}

@test "lint: unknown option is a usage error, exit 2" {
	run -2 "$LINT" --bogus "$EXAMPLES/freeze.pact"
	[[ "$output" == *Usage* ]]
}

@test "lint: missing file is a usage error, exit 2" {
	run -2 "$LINT" "$BATS_TEST_TMPDIR/absent.pact"
	[[ "$output" == *absent.pact* ]]
}

@test "lint: --help exits 0 and says validation is advisory" {
	run -0 "$LINT" --help
	[[ "$output" == *advisory* ]]
	[[ "$output" == *"never reject"* ]]
}

@test "lint: help documents the exit codes" {
	run -0 "$LINT" -h
	[[ "$output" == *"0 "* && "$output" == *"1 "* && "$output" == *"2 "* ]]
}

# -- valid examples: one per document type ----------------------------

@test "valid: charter" { assert_valid charter; }
@test "valid: worker-brief" { assert_valid worker-brief; }
@test "valid: worker-brief with output" { assert_valid worker-brief-with-output; }
@test "valid: consultation" { assert_valid consultation; }
@test "valid: question" { assert_valid question; }
@test "valid: freeze" { assert_valid freeze; }
@test "valid: relay" { assert_valid relay; }
@test "valid: ruling" { assert_valid ruling; }
@test "valid: escalation" { assert_valid escalation; }
@test "valid: prompt (core)" { assert_valid prompt; }
@test "valid: message (core)" { assert_valid message; }
@test "valid: agent-definition (core)" { assert_valid agent-definition; }

@test "valid: agent definition inside a .md file with frontmatter" {
	run -0 "$LINT" "$FIXTURES/agent-definition.md"
	[ -z "$output" ]
}

@test "valid: working directory does not matter" {
	run -0 env -C / "$LINT" "$EXAMPLES/charter.pact"
}

@test "valid: runs with a dead network proxy (offline)" {
	run -0 env http_proxy=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 \
		"$LINT" "$EXAMPLES/charter.pact"
}

# -- coverage of the suite itself -------------------------------------

@test "suite: every document type has an example" {
	local t
	for t in charter worker-brief consultation question freeze relay \
		ruling escalation prompt message agent-definition; do
		[ -f "$EXAMPLES/$t.pact" ] || {
			echo "missing example: $t" >&2
			return 1
		}
	done
}

@test "suite: every profile and agent-definition type has an invalid example" {
	local t
	for t in charter worker-brief consultation question freeze relay \
		ruling escalation agent-definition prompt message; do
		compgen -G "$INVALID/$t-*" > /dev/null || {
			echo "no invalid example for: $t" >&2
			return 1
		}
	done
}

@test "suite: no schema reaches for the network" {
	run grep -E 'schemaLocation="https?:' "$SCHEMA_DIR"/*.xsd
	[ "$status" -eq 1 ]
}

# -- invalid: charter -------------------------------------------------

@test "invalid: charter without persona" {
	assert_rejected charter-no-persona 'charter: missing required element <persona>'
}

@test "invalid: charter without supervisor" {
	assert_rejected charter-no-supervisor 'charter: missing required element <supervisor>'
}

@test "invalid: charter without onboarding digest" {
	assert_rejected charter-no-onboarding 'charter: missing required element <onboarding>'
}

@test "invalid: charter position class worker" {
	assert_rejected charter-bad-class "attribute 'class'.*worker"
}

@test "invalid: charter position class consultant" {
	assert_rejected charter-class-consultant "attribute 'class'.*consultant"
}

@test "invalid: charter position class deputy" {
	assert_rejected charter-class-deputy "attribute 'class'.*deputy"
}

@test "invalid: two missing elements give two lines" {
	run "$LINT" "$INVALID/charter-two-missing.pact"
	[ "$status" -eq 1 ]
	[ "${#lines[@]}" -eq 2 ]
}

# -- invalid: worker-brief --------------------------------------------

@test "invalid: worker-brief without verification" {
	assert_rejected worker-brief-no-verification 'worker-brief: missing required element <verification>'
}

@test "invalid: worker-brief without persona" {
	assert_rejected worker-brief-no-persona 'worker-brief: missing required element <persona>'
}

@test "invalid: worker-brief carrying an old guard" {
	assert_rejected worker-brief-guards "guard text 'STALL WATCHDOG' does not belong"
}

@test "invalid: worker-brief output field without name" {
	assert_rejected worker-brief-output-field-no-name "name"
}

# -- invalid: consultation --------------------------------------------

@test "invalid: consultation without persona" {
	assert_rejected consultation-no-persona 'consultation: missing required element <persona>'
}

@test "invalid: consultation position class is not consultant" {
	assert_rejected consultation-bad-class "attribute 'class'.*consultant"
}

@test "invalid: consultation without ends-when" {
	assert_rejected consultation-no-ends-when 'consultation: missing required element <ends-when>'
}

# -- invalid: question ------------------------------------------------

@test "invalid: question with a persona" {
	assert_rejected question-with-persona "Element 'persona': This element is not expected"
}

@test "invalid: question without ask" {
	assert_rejected question-no-ask 'question: missing required element <ask>'
}

# -- invalid: freeze --------------------------------------------------

@test "invalid: freeze without the dispatch flag" {
	assert_rejected freeze-no-covers-dispatch 'freeze: missing required element <covers-dispatch>'
}

@test "invalid: freeze dispatch flag must be true or false" {
	assert_rejected freeze-covers-dispatch-maybe "covers-dispatch.*'maybe'"
}

@test "invalid: freeze without lifter" {
	assert_rejected freeze-no-lifter 'freeze: missing required element <lifter>'
}

@test "invalid: freeze without end" {
	assert_rejected freeze-no-end 'freeze: missing required element <end>'
}

@test "invalid: freeze with a blank reason" {
	assert_rejected freeze-blank-reason "Element 'reason'"
}

# -- invalid: relay ---------------------------------------------------

@test "invalid: relay without the quoted freeze" {
	assert_rejected relay-no-quote 'relay: missing required element <quote>'
}

@test "invalid: relay with an empty additions element" {
	assert_rejected relay-empty-additions "Element 'additions'"
}

@test "invalid: relay quote differs from its freeze" {
	assert_rejected relay-quote-differs 'relay-quote-differs.pact:[0-9]+: relay quote differs from \.\./\.\./examples/freeze\.pact'
}

@test "invalid: relay source file is missing" {
	assert_rejected relay-source-missing 'relay-source-missing.pact:[0-9]+: relay source not found: no-such-freeze\.pact'
}

# -- invalid: ruling --------------------------------------------------

@test "invalid: ruling without issuer" {
	assert_rejected ruling-no-issuer 'ruling: missing required element <issuer>'
}

@test "invalid: ruling with a persona" {
	assert_rejected ruling-with-persona "Element 'persona': This element is not expected"
}

# -- invalid: escalation ----------------------------------------------

@test "invalid: escalation without request" {
	assert_rejected escalation-no-request 'escalation: missing required element <request>'
}

@test "invalid: escalation with a persona" {
	assert_rejected escalation-with-persona "Element 'persona': This element is not expected"
}

# -- invalid: core types ----------------------------------------------

@test "invalid: agent-definition without persona" {
	assert_rejected agent-definition-no-persona 'agent-definition: missing required element <persona>'
}

@test "invalid: agent definition in .md without persona, line numbers kept" {
	local file="$INVALID/agent-definition-md-no-persona.md"
	local want
	want="$(grep -n '<agent-definition' "$file" | head -n 1 | cut -d: -f1)"
	run "$LINT" "$file"
	[ "$status" -eq 1 ]
	[[ "$output" == "$file:$want: agent-definition: missing required element <persona>" ]]
}

@test "invalid: prompt without persona" {
	assert_rejected prompt-no-persona 'prompt: missing required element <persona>'
}

@test "invalid: message with a persona" {
	assert_rejected message-with-persona "Element 'persona': This element is not expected"
}

# -- invalid: cross-type rules ----------------------------------------

@test "invalid: priority MUST is retired, hint names critical plus required" {
	assert_rejected prompt-priority-must 'priority="critical".*required="true"'
}

@test "invalid: critical constraint without required=true" {
	assert_rejected prompt-critical-not-required 'critical.*required="true"'
}

@test "invalid: empty persona quadrant" {
	assert_rejected prompt-empty-quadrant '<perception> is empty'
}

@test "invalid: quadrant attribute must match its element" {
	assert_rejected prompt-wrong-quadrant "attribute 'quadrant'"
}

@test "invalid: em-dash is rejected" {
	assert_rejected prompt-em-dash 'em-dash'
}

@test "invalid: file that is not well-formed" {
	assert_rejected not-well-formed 'not well-formed'
}

@test "invalid: unknown root element" {
	assert_rejected unknown-root 'unknown document type'
}

@test "invalid: root element without a namespace" {
	assert_rejected no-namespace-root 'unknown document type'
}

# -- several files ----------------------------------------------------

@test "multi: exit 1 when any file is invalid, report only that file" {
	run "$LINT" "$EXAMPLES/charter.pact" "$INVALID/freeze-no-lifter.pact"
	[ "$status" -eq 1 ]
	[[ "$output" == *freeze-no-lifter.pact* ]]
	[[ "$output" != *examples/charter.pact* ]]
}
