#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# 200-colors.sh
#
# Color and dircolors configuration for both Bash and Zsh
# Category: 200-299 Visual configuration
# Note: Uses Bash syntax but is compatible with Zsh

# Source tinty/base16 color theme if available
if command -v tinty >/dev/null 2>&1; then
	TINTED_SHELL_ENABLE_BASE16_VARS=1
	TINTED_SHELL_ENABLE_BASE24_VARS=1
	BASE16_SHELL_PATH="${XDG_DATA_HOME}/tinted-theming/tinty/repos/tinted-shell"

	export \
		BASE16_SHELL_PATH \
		TINTED_SHELL_ENABLE_BASE16_VARS \
		TINTED_SHELL_ENABLE_BASE24_VARS

	# Save tinty completion to fpath directory for autoloading (Zsh only)
	if [ -n "$ZSH_VERSION" ] && [ -d "$ZSH_CACHE_HOME" ]; then
		tinty generate-completion zsh > "${ZSH_CACHE_HOME}/_tinty" 2>/dev/null
	fi
fi

if [ -s "${BASE16_SHELL_PATH}/profile_helper.sh" ]; then
	# shellcheck source=../.local/share/tinted-theming/tinty/repos/tinted-shell/profile_helper.sh
	. "${BASE16_SHELL_PATH}/profile_helper.sh"
fi

# Use tput(1) to determine the number of supported colors.
TERMINAL_COLORS="$(tput colors 2> /dev/null || echo -1)"

# If the terminal supports at least 8 colors, source the color theme and
# setup dircolors(1)
if [ "$TERMINAL_COLORS" -ge '8' ]; then
	# shellcheck source=./colors.sh
	[ -f "${XDG_CONFIG_HOME}/shell/colors.sh" ] && . "${XDG_CONFIG_HOME}/shell/colors.sh"

	# dircolors(1)
	case "$OSTYPE" in
		*-gnu)
			if command -v dircolors >/dev/null 2>&1; then
				# Use process substitution for bash/zsh
				eval "$(dircolors <(dircolors -p | sed 's/ 01;/ /g'))"
			fi
			;;
		bsd* | darwin*)
			if command -v gdircolors >/dev/null 2>&1; then
				# Use process substitution for bash/zsh
				eval "$(gdircolors <(gdircolors -p | sed 's/ 01;/ /g'))"
			fi
			;;
	esac
else
	if [ -f "${XDG_CONFIG_HOME}/shell/colors_null.sh" ]; then
		# shellcheck source=./colors_null.sh
		. "${XDG_CONFIG_HOME}/shell/colors_null.sh"
	fi
fi
