#!/bin/sh
#
# Is the pi CLI reachable?  Without it, every registry model whose
# claude-code channel is external is ineligible on this host.

set -o nounset

if ! command -v pi > /dev/null 2>&1; then
	echo "pi not on PATH."
	echo "Every external-channel model is ineligible here; route to a"
	echo "native model or back inline."
	exit 1
fi

echo "pi at $(command -v pi)"
echo "version $(pi --version 2>&1 | head -1)"
exit 0
