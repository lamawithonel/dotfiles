#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# Print final PATH for debugging with color highlighting

if [ -n "$BASH_VERSION" ] || [ -n "$ZSH_VERSION" ]; then
	# Check if we have colors available
	if [ -n "${BASE16[BASE0D]}" ] && [ -n "${ANSI[RESET]}" ]; then
		# Use Base16 colors for constrasted output:
		# - BASE0D (blue) for "PATH" variable name
		# - BASE0E (magenta) for "=" equals sign
		# - BASE0C (cyan) for ":" colon separators
		# - BASE05 (default foreground) for path elements
		# - RESET to return to normal

		# Color the colons
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
