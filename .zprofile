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
# XDG directories validation
#
# These should have been set up in .zshenv (for all Zsh contexts) and .profile
# (for login shells). Just validate they exist.

# Verify base XDG directories are set (from .profile or .zshenv)
[ -n "$XDG_BIN_HOME" ]    || return 1
[ -n "$XDG_CACHE_HOME" ]  || return 1
[ -n "$XDG_CONFIG_HOME" ] || return 1
[ -n "$XDG_DATA_HOME" ]   || return 1
[ -n "$XDG_STATE_HOME" ]  || return 1

if [ -d "$ZSH_CONFIG_HOME/profile.d" ]; then
	# Use nullglob (N) to avoid error when no files match
	for _f in "${ZSH_CONFIG_HOME}/profile.d/"*.sh(N); do
		#shellcheck disable=1091
		[ -r "$_f" ] && . "$_f"
	done
fi

#-----------------------------------------------------------------------
# Homebrew profile.d
#

if [[ "$OSTYPE" =~ 'darwin' ]] && [ -d /opt/homebrew/etc/profile.d ]; then
	# Use nullglob (N) to avoid error when no files match
	for _f in /opt/homebrew/etc/profile.d/*.sh(N); do
		#shellcheck disable=1091
		[ -r "$_f" ] && . "$_f"
	done
fi
