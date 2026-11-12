#!/bin/sh
#
# Does every enabled pi-harness model in this host's pi-zdr roster (registry
# v4: hosts[host].roster[id] with harness "pi" and "pi-zdr" in rosters) appear
# in pi's enabledModels?  Registry drift shows up here as a dispatch that
# fails only for one model, long after the roster changed.
#
# Env: MODEL_ROUTER_HOST, MODEL_ROUTER_REGISTRY, MODEL_ROUTER_PI_SETTINGS.
# Exit: 0 all present, 1 drift, 77 skipped.

set -o nounset

REGISTRY="${MODEL_ROUTER_REGISTRY:-${HOME}/.agents/model-benchmarks.json}"
HOST="${MODEL_ROUTER_HOST:-$(hostname -s)}"
PI_SETTINGS="${MODEL_ROUTER_PI_SETTINGS:-${HOME}/.pi/agent/settings.json}"

command -v jq > /dev/null 2>&1 || {
	echo 'jq absent'
	exit 77
}
[ -r "${REGISTRY}" ] || {
	echo "no registry at ${REGISTRY}"
	exit 77
}
[ -r "${PI_SETTINGS}" ] || {
	echo "no pi settings at ${PI_SETTINGS}"
	exit 77
}

jq -e '.schema_version == 4' "${REGISTRY}" > /dev/null 2>&1 || {
	echo 'registry is not schema v4; skipping'
	exit 77
}

missing=''
checked=0

for ref in $(jq -r --arg h "${HOST}" '
	.hosts[$h].roster // {}
	| to_entries[]
	| select(.value.harness == "pi")
	| select(.value.enabled == true)
	| select((.value.rosters // []) | index("pi-zdr"))
	| .value.model_ref
	| select(. != null)
' "${REGISTRY}"); do
	checked=$((checked + 1))
	jq -e --arg m "${ref}" \
		'.enabledModels | index($m)' "${PI_SETTINGS}" > /dev/null 2>&1 \
		|| missing="${missing} ${ref}"
done

if [ "${checked}" -eq 0 ]; then
	echo "no pi-zdr roster entries for host ${HOST}; skipping"
	exit 77
fi

if [ -n "${missing}" ]; then
	echo 'in the pi-zdr roster, but absent from pi enabledModels:'
	echo "${missing}"
	echo 'Dispatch to these will fail even though pi itself works.'
	exit 1
fi

echo "${checked} pi-zdr roster models all present in pi enabledModels"
exit 0
