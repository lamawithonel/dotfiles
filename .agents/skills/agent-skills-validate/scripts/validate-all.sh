#!/usr/bin/env bash
# agent-skills-validate — validate every skill under one or more roots.
# Default root: skills/ (relative to git toplevel).
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE="$SCRIPT_DIR/validate.sh"

REPO_ROOT="$(git rev-parse --show-toplevel 2> /dev/null || pwd)"

if [[ $# -eq 0 ]]; then
	ROOTS=("$REPO_ROOT/skills")
else
	ROOTS=("$@")
fi

TOTAL=0
FAILED=0
WARNED=0
SKIPPED=0

# Run one skill, print its TAP, and tally the outcome.  Warnings are
# counted separately and never affect the exit status: they mark keys a
# harness honours and others drop silently, not defects.
_validate_one() {
	local _dir="$1"
	local _out=""
	local _rc=0

	_out="$(bash "$VALIDATE" "$_dir" 2>&1)" || _rc=$?
	printf '%s\n' "$_out"

	case "$_rc" in
		0) ;;
		3) SKIPPED=$((SKIPPED + 1)) ;;
		*) FAILED=$((FAILED + 1)) ;;
	esac

	[[ "$_out" == *' # WARN'* ]] && WARNED=$((WARNED + 1))
	return 0
}

for ROOT in "${ROOTS[@]}"; do
	# Refuse apm-installed roots wholesale.  Location alone does not
	# disqualify a root; only package-manager-owned trees are skipped.
	case "$ROOT" in
		*apm_modules*)
			echo "# refusing apm-installed root: $ROOT (skipped)" >&2
			continue
			;;
	esac

	if [[ ! -d "$ROOT" ]]; then
		echo "# root not found, skipped: $ROOT" >&2
		continue
	fi

	for SKILL_DIR in "$ROOT"/*/; do
		[[ -d "$SKILL_DIR" ]] || continue
		SKILL_DIR="${SKILL_DIR%/}"
		SKILL_NAME="$(basename "$SKILL_DIR")"
		TOTAL=$((TOTAL + 1))

		echo "# === $SKILL_NAME ($SKILL_DIR) ==="
		_validate_one "$SKILL_DIR"
		echo ""
	done
done

echo "# summary: $TOTAL skills, $FAILED failed, $WARNED warned, $SKIPPED skipped"

[[ "$FAILED" -eq 0 ]] || exit 1
