#!/bin/sh
#
# PreToolUse hook: deny Agent calls that name no model or no effort.
#
# Reads the hook JSON on stdin.  Denies an Agent call whose tool_input.model
# or tool_input.effort is missing, not a string, or blank after trimming
# spaces, tabs, and newlines, unless subagent_type is "fork" (forks inherit
# the parent model and effort).  A missing model is reported first.
# Every other well-formed input is allowed.
#
# Input must be exactly one JSON object whose tool_input is an object.
# Anything else (empty, concatenated objects, a non-object top level, or a
# non-object tool_input) is malformed: the hook allows the call and warns on
# stderr.  The jq and python3 paths return the same verdict for every case.
#
# JSON parsing uses jq when present, else python3 (stdlib only).  With
# neither tool, the hook allows the call and warns on stderr: this guard
# fails open, and the model-selection skill text is the primary control.
#
# Exit codes: 0 always.  A deny prints the PreToolUse decision JSON on stdout.

set -o nounset

readonly DENY_REASON='Agent call has no model.  Run ~/.agents/skills/model-selection/scripts/score.py --pick --band <band> and pass its model_param as model and its effort as effort.'
readonly EFFORT_REASON='Agent call has no effort.  Run ~/.agents/skills/model-selection/scripts/score.py --pick --band <band> and pass its model_param as model and its effort as effort.'

_warn() {
	echo "require-agent-model: warning: $*" >&2
}

_verdict_jq() {
	printf '%s' "$1" | jq -r -s '
		if length != 1 then "malformed"
		else .[0] as $d
		| if ($d | type) != "object" then "malformed"
		elif ($d.tool_input | type) != "object" then "malformed"
		elif $d.tool_name != "Agent" then "allow"
		elif $d.tool_input.subagent_type == "fork" then "allow"
		elif ($d.tool_input.model | type) != "string" then "deny"
		elif ($d.tool_input.model | gsub("^[ \t\n\r]+|[ \t\n\r]+$"; "")) == "" then "deny"
		elif ($d.tool_input.effort | type) != "string" then "deny-effort"
		elif ($d.tool_input.effort | gsub("^[ \t\n\r]+|[ \t\n\r]+$"; "")) == "" then "deny-effort"
		else "allow" end
		end
	' 2> /dev/null
}

_verdict_python() {
	printf '%s' "$1" | python3 -I -c '
import json
import sys

WHITESPACE = " \t\n\r"

try:
	data = json.load(sys.stdin)
except ValueError:
	print("malformed")
	sys.exit(0)
if not isinstance(data, dict):
	print("malformed")
	sys.exit(0)
tool_input = data.get("tool_input")
if not isinstance(tool_input, dict):
	print("malformed")
	sys.exit(0)
if data.get("tool_name") != "Agent" or tool_input.get("subagent_type") == "fork":
	print("allow")
	sys.exit(0)
def blank(value):
	return not isinstance(value, str) or value.strip(WHITESPACE) == ""

if blank(tool_input.get("model")):
	print("deny")
elif blank(tool_input.get("effort")):
	print("deny-effort")
else:
	print("allow")
' 2> /dev/null
}

input=''
verdict=''
reason=''

if command -v jq > /dev/null 2>&1; then
	input="$(cat)"
	verdict="$(_verdict_jq "${input}")" || verdict='malformed'
elif command -v python3 > /dev/null 2>&1; then
	input="$(cat)"
	verdict="$(_verdict_python "${input}")" || verdict='malformed'
else
	_warn 'neither jq nor python3 found; allowing the call without a model check'
	exit 0
fi

case "${verdict}" in
	deny | deny-effort)
		[ "${verdict}" = 'deny' ] && reason="${DENY_REASON}" || reason="${EFFORT_REASON}"
		printf '%s\n' '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "'"${reason}"'"}}'
		;;
	allow)
		;;
	*)
		# Covers "malformed" and any output that is not one clean verdict,
		# such as a multi-line result, so a bad call is never passed silently.
		_warn 'malformed hook input; allowing the call'
		;;
esac

exit 0
