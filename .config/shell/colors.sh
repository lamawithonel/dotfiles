#!/bin/sh
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# .config/shell/colors.sh
#
# Color definitions that work in both Bash and Zsh
# This file creates several short-hand variables for the sixteen ANSI colors,
# i.e., those defined in ANSI X3.64 / ECMA-48 / ISO/IEC 6429.  Additionally,
# it defines variables for the Base16 color palette, which should be compatible
# with base16-shell.
#
# Note: This file requires Bash 4.0+ or Zsh for associative arrays.
# The $'...' quoting syntax is also a Bash/Zsh extension.
#
# See:
#   * https://en.wikipedia.org/wiki/ANSI_escape_code
#   * https://github.com/chriskempson/base16
#   * https://github.com/chriskempson/base16-shell

# Detect if we're in Bash or Zsh and initialize associative arrays
if [ -n "$BASH_VERSION" ]; then
	# Bash 4.0+ supports associative arrays
	if [ "${BASH_VERSINFO[0]}" -ge 4 ]; then
		declare -A ANSI
		declare -A BASE16
		_use_arrays=1
	else
		_use_arrays=0
	fi
elif [ -n "$ZSH_VERSION" ]; then
	# Zsh supports associative arrays
	typeset -A ANSI
	typeset -A BASE16
	_use_arrays=1
else
	# Other shells don't support associative arrays
	_use_arrays=0
fi

if [ "$_use_arrays" = "1" ]; then
	# ANSI color reset control sequence
	ANSI[RESET]=$'\033[0m'
	ANSI[BOLD]=$'\033[1m'

	# ANSI colors
	ANSI[BLACK]=$'\033[30m'
	ANSI[RED]=$'\033[31m'
	ANSI[GREEN]=$'\033[32m'
	ANSI[YELLOW]=$'\033[33m'
	ANSI[BLUE]=$'\033[34m'
	ANSI[MAGENTA]=$'\033[35m'
	ANSI[CYAN]=$'\033[36m'
	ANSI[WHITE]=$'\033[37m'

	# ANSI bright colors using the bold attribute
	# (sequences 90-97 are not part of the standard)
	ANSI[BRBLACK]=$'\033[1;30m'
	ANSI[BRRED]=$'\033[1;31m'
	ANSI[BRGREEN]=$'\033[1;32m'
	ANSI[BRYELLOW]=$'\033[1;33m'
	ANSI[BRBLUE]=$'\033[1;34m'
	ANSI[BRMAGENTA]=$'\033[1;35m'
	ANSI[BRCYAN]=$'\033[1;36m'
	ANSI[BRWHITE]=$'\033[1;37m'

	# Aliases for the ambiguously named colors
	ANSI[ORANGE]="${ANSI[RED]}"
	ANSI[LGRAY]="${ANSI[WHITE]}"
	ANSI[DGREY]="${ANSI[BRBLACK]}"
	ANSI[VIOLET]="${ANSI[BRBLUE]}"

	# Base16 Colors
	BASE16[BASE00]=$'\033[30m'
	BASE16[BASE01]=$'\033[38;5;18m'
	BASE16[BASE02]=$'\033[38;5;19m'
	BASE16[BASE03]=$'\033[1;30m'
	BASE16[BASE04]=$'\033[38;5;20m'
	BASE16[BASE05]=$'\033[37m'
	BASE16[BASE06]=$'\033[38;5;21m'
	BASE16[BASE07]=$'\033[1;37m'
	BASE16[BASE08]=$'\033[31m'
	BASE16[BASE09]=$'\033[38;5;16m'
	BASE16[BASE0A]=$'\033[33m'
	BASE16[BASE0B]=$'\033[32m'
	BASE16[BASE0C]=$'\033[36m'
	BASE16[BASE0D]=$'\033[34m'
	BASE16[BASE0E]=$'\033[35m'
	BASE16[BASE0F]=$'\033[38;5;17m'

	export ANSI BASE16
fi

unset _use_arrays
