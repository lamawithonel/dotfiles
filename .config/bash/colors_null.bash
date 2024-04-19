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

# ANSI bright colors using the bold attribute
# (sequences 90-97 are not part of the standard)
ANSI[BRBLACK]=''
ANSI[BRRED]=''
ANSI[BRGREEN]=''
ANSI[BRYELLOW]=''
ANSI[BRBLUE]=''
ANSI[BRMAGENTA]=''
ANSI[BRCYAN]=''
ANSI[BRWHITE]=''

# Aliases for the ambiguously named colors
ANSI[ORANGE]="${ANSI[RED]}"
ANSI[LGRAY]="${ANSI[WHITE]}"
ANSI[DGREY]="${ANSI[BRBLACK]}"
ANSI[VIOLET]="${ANSI[BRBLUE]}"

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

typeset ANSI
typeset BASE16

export ANSI BASE16
