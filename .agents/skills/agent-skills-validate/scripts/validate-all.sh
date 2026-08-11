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
SKIPPED=0

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
		if bash "$VALIDATE" "$SKILL_DIR"; then
			:
		else
			_rc=$?
			if [[ "$_rc" -eq 3 ]]; then
				SKIPPED=$((SKIPPED + 1))
			else
				FAILED=$((FAILED + 1))
			fi
		fi
		echo ""
	done
done

echo "# summary: $TOTAL skills, $FAILED failed, $SKIPPED skipped"

[[ "$FAILED" -eq 0 ]] || exit 1
