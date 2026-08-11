#!/usr/bin/env sh
# probe-claude-models.sh [model-id...]
#
# Validates which Claude model ids this host's Claude Code deployment
# actually accepts, by dispatching a one-word prompt per candidate.
# Truth layer of the tiered discovery workflow (see
# ../references/discover-claude-models.md).
#
# MUST run OUTSIDE a sandboxed tool call: sandboxed Bash blocks the
# CLI's network.  Run it in a plain terminal, or from a Claude Code
# prompt with the `!` prefix.
#
# Candidates: CLI args if given; otherwise the union of
#   - deployment cache: ~/.claude.json additionalModelOptionsCache /
#     modelAccessCache / orgModelDefaultCache (undocumented;
#     best-effort, schema varies across versions)
#   - seed: ids already present in ~/.agents/models.json with a
#     native claude-code channel
#
# Results: JSON at ~/.agents/.local/state/model-router/probe.json
# A session then reads that file to update models.json.

set -o nounset
# errexit intentionally off: probing EXPECTS failures; every fallible
# call's exit status is inspected explicitly.

OUT_DIR="${HOME}/.agents/.local/state/model-router"
OUT="${OUT_DIR}/probe.json"
mkdir -p "$OUT_DIR"

_candidates() {
	if [ "$#" -gt 0 ]; then
		printf '%s\n' "$@"
		return
	fi
	# deployment cache (best-effort; keys differ across CLI versions)
	jq -r '
		(.additionalModelOptionsCache[]?.value // empty),
		(.modelAccessCache[]? // empty),
		(.orgModelDefaultCache // empty)
	' "${HOME}/.claude.json" 2> /dev/null | grep -v '^null$' || true
	# seed from the host registry
	jq -r '.models[] | select(.execution."claude-code".channel == "native")
	       | .aliases[]? // .id' "${HOME}/.agents/models.json" 2> /dev/null || true
}

_probe_one() {
	_id="$1"
	# --effort low keeps probes fast; retry without it on CLIs too old
	# to know the flag (an unknown-flag error must not read as
	# "model not entitled").
	_err=$(MAX_THINKING_TOKENS=0 claude -p --effort low --model "$_id" \
		'Reply with exactly: ok' 2>&1 > /dev/null)
	_rc=$?
	case "$_err" in
		*'unknown option'* | *'unrecognized'* | *'Unexpected argument'*)
			_err=$(MAX_THINKING_TOKENS=0 claude -p --model "$_id" \
				'Reply with exactly: ok' 2>&1 > /dev/null)
			_rc=$?
			;;
	esac
	if [ "$_rc" -eq 0 ]; then
		echo 'ok'
	else
		printf 'error: %s\n' "$(printf '%s' "$_err" | head -c 200 | tr '\n\042' ' _')"
	fi
	unset _id _err _rc
}

_emit_results() {
	printf '{\n  "probed_at": "%s",\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
	printf '  "claude_version": "%s",\n  "results": {\n' \
		"$(claude --version 2> /dev/null | head -1)"
	_first=1
	_candidates "$@" | sort -u | while IFS= read -r _cand; do
		[ -n "$_cand" ] || continue
		_result=$(_probe_one "$_cand")
		[ "$_first" -eq 1 ] || printf ',\n'
		_first=0
		printf '    "%s": "%s"' "$_cand" "$_result"
		printf '%s: %s\n' "$_cand" "$_result" >&2
	done
	printf '\n  }\n}\n'
}

TMP="${OUT}.tmp"
_emit_results "$@" > "$TMP"
if jq . "$TMP" > /dev/null 2>&1; then
	mv "$TMP" "$OUT"
	echo "results written to $OUT" >&2
else
	echo "ERROR: malformed output left at $TMP" >&2
	exit 1
fi
