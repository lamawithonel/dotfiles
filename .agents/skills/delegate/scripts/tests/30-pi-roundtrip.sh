#!/bin/sh
#
# Does a real pi round-trip come back?  This is the only case that
# spends tokens, and the only one that proves the channel end to end.

set -o nounset

command -v pi > /dev/null 2>&1 || {
	echo 'pi absent'
	exit 77
}

MODEL="${DELEGATE_TEST_PI_MODEL:-openrouter/z-ai/glm-5.2}"
TIMEOUT="${DELEGATE_TEST_TIMEOUT:-90}"
SENTINEL='PI-ROUNDTRIP-OK'

out="$(timeout "${TIMEOUT}" pi --model "${MODEL}" \
	-p "Reply with exactly: ${SENTINEL}" --no-session 2>&1)"
rc=$?

case "${out}" in
	*"${SENTINEL}"*)
		echo "round-trip ok on ${MODEL}"
		exit 0
		;;
esac

[ "${rc}" -eq 124 ] && {
	echo "timed out after ${TIMEOUT}s on ${MODEL}"
	echo 'Raise DELEGATE_TEST_TIMEOUT, or suspect blocked egress.'
	exit 1
}

echo "no sentinel from ${MODEL} (rc=${rc})"
echo 'first 200 bytes of output:'
printf '%s' "${out}" | head -c 200
echo
exit 1
