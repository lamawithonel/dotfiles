#!/usr/bin/env bash
#
# Claude Code status line.  Latency-critical: repainted on every
# prompt, so the whole pipeline is exactly two forks -- one jq for
# all JSON parsing and formatting, one git for the branch.
#
# Format:
#	[<model> / <effort>] 📁 <cwd> | <git-branch> | <light> Context: <used%> (<usedK>/<totalK>)

set -o errexit
set -o nounset
set -o pipefail

# Emits three lines: raw cwd (for git), the prefix segment, and the
# context segment.
# shellcheck disable=SC2016  # $-names inside are jq variables, not shell
STATUS_FILTER='
def k: (. / 100 | round) as $x | "\($x / 10 | floor).\($x % 10)k";
env.HOME as $h
| (.model.display_name
	+ (if (.effort.level // "") != "" then " / \(.effort.level)" else "" end)
) as $model
| .workspace.current_dir as $cwd
| (if $cwd == $h then "~"
	elif $cwd | startswith($h + "/") then "~\($cwd | ltrimstr($h))"
	else $cwd
	end) as $dir
| (.context_window.used_percentage // null) as $p
| (if $p == null then "🟢 Context: n/a"
	else
		(if $p > 75 then "🚨" elif $p > 65 then "⚠️" else "🟢" end) as $light
		| (.context_window.total_input_tokens // null) as $u
		| (.context_window.context_window_size // null) as $t
		| (if $u != null and $t != null
			then "\($light) Context: \($p | round)% (\($u | k)/\($t | k))"
			else "\($light) Context: \($p | round)%"
			end)
	end) as $ctx
| $cwd, "[\($model)] 📁 \($dir)", $ctx
'
readonly STATUS_FILTER

mapfile -t _fields < <(jq -r "$STATUS_FILTER")

_branch="$(git -C "${_fields[0]}" --no-optional-locks \
	rev-parse --abbrev-ref HEAD 2> /dev/null || true)"

_line="${_fields[1]}"
if [ -n "$_branch" ]; then
	_line="${_line} | ${_branch}"
fi
printf '%s\n' "${_line} | ${_fields[2]}"
