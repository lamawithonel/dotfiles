#!/usr/bin/env bash

#-----------------------------------------------------------------------
# Shell-agnostic stuff
#

# Source .profile if it hasn't been sourced yet
if [ -z "$__PROFILE_SOURCED" ]; then
	#shellcheck source=.profile
	[ -s "${HOME}/.profile" ] && source "${HOME}/.profile"
fi

# This file is only for Bash.  Exit if the shell is NOT Bash.
[ -n "$BASH_VERSION" ] || return 1

#-----------------------------------------------------------------------
# XDG directories for Bash
#

# These should have been setup in .profile, but just in case...
[ -n "$XDG_BIN_HOME" ]    || return 1
[ -n "$XDG_CACHE_HOME" ]  || return 1
[ -n "$XDG_CONFIG_HOME" ] || return 1
[ -n "$XDG_DATA_HOME" ]   || return 1
[ -n "$XDG_STATE_HOME" ]  || return 1

# Bash-specific XDG directories
[ -d "${BASH_CACHE_HOME:=${XDG_CACHE_HOME}/bash}" ]   || mkdir -pZ "$BASH_CACHE_HOME" >&/dev/null  || mkdir -p "$BASH_CACHE_HOME"
[ -d "${BASH_CONFIG_HOME:=${XDG_CONFIG_HOME}/bash}" ] || mkdir -pZ "$BASH_CONFIG_HOME" >&/dev/null || mkdir -p "$BASH_CONFIG_HOME"
[ -d "${BASH_DATA_HOME:=${XDG_DATA_HOME}/bash}" ]     || mkdir -pZ "$BASH_DATA_HOME" >&/dev/null   || mkdir -p "$BASH_DATA_HOME"
[ -d "${BASH_STATE_HOME:=${XDG_STATE_HOME}/bash}" ]   || mkdir -pZ "$BASH_STATE_HOME" >&/dev/null  || mkdir -p "$BASH_STATE_HOME"

if [ -d "$BASH_CONFIG_HOME" ]; then
	for _f in "${BASH_CONFIG_HOME}/profile.d/"*".sh"; do
		#shellcheck disable=1090
		[ -r "$_f" ] && source "$_f"
	done
fi

#-----------------------------------------------------------------------
# Homebrew profile.d
#

if [[ "$OSTYPE" =~ 'darwin' ]] && [ -d /opt/homebrew/etc/profile.d ]; then
	for _f in /opt/homebrew/etc/profile.d/*.sh; do
		#shellcheck disable=1090
		[ -r "$_f" ] && source "$_f"
	done
fi

#-----------------------------------------------------------------------
# ~/.bashrc for interactive shells

# If this is an interactive shell and .bashrc is not already in the call stack, source it
if [[ $- == *i* ]] && [[ ! ${BASH_SOURCE[*]} =~ ([[:blank:]]|/)\.bashrc([[:blank:]]|$) ]]; then
	#shellcheck source=./.bashrc
	[ -f "${HOME}/.bashrc" ] && source "${HOME}/.bashrc"
fi

# vim:foldmethod=marker
# vi:ts=4:sw=4:noexpandtab
