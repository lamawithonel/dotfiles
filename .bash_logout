#!/usr/bin/env bash

# This file is only for Bash.  Exit if the shell is NOT Bash.
[ -n "$BASH_VERSION" ] || exit 1

if [ -x "$XDG_CONFIG_HOME/plasma-workspace/shutdown/secrets-agents.sh" ]; then
	source "${XDG_CONFIG_HOME}/plasma-workspace/shutdown/secrets-agents.sh"
fi

if [ $SHLVL -eq 1 ]; then
	clear
	tput E3 >&/dev/null || echo -ne "\033[3J" >&/dev/null
	command -v sudo &> /dev/null && sudo -k
fi

# vim:foldmethod=marker
# vi:ts=4:sw=4:noexpandtab
