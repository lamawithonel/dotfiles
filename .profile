#!/bin/sh
#-----------------------------------------------------------------------
# ~/.profile
#
# This file is read by POSIX-compliant shells when invoked as login shells.
# In the case of Bash, if either ~/.bash_profile or ~/.bash_login exist it
# will read the first one it encounters and ignore the rest.
# See the INVOCATION section of the bash(1) man page for more information.

# Set a secure umask(2)
#shellcheck disable=2046
if [ $(id -ru) -gt 999 ] && [ "$(id -gn)" = "$(id -un)" ]; then
	umask 0027
else
	umask 0022
fi

#shellcheck disable=1090
[ -e ~/.profile.local ] && . ~/.profile.local

# vim:foldmethod=marker
# vi:ts=4:sw=4:noexpandtab
