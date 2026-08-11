#!/bin/sh
# gh_recover.sh -- drift remediation.  When compat_probe.sh reports
# drift, re-install the pinned toolchain via bootstrap_work.sh (gh
# fetch + fail-closed integrity ladder + zero-network mise
# registration), then re-run the probe as the closing check.
#
# NEVER `mise install`: it is sandboxed at work, blocked on the
# release-asset CDN, and both workarounds are forbidden (R1).
#
# Runs agent-issued or manually in a plain terminal (R5) -- same
# receipt either way: vcs-compat-recover/1 at
# ~/.agents/.local/state/vcs-workflow/compat-recover.json
# Exit: 0 recovered (probe green), 1 not recovered.

set -o nounset

OUT_DIR="$HOME/.agents/.local/state/vcs-workflow"
OUT="$OUT_DIR/compat-recover.json"
_scriptdir=$(dirname "$0")

"$_scriptdir/bootstrap_work.sh" "$@"
_boot_rc=$?

"$_scriptdir/compat_probe.sh"
_probe_rc=$?

if [ "$_boot_rc" -eq 0 ] && [ "$_probe_rc" -eq 0 ]; then
	_verdict='recovered'
else
	_verdict='not-recovered'
fi

mkdir -p "$OUT_DIR"
cat > "$OUT.tmp" <<- EOF
	{
	  "schema": "vcs-compat-recover/1",
	  "recovered_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
	  "bootstrap_exit": $_boot_rc,
	  "probe_exit": $_probe_rc,
	  "verdict": "$_verdict"
	}
EOF
mv "$OUT.tmp" "$OUT"

printf 'RECOVER-%s bootstrap=%d probe=%d receipt=%s\n' \
	"$(printf '%s' "$_verdict" | tr '[:lower:]-' '[:upper:]_')" \
	"$_boot_rc" "$_probe_rc" "$OUT"
[ "$_verdict" = 'recovered' ]
