#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# 600-path-print.sh
#
# Print final PATH for debugging with color highlighting
# Category: 600-699 Final setup and local overrides
# Note: Uses Bash syntax but is compatible with Zsh

# Print the PATH variable with fancy color highlighting to make it easy to read
if [ -n "$BASH_VERSION" ] || [ -n "$ZSH_VERSION" ]; then
	# Check if we have colors available
	if [ -n "${BASE16[BASE0D]}" ] && [ -n "${ANSI[RESET]}" ]; then
		# Use Base16 colors for pretty output:
		# - BASE0D (blue) for "PATH" variable name
		# - BASE0E (magenta) for "=" equals sign
		# - BASE0C (cyan) for ":" colon separators
		# - BASE05 (default foreground) for path elements
		# - RESET to return to normal
		
		# Use parameter expansion for fast string replacement - color the colons
		# This is much faster than looping and works in both Bash and Zsh
		_colored_path="${PATH//:/${BASE16[BASE0C]}:${BASE16[BASE05]}}"
		
		# Print with colors: PATH=<colored_path>
		printf '%s%s%s%s%s%s%s\n' \
			"${BASE16[BASE0D]}" "PATH" \
			"${BASE16[BASE0E]}" "=" \
			"${BASE16[BASE05]}" "${_colored_path}" \
			"${ANSI[RESET]}"
		
		unset _colored_path
	else
		# No colors available, fall back to plain output
		printf 'PATH=%s\n' "$PATH"
	fi
fi
