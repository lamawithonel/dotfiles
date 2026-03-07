#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# Prompt configuration - Starship initialization

# Use Starship.rs to configure the prompt
if command -v starship >/dev/null 2>&1; then
	if [ -n "$BASH_VERSION" ]; then
		eval "$(starship init bash)"
		eval "$(starship completions bash)"
	elif [ -n "$ZSH_VERSION" ]; then
		eval "$(starship init zsh)"
	fi
fi
