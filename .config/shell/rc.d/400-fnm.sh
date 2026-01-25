#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# 400-fnm.sh
#
# Fast Node Manager initialization
# Category: 400-499 Language/tool environment managers
# Note: Uses Bash syntax but is compatible with Zsh

if command -v fnm >/dev/null 2>&1; then
	PATH="$(echo "$PATH" | sed -E 's,(^|:)/[^:]+/fnm_multishells/[0-9_]+/bin(:|$),,g')"
	# fnm env sets up the environment and includes completion setup
	if [ -n "$BASH_VERSION" ]; then
		eval "$(fnm env --use-on-cd --shell bash)"
	elif [ -n "$ZSH_VERSION" ]; then
		eval "$(fnm env --use-on-cd --shell zsh)"
	fi
fi
