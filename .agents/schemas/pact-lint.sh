#!/usr/bin/env bash
# pact-lint.sh -- lint PACT documents before you send them.
#
# Usage: pact-lint.sh [-h|--help] FILE...
#
# Checks, per file:
#   1. The file is well-formed XML.
#   2. The root element is a known PACT document type.
#   3. Every element that the type requires is present (one line each).
#      A charter, a consultation, and an agent definition require a
#      persona.  The schema checks its name: non-blank, no braces.
#   4. The file validates against the PACT schema for its namespace.
#   5. Rules that XSD 1.0 cannot state: a critical constraint carries
#      required="true"; no unicode em-dash; a worker brief carries no
#      old guard text; a relay quote matches the freeze file that its
#      source names.
#
# A file may start with YAML frontmatter (a harness .md file).  The
# frontmatter is skipped and line numbers stay true.  Leave out the XML
# declaration in such a file.
#
# Validation is ADVISORY.  A writer runs this script before it sends a
# message.  A receiver never rejects a message because it fails here.
#
# Offline.  The script reads the schemas that sit beside it and runs
# xmllint with --nonet.  It never fetches anything.
#
# Exit codes:
#   0  every file is valid (no output)
#   1  at least one file has a problem (one line per problem)
#   2  usage error, or an internal failure (bad schema, missing tool)
#
# Output line: FILE:LINE: message  (LINE is left out when unknown).
#
# Environment: TMPDIR sets the scratch location.

set -o errexit
set -o nounset
set -o pipefail

readonly NS_CORE='urn:pact:taxonomy:1.0'
readonly NS_ORG='urn:pact:org:1.0'
SELF_NAME="$(basename "$0")" && readonly SELF_NAME
SCHEMA_DIR="$(dirname -- "$(readlink -f -- "$0")")" && readonly SCHEMA_DIR

_TMP=''
_WORK=''
_OUT=''
_FILE=''
_NS=''
_LOCAL=''

_usage() {
	cat <<- EOF
		Usage: ${SELF_NAME} [-h|--help] FILE...

		Lint PACT documents.  Checks well-formedness, the document type,
		required elements, the XSD schema, and a few rules that XSD cannot
		state.  Works offline.  A relay quote must equal the text of the freeze
		file that its source names, with runs of whitespace collapsed.

		This check is advisory.  A writer runs it before sending.  A
		receiver never rejects a message because it fails validation.

		Exit codes:
		  0  every file is valid
		  1  a file has a problem (one output line per problem)
		  2  usage error or internal failure
	EOF
}

_fail() {
	echo "${SELF_NAME}: $*" >&2
	exit 2
}

# shellcheck disable=SC2329  # invoked through trap
_cleanup() {
	if [ -n "$_TMP" ]; then
		rm -rf "$_TMP"
	fi
}

# _problem LINE MESSAGE -- record one problem for the current file.
_problem() {
	if [ -n "$1" ]; then
		printf '%s:%s: %s\n' "$_FILE" "$1" "$2" >> "$_OUT"
	else
		printf '%s: %s\n' "$_FILE" "$2" >> "$_OUT"
	fi
}

# _strip_frontmatter FILE -- print FILE with leading YAML frontmatter
# replaced by blank lines, so line numbers stay true.
_strip_frontmatter() {
	awk '
		NR == 1 && /^---[ \t]*$/ { infm = 1; print ""; next }
		infm { print ""; if (/^---[ \t]*$/) infm = 0; next }
		{ print }
	' "$1"
}

# _xp EXPR -- evaluate an XPath expression on the work copy.
_xp() {
	xmllint --nonet --xpath "$1" "$_WORK" 2> /dev/null || true
}

_root_line() {
	grep -n -m 1 -E "<([A-Za-z0-9_.-]+:)?${_LOCAL}([[:space:]/>]|\$)" "$_WORK" \
		| cut -d: -f1 || true
}

# _check_wellformed -- return 1 and record the first parser error.
_check_wellformed() {
	local rc=0 first
	xmllint --noout --nonet "$_WORK" 2> "$_TMP/wf.txt" || rc=$?
	[ "$rc" -eq 0 ] && return 0
	first="$(grep -m 1 -E 'doc\.xml:[0-9]+: .*error : ' "$_TMP/wf.txt" || true)"
	if [ -z "$first" ]; then
		_problem '' 'not well-formed XML'
		return 1
	fi
	_problem "$(printf '%s' "$first" | sed -E 's/^.*doc\.xml:([0-9]+): .*/\1/')" \
		"not well-formed XML: $(printf '%s' "$first" | sed -E 's/^.*error : //')"
	return 1
}

# _known_type -- return 0 when the root is a PACT document type.
_known_type() {
	case "${_NS}|${_LOCAL}" in
		"${NS_CORE}|pact" | "${NS_CORE}|prompt" | "${NS_CORE}|message" | "${NS_CORE}|agent-definition") return 0 ;;
		"${NS_ORG}|charter" | "${NS_ORG}|worker-brief" | "${NS_ORG}|consultation" | "${NS_ORG}|question") return 0 ;;
		"${NS_ORG}|freeze" | "${NS_ORG}|relay" | "${NS_ORG}|ruling" | "${NS_ORG}|escalation") return 0 ;;
	esac
	return 1
}

# _required_for TYPE -- print the required child elements of TYPE.
# c:NAME is a core element, o:NAME is a profile element.  Keep this
# table in step with the xs:all lists in the two schemas.
_required_for() {
	sed -n -e "s/^${1} //p" <<- 'EOF'
		prompt c:objective
		message c:summary
		agent-definition c:persona c:role c:instructions
		charter c:persona o:position o:supervisor c:objective o:milestones o:model o:onboarding
		worker-brief c:role c:objective c:tasks o:verification
		consultation c:persona o:position o:creator c:objective o:ends-when o:model
		question o:from o:ask
		freeze o:issuer o:reason o:scope o:end o:lifter o:covers-dispatch
		relay o:relayer o:source o:quote
		ruling o:issuer o:decision o:applies-to
		escalation o:from o:to o:problem o:request
	EOF
}

_check_required() {
	local line item ns name count
	line="$(_root_line)"
	for item in $(_required_for "$_LOCAL"); do
		name="${item#?:}"
		ns="$NS_CORE"
		[ "${item%%:*}" = 'o' ] && ns="$NS_ORG"
		count="$(_xp "count(/*/*[local-name()='${name}' and namespace-uri()='${ns}'])")"
		if [ "${count:-0}" = '0' ]; then
			_problem "$line" "${_LOCAL}: missing required element <${name}>"
		fi
	done
}

# _filter_schema_errors -- turn xmllint schema errors into LINE<TAB>MSG.
# Drops "missing child" errors on the root (the required-element check
# names each one) and the second line of a double type error.
_filter_schema_errors() {
	sed -n -E \
		-e 's/\{(urn|http)[^}]*\}//g' \
		-e 's|^.*doc\.xml:([0-9]+): Schemas validity error : |\1\t|p' "$1" \
		| awk -F '\t' -v root="$_LOCAL" '
			$2 ~ ("^Element \047" root "\047: Missing child element") { next }
			$2 ~ /is not a valid value of the atomic type/ && prev_ln == $1 && prev_facet { next }
			{
				prev_ln = $1
				prev_facet = ($2 ~ /\[facet/)
				msg = $2
				if (msg ~ /attribute \047priority\047/ && msg ~ /\047MUST\047/) {
					msg = msg " Use priority=\"critical\" with required=\"true\"."
				}
				print $1 "\t" msg
			}'
}

_check_schema() {
	local schema="${SCHEMA_DIR}/pact-1.0.xsd" rc=0 ln msg
	[ "$_NS" = "$NS_ORG" ] && schema="${SCHEMA_DIR}/pact-org-1.0.xsd"
	xmllint --noout --nonet --schema "$schema" "$_WORK" > "$_TMP/xsd.txt" 2>&1 || rc=$?
	case "$rc" in
		0) return 0 ;;
		3 | 4) ;;
		*) _fail "xmllint failed on schema ${schema} (status ${rc})" ;;
	esac
	while IFS=$'\t' read -r ln msg; do
		_problem "$ln" "$msg"
	done < <(_filter_schema_errors "$_TMP/xsd.txt")
}

_check_critical() {
	local n
	n="$(_xp "count(//*[@priority='critical'][not(@required='true')])")"
	if [ "${n:-0}" != '0' ]; then
		_problem '' "${n} element(s) with priority=\"critical\" lack required=\"true\""
	fi
}

_check_em_dash() {
	local hit
	while IFS=: read -r hit _; do
		_problem "$hit" 'em-dash found; write two ASCII hyphens (--)'
	done < <(grep -n -F $'\xe2\x80\x94' "$_FILE" || true)
}

_check_guards() {
	local ln word
	[ "$_LOCAL" = 'worker-brief' ] || return 0
	while IFS=: read -r ln word; do
		_problem "$ln" "guard text '${word}' does not belong in a worker brief"
	done < <(grep -n -o -E 'STALL WATCHDOG|SCOPE LIMIT|RECEIPT CONTRACT|RAW QUOTES|[Ff]inal [Rr]eport [Cc]ontract' "$_WORK" || true)
}

# _freeze_text FILE -- print the text a relay quotes from a freeze file.
_freeze_text() {
	local out='' name label val
	for name in reason scope end lifter covers-dispatch; do
		val="$(xmllint --nonet --xpath "string(/*/*[local-name()='${name}'])" "$1" 2> /dev/null || true)"
		label="${name^}"
		[ "$name" = 'covers-dispatch' ] && label='Covers dispatch'
		out+="${label}: ${val} "
	done
	printf '%s' "$out"
}

# _squash -- collapse runs of whitespace and trim the ends.
_squash() {
	tr -s '[:space:]' ' ' | sed -E 's/^ //; s/ $//'
}

# _check_relay -- the quote must match the freeze file named in source.
_check_relay() {
	local src quote line frz
	[ "$_LOCAL" = 'relay' ] || return 0
	src="$(_xp "string(/*/*[local-name()='source'])" | _squash)"
	quote="$(_xp "string(/*/*[local-name()='quote'])")"
	[ -n "$src" ] && [ -n "$quote" ] || return 0
	line="$(grep -n -m 1 -E '<([A-Za-z0-9_.-]+:)?quote[ >]' "$_WORK" | cut -d: -f1 || true)"
	case "$src" in
		/*) frz="$src" ;;
		*) frz="$(dirname -- "$_FILE")/${src}" ;;
	esac
	if [ ! -f "$frz" ]; then
		_problem "$line" "relay source not found: ${src}"
	elif [ "$(printf '%s' "$quote" | _squash)" != "$(_freeze_text "$frz" | _squash)" ]; then
		_problem "$line" "relay quote differs from ${src}"
	fi
}

# _lint_file FILE -- print problems for FILE.  Return 1 if any.
_lint_file() {
	_FILE="$1"
	_WORK="$_TMP/doc.xml"
	_OUT="$_TMP/out.txt"
	: > "$_OUT"
	_strip_frontmatter "$_FILE" > "$_WORK"
	if _check_wellformed; then
		_NS="$(_xp 'namespace-uri(/*)')"
		_LOCAL="$(_xp 'local-name(/*)')"
		_lint_typed
	fi
	_check_em_dash
	[ -s "$_OUT" ] || return 0
	cat "$_OUT"
	return 1
}

_lint_typed() {
	if ! _known_type; then
		_problem "$(_root_line)" "unknown document type <${_LOCAL}> (namespace '${_NS}')"
		return 0
	fi
	_check_required
	_check_schema
	_check_critical
	_check_guards
	_check_relay
}

main() {
	local -a files=()
	local f status=0
	while [ "$#" -gt 0 ]; do
		case "$1" in
			-h | --help)
				_usage
				exit 0
				;;
			--)
				shift
				files+=("$@")
				break
				;;
			-?*)
				_usage >&2
				_fail "unknown option: $1"
				;;
			*) files+=("$1") ;;
		esac
		shift
	done
	if [ "${#files[@]}" -eq 0 ]; then
		_usage >&2
		_fail 'no FILE given'
	fi
	for f in "${files[@]}"; do
		[ -r "$f" ] && [ -f "$f" ] || _fail "cannot read file: ${f}"
	done
	command -v xmllint > /dev/null 2>&1 || _fail 'xmllint is not in PATH'
	trap _cleanup EXIT INT TERM HUP
	_TMP="$(mktemp -d "${TMPDIR:-/tmp}/pact-lint.XXXXXX")"
	for f in "${files[@]}"; do
		_lint_file "$f" || status=1
	done
	exit "$status"
}

main "$@"
