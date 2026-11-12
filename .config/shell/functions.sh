#!/bin/sh
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# .config/shell/functions.sh
#
# POSIX-compatible public shell functions
# Can be sourced by both Bash and Zsh (and any POSIX shell)
#
# This is the one canonical home of these functions.  Do not duplicate
# them elsewhere (e.g., in .profile or rc.d stage files).

# rngstring() -- Print a random string
#
# $1 = length (optional, default 16)
# $2 = tr(1)-style character set (optional)
#
rngstring() {
	_length="${1:-16}"
	_charset="${2:-A-Za-z0-9@%+\\/\'\!\#\$\^\?:.\(\)\{\}\[\]\~_.-}"

	# if '--help' or '-h' are one of the arguments in $@, print usage
	case "$*" in
		*--help* | -h*)
			echo "Usage: rngstring [length] [tr-style-charset]"
			return 0
			;;
	esac

	LANG=C LC_ALL=C tr -cd "$_charset" < /dev/urandom | fold -w "$_length" | head -n 1
}
