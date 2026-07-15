#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
#
#----------------------------------------------------------------------
# Starship prompt initialization

if command -v starship > /dev/null 2>&1; then
	# Requires mise >= 2026.7.5, which creates the `cargo-starship/latest`
	# symlink; starship's init output references that stable path
	# rather than a version-numbered one.
	if [ -n "$BASH_VERSION" ]; then
		eval "$(starship init bash)"
	elif [ -n "$ZSH_VERSION" ]; then
		eval "$(starship init zsh)"
	fi
fi
