# test_helper.bash -- shared setup for the PACT lint bats suite.
# Sourced by every tests/*.bats file.
#
# Every path is absolute.  No test depends on the working directory.

bats_require_minimum_version 1.5.0

SCHEMA_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
LINT="$SCHEMA_DIR/pact-lint.sh"
EXAMPLES="$SCHEMA_DIR/examples"
INVALID="$SCHEMA_DIR/tests/invalid"
VALID="$SCHEMA_DIR/tests/valid"
FIXTURES="$SCHEMA_DIR/tests/fixtures"
export SCHEMA_DIR LINT EXAMPLES INVALID VALID FIXTURES

# assert_valid TYPE -- the example for TYPE passes with no output.
assert_valid() {
	run "$LINT" "$EXAMPLES/$1.pact"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

# assert_valid_fixture NAME -- the valid fixture NAME passes with no
# output.
assert_valid_fixture() {
	run "$LINT" "$VALID/$1.pact"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

# assert_rejected NAME REGEX -- invalid fixture NAME fails with exit 1
# and a problem line that matches REGEX.  Every line starts with the
# file path.
assert_rejected() {
	local file="$INVALID/$1"
	[ -e "$file" ] || file="$INVALID/$1.pact"
	run "$LINT" "$file"
	[ "$status" -eq 1 ]
	printf '%s\n' "$output" | grep -E -q -- "$2" || {
		printf 'no line matches /%s/\noutput:\n%s\n' "$2" "$output" >&2
		return 1
	}
	# Each output line names the file.
	local line
	while IFS= read -r line; do
		case "$line" in
			"$file"*) ;;
			*)
				printf 'line lacks file prefix: %s\n' "$line" >&2
				return 1
				;;
		esac
	done <<< "$output"
}
