#!/usr/bin/env bash
# agent-skills-validate — validate one Agent Skill against the spec.
# https://agentskills.io/specification
#
# Bash-first; uses yq for YAML parsing (pinned in mise.toml).
# python3 is used opportunistically for NFKC normalization on
# the name-vs-folder check; if python3 is absent the check
# degrades to a raw string comparison.
set -o errexit
set -o nounset
set -o pipefail

usage() {
	cat <<- USAGE
		Usage: $0 <path-or-name>

		Validate one Agent Skill against the Agent Skills Specification.

		The arg is treated as a path if it contains a / or starts with .
		Otherwise it is resolved against skills/ first, then registered roots.

		Refuses to validate apm-installed paths (apm_modules/).
	USAGE
	exit 2
}

[[ $# -eq 1 ]] || usage
[[ "$1" = "-h" || "$1" = "--help" ]] && usage

ARG="$1"
SKILL_DIR=""

# Resolve arg to a directory.
if [[ "$ARG" == */* || "$ARG" == .* ]]; then
	SKILL_DIR="$ARG"
else
	REPO_ROOT="$(git rev-parse --show-toplevel 2> /dev/null || pwd)"
	if [[ -d "$REPO_ROOT/skills/$ARG" ]]; then
		SKILL_DIR="$REPO_ROOT/skills/$ARG"
	else
		echo "ERROR: skill '$ARG' not found under skills/" >&2
		exit 2
	fi
fi

# Refuse apm-installed paths.  Location alone does not disqualify a
# skill (hand-authored skills live anywhere, including ~/.agents/skills
# and project source trees); only package-manager-owned trees are
# upstream-managed.
case "$SKILL_DIR" in
	*apm_modules*)
		echo "upstream-managed skill, not validated: $SKILL_DIR" >&2
		exit 3
		;;
esac

SKILL_DIR="$(cd "$SKILL_DIR" 2> /dev/null && pwd)" || {
	echo "ERROR: skill directory not found: $1" >&2
	exit 2
}

if [[ ! -d "$SKILL_DIR" ]]; then
	echo "ERROR: not a directory: $SKILL_DIR" >&2
	exit 2
fi

SKILL_NAME="$(basename "$SKILL_DIR")"

# Locate SKILL.md (preferred) or skill.md (lowercase fallback).
SKILL_MD=""
for _candidate in SKILL.md skill.md; do
	if [[ -f "$SKILL_DIR/$_candidate" ]]; then
		SKILL_MD="$SKILL_DIR/$_candidate"
		break
	fi
done

PASS=0
FAIL=0
N=0

_check() {
	local _desc="$1"
	local _result="$2" # "ok" or "fail"
	N=$((N + 1))
	if [[ "$_result" = "ok" ]]; then
		echo "ok $N - $_desc"
		PASS=$((PASS + 1))
	else
		echo "not ok $N - $_desc"
		FAIL=$((FAIL + 1))
	fi
}

_summary_and_exit() {
	echo "1..$N"
	echo "$PASS passed, $FAIL failed"
	[[ "$FAIL" -eq 0 ]] || exit 1
	exit 0
}

# Check 1: SKILL.md or skill.md exists at root.
if [[ -n "$SKILL_MD" ]]; then
	_check "SKILL.md (or skill.md) exists at skill root" ok
else
	_check "SKILL.md (or skill.md) exists at skill root" fail
	# Without a SKILL.md the rest of the checks are moot.
	_summary_and_exit
fi

# Check 2: file starts with frontmatter delimiter.
if head -1 "$SKILL_MD" | grep -q '^---$'; then
	_check "file starts with frontmatter delimiter" ok
else
	_check "file starts with frontmatter delimiter" fail
fi

# Check 3: frontmatter is properly closed with a second ---.
DELIM_COUNT="$(grep -cE '^---$' "$SKILL_MD" || true)"
if [[ "$DELIM_COUNT" -ge 2 ]]; then
	_check "frontmatter closed with second ---" ok
else
	_check "frontmatter closed with second --- (got $DELIM_COUNT delimiters)" fail
	# Without a closed frontmatter, downstream YAML parsing is meaningless.
	_summary_and_exit
fi

# Extract the frontmatter block (lines strictly between the first
# two --- markers) for parsing.
FRONTMATTER="$(awk 'BEGIN{c=0} /^---$/{c++; if(c==2) exit; next} c==1' "$SKILL_MD")"

# Check 4: frontmatter is valid YAML.
YAML_PARSE_ERR=""
if YAML_PARSE_ERR="$(echo "$FRONTMATTER" | yq '.' - 2>&1 > /dev/null)"; then
	_check "frontmatter parses as valid YAML" ok
else
	# Trim error to first line for readability.
	_first="${YAML_PARSE_ERR%%$'\n'*}"
	_check "frontmatter parses as valid YAML ($_first)" fail
	# If YAML can't be parsed, downstream key/field checks are noise.
	_summary_and_exit
fi

# Check 5: frontmatter is a YAML mapping.
FM_TAG="$(echo "$FRONTMATTER" | yq 'tag' - 2> /dev/null || echo "")"
if [[ "$FM_TAG" = "!!map" ]]; then
	_check "frontmatter is a YAML mapping" ok
else
	_check "frontmatter is a YAML mapping (got ${FM_TAG:-<unknown>})" fail
	_summary_and_exit
fi

# Pull frontmatter values once for downstream checks.
NAME_VALUE="$(echo "$FRONTMATTER" | yq -r '.name // ""' -)"
DESC_VALUE="$(echo "$FRONTMATTER" | yq -r '.description // ""' -)"
COMPAT_VALUE="$(echo "$FRONTMATTER" | yq -r '.compatibility // ""' -)"
HAS_COMPAT="$(echo "$FRONTMATTER" | yq -r 'has("compatibility")' -)"

# Check 6: name field present.
if echo "$FRONTMATTER" | yq -e 'has("name")' - > /dev/null 2>&1; then
	_check "name field present in frontmatter" ok
else
	_check "name field present in frontmatter" fail
fi

# Check 7: name is 1..64 chars.
NAME_LEN=${#NAME_VALUE}
if [[ "$NAME_LEN" -ge 1 && "$NAME_LEN" -le 64 ]]; then
	_check "name length within 1..64 chars (got $NAME_LEN)" ok
else
	_check "name length within 1..64 chars (got $NAME_LEN)" fail
fi

# Check 8: name is lowercase.
# Bash lower-case fold; compare against original.
NAME_LC="$(printf '%s' "$NAME_VALUE" | tr '[:upper:]' '[:lower:]')"
if [[ "$NAME_VALUE" = "$NAME_LC" ]]; then
	_check "name is lowercase" ok
else
	_check "name is lowercase (got '$NAME_VALUE')" fail
fi

# Check 9: name only contains [a-z0-9-].
# TODO(i18n): the upstream skills-ref accepts unicode lowercase
# letters via unicodedata + str.isalnum(); replicating that
# correctly in bash + yq is non-trivial, and hub-local skills
# are all ASCII today.  Document in Known Limitations.
if [[ "$NAME_VALUE" =~ ^[a-z0-9-]+$ ]]; then
	_check "name uses only [a-z0-9-]" ok
else
	_check "name uses only [a-z0-9-] (got '$NAME_VALUE')" fail
fi

# Check 10: name has no leading or trailing hyphen.
if [[ "$NAME_VALUE" != -* && "$NAME_VALUE" != *- ]]; then
	_check "name has no leading or trailing hyphen" ok
else
	_check "name has no leading or trailing hyphen (got '$NAME_VALUE')" fail
fi

# Check 11: name has no consecutive hyphens.
if [[ "$NAME_VALUE" != *--* ]]; then
	_check "name has no consecutive hyphens" ok
else
	_check "name has no consecutive hyphens (got '$NAME_VALUE')" fail
fi

# Check 12: name matches folder, NFKC-normalized when python3 available.
if command -v python3 > /dev/null 2>&1; then
	NORM_NAME="$(python3 -c "import sys,unicodedata; print(unicodedata.normalize('NFKC', sys.argv[1]))" "$NAME_VALUE" 2> /dev/null || echo "$NAME_VALUE")"
	NORM_DIR="$(python3 -c "import sys,unicodedata; print(unicodedata.normalize('NFKC', sys.argv[1]))" "$SKILL_NAME" 2> /dev/null || echo "$SKILL_NAME")"
else
	NORM_NAME="$NAME_VALUE"
	NORM_DIR="$SKILL_NAME"
fi
if [[ "$NORM_NAME" = "$NORM_DIR" ]]; then
	_check "name matches folder ($SKILL_NAME)" ok
else
	_check "name matches folder (expected $SKILL_NAME, got '$NAME_VALUE')" fail
fi

# Check 13: description field present.
if echo "$FRONTMATTER" | yq -e 'has("description")' - > /dev/null 2>&1; then
	_check "description field present in frontmatter" ok
else
	_check "description field present in frontmatter" fail
fi

# Check 14: description length 1..1024 chars (after trim).
DESC_TRIMMED="$(printf '%s' "$DESC_VALUE" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
DESC_LEN=${#DESC_TRIMMED}
if [[ "$DESC_LEN" -ge 1 && "$DESC_LEN" -le 1024 ]]; then
	_check "description length within 1..1024 chars (got $DESC_LEN)" ok
else
	_check "description length within 1..1024 chars (got $DESC_LEN)" fail
fi

# Check 15: compatibility, if present, is <= 500 chars.
if [[ "$HAS_COMPAT" = "true" ]]; then
	COMPAT_LEN=${#COMPAT_VALUE}
	if [[ "$COMPAT_LEN" -le 500 ]]; then
		_check "compatibility within 500 chars (got $COMPAT_LEN)" ok
	else
		_check "compatibility within 500 chars (got $COMPAT_LEN)" fail
	fi
else
	_check "compatibility within 500 chars (not present, skipped)" ok
fi

# Check 16: frontmatter uses only spec-recognized keys.
RECOGNIZED='name description license compatibility metadata allowed-tools'
UNKNOWN_KEYS=""
while IFS= read -r _key; do
	[[ -z "$_key" ]] && continue
	_known=0
	for _r in $RECOGNIZED; do
		if [[ "$_key" = "$_r" ]]; then
			_known=1
			break
		fi
	done
	[[ "$_known" -eq 0 ]] && UNKNOWN_KEYS="$UNKNOWN_KEYS $_key"
done < <(echo "$FRONTMATTER" | yq -r 'keys | .[]' -)

if [[ -z "$UNKNOWN_KEYS" ]]; then
	_check "frontmatter uses only spec-recognized keys" ok
else
	_check "frontmatter uses only spec-recognized keys (unknown:$UNKNOWN_KEYS)" fail
fi

# Check 17: body under 500 lines.
TOTAL_LINES="$(wc -l < "$SKILL_MD" | tr -d ' ')"
SECOND_DELIM="$(awk '/^---$/{c++; if (c==2) {print NR; exit}}' "$SKILL_MD")"
if [[ -n "$SECOND_DELIM" ]]; then
	BODY_LINES=$((TOTAL_LINES - SECOND_DELIM))
else
	BODY_LINES="$TOTAL_LINES"
fi
if [[ "$BODY_LINES" -lt 500 ]]; then
	_check "body under 500 lines (got $BODY_LINES)" ok
else
	_check "body under 500 lines (got $BODY_LINES)" fail
fi

# Check 18: scripts/ files all executable (or no scripts/).
if [[ -d "$SKILL_DIR/scripts" ]]; then
	NON_EXEC="$(find "$SKILL_DIR/scripts" -type f -not -perm -u+x 2> /dev/null | wc -l | tr -d ' ')"
	if [[ "$NON_EXEC" -eq 0 ]]; then
		_check "scripts/ files all executable" ok
	else
		_check "scripts/ files all executable ($NON_EXEC non-executable)" fail
	fi
else
	_check "scripts/ executability (no scripts/ dir, skipped)" ok
fi

_summary_and_exit
