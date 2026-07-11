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
		eval "$(starship init bash | sed -E 's:(mise/installs/cargo-starship)/[[:digit:]\.]+/(bin/starship):\1/latest/\2:g')"
		eval "$(starship completions bash | sed -E 's:(mise/installs/cargo-starship)/[[:digit:]\.]+/(bin/starship):\1/latest/\2:g')"
	elif [ -n "$ZSH_VERSION" ]; then
		eval "$(starship init zsh | sed -E 's:(mise/installs/cargo-starship)/[[:digit:]\.]+/(bin/starship):\1/latest/\2:g')"
		eval "$(starship completions zsh | sed -E 's:(mise/installs/cargo-starship)/[[:digit:]\.]+/(bin/starship):\1/latest/\2:g')"
	fi
fi
