#!/bin/sh
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# .config/shell/colors_null.sh
#
# Null color definitions for dumb terminals
# This file creates the same color variables as colors.sh but with empty values
#
# Note: This file requires Bash 4.0+ or Zsh for associative arrays.

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
	ANSI[RESET]=''
	ANSI[BOLD]=''

	# ANSI colors
	ANSI[BLACK]=''
	ANSI[RED]=''
	ANSI[GREEN]=''
	ANSI[YELLOW]=''
	ANSI[BLUE]=''
	ANSI[MAGENTA]=''
	ANSI[CYAN]=''
	ANSI[WHITE]=''

	# ANSI bright colors
	ANSI[BRBLACK]=''
	ANSI[BRRED]=''
	ANSI[BRGREEN]=''
	ANSI[BRYELLOW]=''
	ANSI[BRBLUE]=''
	ANSI[BRMAGENTA]=''
	ANSI[BRCYAN]=''
	ANSI[BRWHITE]=''

	# Aliases for the ambiguously named colors
	ANSI[ORANGE]=''
	ANSI[LGRAY]=''
	ANSI[DGREY]=''
	ANSI[VIOLET]=''

	# Base16 Colors
	BASE16[BASE00]=''
	BASE16[BASE01]=''
	BASE16[BASE02]=''
	BASE16[BASE03]=''
	BASE16[BASE04]=''
	BASE16[BASE05]=''
	BASE16[BASE06]=''
	BASE16[BASE07]=''
	BASE16[BASE08]=''
	BASE16[BASE09]=''
	BASE16[BASE0A]=''
	BASE16[BASE0B]=''
	BASE16[BASE0C]=''
	BASE16[BASE0D]=''
	BASE16[BASE0E]=''
	BASE16[BASE0F]=''

	export ANSI BASE16
fi

unset _use_arrays
