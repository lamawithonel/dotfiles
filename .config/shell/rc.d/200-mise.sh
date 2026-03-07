#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
#
#----------------------------------------------------------------------
# Mise polyglot runtime manager (https://mise.jdx.dev/)
#
# Manages: Python, Node.js, Rust, Go, Java, Ruby, Zig, and more

if command -v mise > /dev/null 2>&1; then
	if [ -n "$BASH_VERSION" ]; then
		eval "$(mise activate bash)"
		eval "$(mise completions bash)"
	elif [ -n "$ZSH_VERSION" ]; then
		eval "$(mise activate zsh)"
		eval "$(mise completions zsh)"
	fi
fi
