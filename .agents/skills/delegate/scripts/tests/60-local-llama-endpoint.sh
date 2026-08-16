#!/bin/sh
#
# Is the local llama.cpp endpoint answering?  Local models are the one
# external-channel class with no egress and no per-token cost, so when
# they are up they are usually the right answer for cheap bulk work.

set -o nounset

ENDPOINT="${DELEGATE_TEST_LLAMA_URL:-http://localhost:8080/v1/models}"

command -v curl > /dev/null 2>&1 || {
	echo 'curl absent'
	exit 77
}

code="$(curl -s -m 5 -o /dev/null -w '%{http_code}' "${ENDPOINT}" 2> /dev/null)"

case "${code}" in
	200)
		echo "local endpoint answering at ${ENDPOINT}"
		exit 0
		;;
	401 | 403)
		echo "local endpoint up at ${ENDPOINT} but rejected us (${code})."
		echo 'The server is running; the credential or header is wrong.'
		exit 1
		;;
	000)
		echo "nothing listening at ${ENDPOINT}."
		echo 'Local llama-cpp models are unreachable; route elsewhere.'
		exit 1
		;;
esac

echo "unexpected status ${code} from ${ENDPOINT}"
exit 1
