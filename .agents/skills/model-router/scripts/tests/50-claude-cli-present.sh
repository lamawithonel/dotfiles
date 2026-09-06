#!/bin/sh
#
# Is the claude CLI reachable?  This is the reverse external channel --
# the one Pi uses to reach Claude models.  It also backs `claude -p`
# shell-outs from any harness.

set -o nounset

if ! command -v claude > /dev/null 2>&1; then
	echo 'claude not on PATH.'
	echo 'Pi cannot reach Claude models from this host, and no headless'
	echo 'claude -p shell-out will run.'
	exit 1
fi

echo "claude at $(command -v claude)"
echo "version $(claude --version 2>&1 | head -1)"
exit 0
