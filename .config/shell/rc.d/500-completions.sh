#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# 500-completions.sh
#
# Tool completions (shell-specific handling)
# Category: 500-599 Tool completions
# Note: Uses Bash syntax but is compatible with Zsh

# pipenv
if command -v pipenv >/dev/null 2>&1; then
	if [ -n "$BASH_VERSION" ]; then
		eval "$(pipenv --completion 2>/dev/null || _PIPENV_COMPLETE=bash_source pipenv)"
	elif [ -n "$ZSH_VERSION" ] && [ -d "$ZSH_CACHE_HOME" ]; then
		# Save pipenv completion to fpath directory for autoloading
		{ pipenv --completion 2>/dev/null || _PIPENV_COMPLETE=zsh_source pipenv; } > "${ZSH_CACHE_HOME}/_pipenv" 2>/dev/null
	fi
fi
