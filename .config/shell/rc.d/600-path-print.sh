#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# 600-path-print.sh
#
# Print final PATH for debugging
# Category: 600-699 Final setup and local overrides
# Note: Uses Bash syntax but is compatible with Zsh

# Print the PATH variable to make it easy to see what's in there
if [ -n "$BASH_VERSION" ] || [ -n "$ZSH_VERSION" ]; then
	# Use printf to handle IFS properly
	printf 'PATH=%s\n' "$PATH"
fi
