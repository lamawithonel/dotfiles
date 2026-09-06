#!/bin/sh
#
# test-external.sh -- probe the external delegation channel and name
# the part that is broken.
#
# Usage:
#	test-external.sh [FILTER]
#
# Runs every executable case in tests/, in filename order.  FILTER is a
# substring matched against the case name, so `test-external.sh pi`
# runs only the pi cases and `test-external.sh 20` runs one.
#
# Adding a case: drop an executable file in tests/.  Nothing else
# changes -- no registration, no list to update.  A case writes its
# diagnostic to stdout or stderr and exits 0 (pass), 77 (skip, for a
# precondition it cannot meet), or anything else (fail).
#
# Environment read by the cases:
#	DELEGATE_TEST_TIMEOUT    seconds for a live round-trip (default 90)
#	DELEGATE_TEST_PI_MODEL   model for the pi round-trip

set -o nounset

PROG="${0##*/}"
readonly PROG

pass=0
fail=0
skip=0
n=0
failed=''

_die() {
	echo "${PROG}: $1" >&2
	exit 2
}

_selected() {
	case "$1" in
		*"${FILTER}"*) return 0 ;;
	esac
	return 1
}

_tally() {
	case "$1" in
		0)
			pass=$((pass + 1))
			printf 'ok %d - %s\n' "${n}" "$2"
			;;
		77)
			skip=$((skip + 1))
			printf 'ok %d - %s # SKIP\n' "${n}" "$2"
			;;
		*)
			fail=$((fail + 1))
			failed="${failed} $2"
			printf 'not ok %d - %s\n' "${n}" "$2"
			;;
	esac
}

_run_case() {
	_out="$("$1" 2>&1)"
	_tally "$?" "$2"
	[ -n "${_out}" ] || return 0
	printf '%s\n' "${_out}" | sed 's/^/#   /'
}

_report() {
	printf '1..%d\n' "${n}"
	printf '# %d passed, %d failed, %d skipped\n' "${pass}" "${fail}" "${skip}"
	[ "${fail}" -eq 0 ] && return 0
	printf '# failed:%s\n' "${failed}"
	return 1
}

TESTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/tests" 2> /dev/null && pwd)"
FILTER="${1:-}"

[ -n "${TESTS_DIR}" ] || _die 'no tests/ directory beside this script'

for case_file in "${TESTS_DIR}"/*; do
	[ -f "${case_file}" ] || continue

	name="${case_file##*/}"
	name="${name%.sh}"

	_selected "${name}" || continue
	[ -x "${case_file}" ] || _die "${name} is not executable"

	n=$((n + 1))
	_run_case "${case_file}" "${name}"
done

[ "${n}" -gt 0 ] || _die "no cases matched filter '${FILTER}'"

_report
