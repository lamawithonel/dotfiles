#!/usr/bin/env sh
# lint-shell.sh -- PostToolUse hook: run the static-check battery from
# ~/.agents/rules/shell.md on every edited shell script.
#
# Convenience layer only.  Some environments restrict hooks entirely,
# so the rules file remains the authority; this hook just catches
# lapses early where hooks do run.  It is read-only (analyzes the
# edited file, changes nothing) and every missing tool skips silently.
# Exit 2 feeds findings back to the model via stderr.

set -o nounset

_file=$(jq -r '.tool_input.file_path // empty' 2> /dev/null)
case "$_file" in
	*.sh | *.bash) [ -f "$_file" ] || exit 0 ;;
	*) exit 0 ;;
esac

_fail=0
_report() {
	printf '== %s ==\n%s\n' "$1" "$2" >&2
	_fail=1
}

# Dialect comes from the shebang, not the extension.
case "$(head -n 1 "$_file")" in
	*bash*) _dialect='bash' ;;
	*) _dialect='sh' ;;
esac

_out=$("$_dialect" -n "$_file" 2>&1) || _report "$_dialect -n" "$_out"

if command -v shellcheck > /dev/null 2>&1; then
	_out=$(shellcheck "$_file" 2>&1) || _report shellcheck "$_out"
fi

if command -v shfmt > /dev/null 2>&1; then
	_out=$(shfmt -d -bn -ci -sr -kp "$_file" 2>&1) || _report 'shfmt -d' "$_out"
fi

if [ "$_dialect" = 'sh' ] && command -v checkbashisms > /dev/null 2>&1; then
	_out=$(checkbashisms "$_file" 2>&1) || _report checkbashisms "$_out"
fi

_sm=$(command -v shellmetrics 2> /dev/null) \
	|| _sm="${HOME}/.local/share/mise/installs/http-shellmetrics/main/shellmetrics"
if [ -x "$_sm" ]; then
	_out=$("$_sm" --csv "$_file" 2> /dev/null | awk -F, '
		NR == 1 { next }
		{ gsub(/"/, "", $2) }
		$2 == "<begin>" || $2 == "<end>" { next }
		{ n++; sum += $5 }
		$5 > 10 { printf "%s: CCN %s (limit 10; case-statement exemption to 16 may apply)\n", $2, $5 }
		END { if (n && sum / n > 8) printf "file CCN average %.2f (limit 8)\n", sum / n }
	')
	[ -n "$_out" ] && _report shellmetrics "$_out"
fi

if [ "$_fail" -ne 0 ]; then
	printf 'Static checks failed for %s (see shell.md).\n' "$_file" >&2
	exit 2
fi
exit 0
