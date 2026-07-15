#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
#
#----------------------------------------------------------------------
# Tool integrations: Mise, fnox, and pitchfork
#
# All three activations are eager for the same reason: each one
# installs prompt and/or directory-change hooks that real usage
# depends on (project-local tool versions and environment for mise,
# secrets following the current directory for fnox, daemon
# supervision for pitchfork).  A lazy wrapper would silently skip
# those hooks in every shell where the tool is never invoked
# directly, so activation runs at startup.  Completions for fnox and
# pitchfork are handled separately, in 70-completions.sh.

if [ -n "$BASH_VERSION" ]; then
	_shell_name=bash
elif [ -n "$ZSH_VERSION" ]; then
	_shell_name=zsh
fi

if [ -n "$_shell_name" ]; then
	if command -v mise > /dev/null 2>&1; then
		eval "$(mise activate "$_shell_name")"
	fi

	if command -v fnox > /dev/null 2>&1; then
		eval "$(fnox activate "$_shell_name")"
	fi

	if command -v pitchfork > /dev/null 2>&1; then
		eval "$(pitchfork activate "$_shell_name")"
	fi
fi

unset _shell_name
