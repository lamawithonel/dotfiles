#!/bin/sh
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# 210-prompt.sh
#
# Prompt configuration - Starship initialization
# Category: 200-299 Visual configuration
#
# Note: Fallback prompts are shell-specific and remain in .bashrc/.zshrc

# Use Starship.rs to configure the prompt if it's available
if command -v starship >/dev/null 2>&1; then
	if [ -n "$BASH_VERSION" ]; then
		eval "$(starship init bash)"
		eval "$(starship completions bash)"
	elif [ -n "$ZSH_VERSION" ]; then
		eval "$(starship init zsh)"
	fi
fi
