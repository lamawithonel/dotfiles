#!/usr/bin/env bash

# This file is only for Bash.  Exit if the shell is NOT Bash.
[ -n "$BASH_VERSION" ] || exit 1

# Load the default .profile
#shellcheck source=.profile
[[ -s ~/.profile ]] && source ~/.profile

# Setup XDG directories
BASH_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}/bash"
BASH_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/bash"
[[ -d "$BASH_CONFIG_HOME" ]] || mkdir -pZ "$BASH_CONFIG_HOME" >&/dev/null || mkdir -p "$BASH_CONFIG_HOME"
[[ -d "$BASH_DATA_HOME" ]]   || mkdir -pZ "$BASH_DATA_HOME" >&/dev/null   || mkdir -p "$BASH_DATA_HOME"

# Store history in the XDG-standard location
HISTFILE="${BASH_DATA_HOME}/history"; export HISTFILE

# Source ~/.bashrc if this is an interactive shell.
case "${-}" in
	*i*)
        #shellcheck source=.bashrc
        source ~/.bashrc ;;
esac

# vim:foldmethod=marker
# vi:ts=4:sw=4:noexpandtab
