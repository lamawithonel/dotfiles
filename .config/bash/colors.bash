#!/usr/bin/env bash
#----------------------------------------------------------------------
# This file creates several short-hand variables for the sixteen ANSI colors,
# i.e., those defined in ANSI X3.64 / ECMA-48 / ISO/IEC 6429.  Additionally,
# it defines variables for the Base16 color pallet, which should be compatible
# with base16-shell.
#
# See:
#   * https://en.wikipedia.org/wiki/ANSI_escape_code
#   * https://github.com/chriskempson/base16
#   * https://github.com/chriskempson/base16-shell

typeset -A ANSI
typeset -A BASE16

# ANSI color reset control sequence
ANSI[RESET]=$(echo -ne '\033[0m')

# ANSI colors
ANSI[BLACK]=$(echo -ne '\033[30m')
ANSI[RED]=$(echo -ne '\033[31m')
ANSI[GREEN]=$(echo -ne '\033[32m')
ANSI[YELLOW]=$(echo -ne '\033[33m')
ANSI[BLUE]=$(echo -ne '\033[34m')
ANSI[MAGENTA]=$(echo -ne '\033[35m')
ANSI[CYAN]=$(echo -ne '\033[36m')
ANSI[WHITE]=$(echo -ne '\033[37m')

# ANSI bright colors using the bold attribute
# (sequences 90-97 are not part of the standard)
ANSI[BRBLACK]=$(echo -ne '\033[1;30m')
ANSI[BRRED]=$(echo -ne '\033[1;31m')
ANSI[BRGREEN]=$(echo -ne '\033[1;32m')
ANSI[BRYELLOW]=$(echo -ne '\033[1;33m')
ANSI[BRBLUE]=$(echo -ne '\033[1;34m')
ANSI[BRMAGENTA]=$(echo -ne '\033[1;35m')
ANSI[BRCYAN]=$(echo -ne '\033[1;36m')
ANSI[BRWHITE]=$(echo -ne '\033[1;37m')

# Aliases for the ambiguously named colors
ANSI[ORANGE]=$ANSI[RED]
ANSI[LGRAY]=$ANSI[WHITE]
ANSI[DGREY]=$ANSI[BRBLACK]
ANSI[VIOLET]=$ANSI[BRBLUE]

# Base16 Colors
BASE16[BASE00]=$(echo -ne '\033[30m')
BASE16[BASE01]=$(echo -ne '\033[38;5;18m')
BASE16[BASE02]=$(echo -ne '\033[38;5;19m')
BASE16[BASE03]=$(echo -ne '\033[1;30m')
BASE16[BASE04]=$(echo -ne '\033[38;5;20m')
BASE16[BASE05]=$(echo -ne '\033[37m')
BASE16[BASE06]=$(echo -ne '\033[38;5;21m')
BASE16[BASE07]=$(echo -ne '\033[1;37m')
BASE16[BASE08]=$(echo -ne '\033[31m')
BASE16[BASE09]=$(echo -ne '\033[38;5;16m')
BASE16[BASE0A]=$(echo -ne '\033[33m')
BASE16[BASE0B]=$(echo -ne '\033[32m')
BASE16[BASE0C]=$(echo -ne '\033[36m')
BASE16[BASE0D]=$(echo -ne '\033[34m')
BASE16[BASE0E]=$(echo -ne '\033[35m')
BASE16[BASE0F]=$(echo -ne '\033[38;5;17m')

export ANSI BASE16
