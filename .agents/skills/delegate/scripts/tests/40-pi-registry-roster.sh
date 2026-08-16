#!/bin/sh
#
# Does every external-channel model in the registry actually exist in
# pi's enabled roster?  Registry drift shows up here as a dispatch that
# fails only for one model, long after the roster changed.

set -o nounset

REGISTRY="${HOME}/.agents/models.json"
PI_SETTINGS="${HOME}/.pi/agent/settings.json"

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

missing=''
checked=0

for id in $(jq -r '
	.models[]
	| select(.execution["claude-code"].channel == "external")
	| select(.public_id != null)
	| .id
' "${REGISTRY}"); do
	case "${id}" in
		local/*) continue ;;
	esac

	checked=$((checked + 1))
	jq -e --arg m "openrouter/${id}" \
		'.enabledModels | index($m)' "${PI_SETTINGS}" > /dev/null 2>&1 \
		|| missing="${missing} ${id}"
done

if [ -n "${missing}" ]; then
	echo 'in the registry as external, but absent from pi enabledModels:'
	echo "${missing}"
	echo 'Dispatch to these will fail even though pi itself works.'
	exit 1
fi

echo "${checked} external registry models all present in pi enabledModels"
exit 0
