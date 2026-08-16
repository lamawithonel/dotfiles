#!/usr/bin/env bash
# agent-skills-validate — validate one Agent Skill against the spec.
# https://agentskills.io/specification
#
# Bash-first; uses yq for YAML parsing (pinned in mise.toml).
# python3 is used opportunistically for NFKC normalization on
# the name-vs-folder check and for classifying unrecognized
# frontmatter keys; if python3 is absent both degrade gracefully.
#
# Results are two-tiered.  A FAILURE is a spec violation, or a
# frontmatter key so close to a real one that the author plainly meant
# the real one.  A WARNING is a key some harness honours and every
# other harness drops in silence: portable-skill noise, not a defect.
# Warnings count as passes and never change the exit status.
set -o errexit
set -o nounset
set -o pipefail

# Spec-recognized frontmatter keys.
RECOGNIZED='name description license compatibility metadata allowed-tools'

# Keys no harness rejects but some harness honours.  Spelled correctly
# these are a portability note, not a defect.
HARNESS_KEYS='argument-hint disable-model-invocation user-invocable model'

# Keys that WITHHOLD a capability.  A misspelling here does not degrade
# gracefully: the harness drops the key, the restriction disappears,
# and the skill ends up more exposed than its author wrote it to be.
# Near misses of these are reported as failures with that consequence
# spelled out.
GUARD_KEYS='allowed-tools disable-model-invocation user-invocable'

readonly RECOGNIZED HARNESS_KEYS GUARD_KEYS

PASS=0
FAIL=0
WARN=0
N=0

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

_check() {
	local _desc="$1"
	local _result="$2" # "ok", "warn", or "fail"
	N=$((N + 1))
	case "$_result" in
		ok)
			echo "ok $N - $_desc"
			PASS=$((PASS + 1))
			;;
		warn)
			echo "ok $N - $_desc # WARN"
			PASS=$((PASS + 1))
			WARN=$((WARN + 1))
			;;
		*)
			echo "not ok $N - $_desc"
			FAIL=$((FAIL + 1))
			;;
	esac
}

_summary_and_exit() {
	local _plural='warnings'
	echo "1..$N"
	if [[ "$WARN" -eq 0 ]]; then
		echo "$PASS passed, $FAIL failed"
	else
		[[ "$WARN" -eq 1 ]] && _plural='warning'
		echo "$PASS passed, $FAIL failed, $WARN $_plural"
	fi
	[[ "$FAIL" -eq 0 ]] || exit 1
	exit 0
}

# Resolve the argument to an absolute skill directory, refusing
# package-manager-owned trees.  Location alone does not disqualify a
# skill: hand-authored skills live anywhere, including ~/.agents/skills
# and project source trees.
_resolve_skill_dir() {
	local _arg="$1"
	local _dir=""
	local _repo_root=""

	if [[ "$_arg" == */* || "$_arg" == .* ]]; then
		_dir="$_arg"
	else
		_repo_root="$(git rev-parse --show-toplevel 2> /dev/null || pwd)"
		if [[ -d "$_repo_root/skills/$_arg" ]]; then
			_dir="$_repo_root/skills/$_arg"
		else
			echo "ERROR: skill '$_arg' not found under skills/" >&2
			exit 2
		fi
	fi

	case "$_dir" in
		*apm_modules*)
			echo "upstream-managed skill, not validated: $_dir" >&2
			exit 3
			;;
	esac

	_dir="$(cd "$_dir" 2> /dev/null && pwd)" || {
		echo "ERROR: skill directory not found: $_arg" >&2
		exit 2
	}

	printf '%s\n' "$_dir"
}

# Check 1: SKILL.md or skill.md exists at root.
_check_skill_md_exists() {
	local _candidate=""
	SKILL_MD=""
	for _candidate in SKILL.md skill.md; do
		if [[ -f "$SKILL_DIR/$_candidate" ]]; then
			SKILL_MD="$SKILL_DIR/$_candidate"
			break
		fi
	done

	if [[ -n "$SKILL_MD" ]]; then
		_check "SKILL.md (or skill.md) exists at skill root" ok
		return 0
	fi

	_check "SKILL.md (or skill.md) exists at skill root" fail
	# Without a SKILL.md the rest of the checks are moot.
	_summary_and_exit
}

# Checks 2-5: frontmatter delimiters, YAML validity, mapping shape.
# Each failure here makes every downstream check meaningless, so the
# run ends rather than emitting noise.
_check_frontmatter() {
	local _delim_count=""
	local _parse_err=""
	local _first=""
	local _tag=""

	if head -1 "$SKILL_MD" | grep -q '^---$'; then
		_check "file starts with frontmatter delimiter" ok
	else
		_check "file starts with frontmatter delimiter" fail
	fi

	_delim_count="$(grep -cE '^---$' "$SKILL_MD" || true)"
	if [[ "$_delim_count" -ge 2 ]]; then
		_check "frontmatter closed with second ---" ok
	else
		_check "frontmatter closed with second --- (got $_delim_count delimiters)" fail
		_summary_and_exit
	fi

	FRONTMATTER="$(awk 'BEGIN{c=0} /^---$/{c++; if(c==2) exit; next} c==1' "$SKILL_MD")"

	if _parse_err="$(echo "$FRONTMATTER" | yq '.' - 2>&1 > /dev/null)"; then
		_check "frontmatter parses as valid YAML" ok
	else
		_first="${_parse_err%%$'\n'*}"
		_check "frontmatter parses as valid YAML ($_first)" fail
		_summary_and_exit
	fi

	_tag="$(echo "$FRONTMATTER" | yq 'tag' - 2> /dev/null || echo "")"
	if [[ "$_tag" = "!!map" ]]; then
		_check "frontmatter is a YAML mapping" ok
	else
		_check "frontmatter is a YAML mapping (got ${_tag:-<unknown>})" fail
		_summary_and_exit
	fi
}

# NFKC-normalize when python3 is available; otherwise pass through.
_nfkc() {
	if [[ "$HAS_PYTHON" -eq 0 ]]; then
		printf '%s\n' "$1"
		return 0
	fi
	python3 -c \
		"import sys,unicodedata; print(unicodedata.normalize('NFKC', sys.argv[1]))" \
		"$1" 2> /dev/null || printf '%s\n' "$1"
}

# Checks 6-12: name presence and shape.
#
# TODO(i18n): the upstream skills-ref accepts unicode lowercase letters
# via unicodedata + str.isalnum(); replicating that correctly in bash +
# yq is non-trivial, and hub-local skills are all ASCII today.
# Documented in Known Limitations.
_check_name() {
	local _len=0
	local _lc=""
	local _norm_name=""
	local _norm_dir=""

	if echo "$FRONTMATTER" | yq -e 'has("name")' - > /dev/null 2>&1; then
		_check "name field present in frontmatter" ok
	else
		_check "name field present in frontmatter" fail
	fi

	_len=${#NAME_VALUE}
	if [[ "$_len" -ge 1 && "$_len" -le 64 ]]; then
		_check "name length within 1..64 chars (got $_len)" ok
	else
		_check "name length within 1..64 chars (got $_len)" fail
	fi

	_lc="$(printf '%s' "$NAME_VALUE" | tr '[:upper:]' '[:lower:]')"
	if [[ "$NAME_VALUE" = "$_lc" ]]; then
		_check "name is lowercase" ok
	else
		_check "name is lowercase (got '$NAME_VALUE')" fail
	fi

	if [[ "$NAME_VALUE" =~ ^[a-z0-9-]+$ ]]; then
		_check "name uses only [a-z0-9-]" ok
	else
		_check "name uses only [a-z0-9-] (got '$NAME_VALUE')" fail
	fi

	if [[ "$NAME_VALUE" != -* && "$NAME_VALUE" != *- ]]; then
		_check "name has no leading or trailing hyphen" ok
	else
		_check "name has no leading or trailing hyphen (got '$NAME_VALUE')" fail
	fi

	if [[ "$NAME_VALUE" != *--* ]]; then
		_check "name has no consecutive hyphens" ok
	else
		_check "name has no consecutive hyphens (got '$NAME_VALUE')" fail
	fi

	_norm_name="$(_nfkc "$NAME_VALUE")"
	_norm_dir="$(_nfkc "$SKILL_NAME")"
	if [[ "$_norm_name" = "$_norm_dir" ]]; then
		_check "name matches folder ($SKILL_NAME)" ok
	else
		_check "name matches folder (expected $SKILL_NAME, got '$NAME_VALUE')" fail
	fi
}

# Checks 13-14: description presence and length.
_check_description() {
	local _trimmed=""
	local _len=0

	if echo "$FRONTMATTER" | yq -e 'has("description")' - > /dev/null 2>&1; then
		_check "description field present in frontmatter" ok
	else
		_check "description field present in frontmatter" fail
	fi

	_trimmed="$(printf '%s' "$DESC_VALUE" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
	_len=${#_trimmed}
	if [[ "$_len" -ge 1 && "$_len" -le 1024 ]]; then
		_check "description length within 1..1024 chars (got $_len)" ok
	else
		_check "description length within 1..1024 chars (got $_len)" fail
	fi
}

# Check 15: compatibility, if present, is <= 500 chars.
_check_compatibility() {
	local _len=0

	if [[ "$HAS_COMPAT" != "true" ]]; then
		_check "compatibility within 500 chars (not present, skipped)" ok
		return 0
	fi

	_len=${#COMPAT_VALUE}
	if [[ "$_len" -le 500 ]]; then
		_check "compatibility within 500 chars (got $_len)" ok
	else
		_check "compatibility within 500 chars (got $_len)" fail
	fi
}

# Collect frontmatter keys that are not in the spec.
_unknown_keys() {
	local _key=""
	local _r=""
	local _known=0
	local _unknown=""

	while IFS= read -r _key; do
		[[ -z "$_key" ]] && continue
		_known=0
		for _r in $RECOGNIZED; do
			if [[ "$_key" = "$_r" ]]; then
				_known=1
				break
			fi
		done
		[[ "$_known" -eq 0 ]] && _unknown="$_unknown $_key"
	done < <(echo "$FRONTMATTER" | yq -r 'keys | .[]' -)

	printf '%s\n' "$_unknown"
}

# Classify unrecognized keys as "error" or "warn", one per line.
# Near-miss detection is what separates a harmless extension key from a
# typo the harness silently swallowed.
_key_report() {
	python3 - "$RECOGNIZED $HARNESS_KEYS" "$GUARD_KEYS" "$HARNESS_KEYS" "$1" <<- 'PY'
		import difflib
		import sys

		known = sys.argv[1].split()
		guard = set(sys.argv[2].split())
		harness = set(sys.argv[3].split())

		for key in sys.argv[4].split():
		    if key in harness:
		        print(f"warn\t{key}: harness extension, not in the spec; "
		              f"harnesses that do not know it ignore it silently")
		        continue
		    near = difflib.get_close_matches(key, known, n=1, cutoff=0.8)
		    if not near:
		        print(f"warn\t{key}: unrecognized everywhere, ignored silently")
		    elif near[0] in guard:
		        print(f"error\t{key}: almost certainly a typo for '{near[0]}', "
		              f"which WITHHOLDS a capability -- the key is dropped, the "
		              f"restriction silently disappears, and the skill is more "
		              f"exposed than it was written to be")
		    else:
		        print(f"error\t{key}: almost certainly a typo for '{near[0]}', "
		              f"so the behaviour the author asked for never happens")
	PY
}

# Check 16: frontmatter key spelling and portability.
_check_keys() {
	local _unknown=""
	local _report=""
	local _errors=0

	_unknown="$(_unknown_keys)"
	_unknown="${_unknown# }"

	if [[ -z "$_unknown" ]]; then
		_check "frontmatter uses only spec-recognized keys" ok
		return 0
	fi

	if [[ "$HAS_PYTHON" -eq 0 ]]; then
		_check "frontmatter keys (unknown: $_unknown; python3 absent, unclassified)" warn
		return 0
	fi

	_report="$(_key_report "$_unknown")"
	_errors="$(printf '%s\n' "$_report" | grep -c '^error' || true)"

	if [[ "$_errors" -gt 0 ]]; then
		_check "frontmatter key spelling and portability (unknown: $_unknown)" fail
	else
		_check "frontmatter uses non-spec keys (unknown: $_unknown)" warn
	fi

	printf '%s\n' "$_report" \
		| sed -e 's/^error\t/#   ERROR: /' -e 's/^warn\t/#   WARN:  /'
}

# Check 17: body under 500 lines.
_check_body() {
	local _total=0
	local _second_delim=""
	local _body=0

	_total="$(wc -l < "$SKILL_MD" | tr -d ' ')"
	_second_delim="$(awk '/^---$/{c++; if (c==2) {print NR; exit}}' "$SKILL_MD")"
	if [[ -n "$_second_delim" ]]; then
		_body=$((_total - _second_delim))
	else
		_body="$_total"
	fi

	if [[ "$_body" -lt 500 ]]; then
		_check "body under 500 lines (got $_body)" ok
	else
		_check "body under 500 lines (got $_body)" fail
	fi
}

# Check 18: scripts/ files all executable (or no scripts/).
_check_scripts() {
	local _non_exec=0

	if [[ ! -d "$SKILL_DIR/scripts" ]]; then
		_check "scripts/ executability (no scripts/ dir, skipped)" ok
		return 0
	fi

	_non_exec="$(find "$SKILL_DIR/scripts" -type f -not -perm -u+x 2> /dev/null | wc -l | tr -d ' ')"
	if [[ "$_non_exec" -eq 0 ]]; then
		_check "scripts/ files all executable" ok
	else
		_check "scripts/ files all executable ($_non_exec non-executable)" fail
	fi
}

[[ $# -eq 1 ]] || usage
[[ "$1" = "-h" || "$1" = "--help" ]] && usage

HAS_PYTHON=0
command -v python3 > /dev/null 2>&1 && HAS_PYTHON=1
readonly HAS_PYTHON

SKILL_DIR="$(_resolve_skill_dir "$1")"
SKILL_NAME="$(basename "$SKILL_DIR")"
readonly SKILL_DIR SKILL_NAME

_check_skill_md_exists
_check_frontmatter

# Pull frontmatter values once for the checks that follow.
NAME_VALUE="$(echo "$FRONTMATTER" | yq -r '.name // ""' -)"
DESC_VALUE="$(echo "$FRONTMATTER" | yq -r '.description // ""' -)"
COMPAT_VALUE="$(echo "$FRONTMATTER" | yq -r '.compatibility // ""' -)"
HAS_COMPAT="$(echo "$FRONTMATTER" | yq -r 'has("compatibility")' -)"

_check_name
_check_description
_check_compatibility
_check_keys
_check_body
_check_scripts

_summary_and_exit
