#!/bin/zsh
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#-----------------------------------------------------------------------
# ~/.zprofile
#
# This file is sourced by Zsh login shells
# It should source .profile for POSIX-compatible environment setup

# Source .profile if it hasn't been sourced yet
if [ -z "$__PROFILE_SOURCED" ]; then
	#shellcheck source=.profile
	[ -s "${HOME}/.profile" ] && emulate sh -c '. "${HOME}/.profile"'
fi

#-----------------------------------------------------------------------
# XDG directories for Zsh
#

# These should have been setup in .profile, but just in case...
[ -n "$XDG_CACHE_HOME" ]  || return 1
[ -n "$XDG_CONFIG_HOME" ] || return 1
[ -n "$XDG_DATA_HOME" ]   || return 1
[ -n "$XDG_STATE_HOME" ]  || return 1

# Zsh-specific XDG directories
[ -d "${ZSH_CACHE_HOME:=${XDG_CACHE_HOME}/zsh}" ]   || mkdir -p "$ZSH_CACHE_HOME"
[ -d "${ZSH_CONFIG_HOME:=${XDG_CONFIG_HOME}/zsh}" ] || mkdir -p "$ZSH_CONFIG_HOME"
[ -d "${ZSH_DATA_HOME:=${XDG_DATA_HOME}/zsh}" ]     || mkdir -p "$ZSH_DATA_HOME"
[ -d "${ZSH_STATE_HOME:=${XDG_STATE_HOME}/zsh}" ]   || mkdir -p "$ZSH_STATE_HOME"

export ZSH_CACHE_HOME ZSH_CONFIG_HOME ZSH_DATA_HOME ZSH_STATE_HOME

if [ -d "$ZSH_CONFIG_HOME" ]; then
	for _f in "${ZSH_CONFIG_HOME}/profile.d/"*".sh"; do
		#shellcheck disable=1091
		[ -r "$_f" ] && . "$_f"
	done
fi

#-----------------------------------------------------------------------
# Homebrew profile.d
#

if [[ "$OSTYPE" =~ 'darwin' ]] && [ -d /opt/homebrew/etc/profile.d ]; then
	for _f in /opt/homebrew/etc/profile.d/*.sh; do
		#shellcheck disable=1091
		[ -r "$_f" ] && . "$_f"
	done
fi
