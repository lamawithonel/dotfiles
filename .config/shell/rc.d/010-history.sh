#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# 010-history.sh
#
# History configuration for both Bash and Zsh
# Category: 000-099 Core shell configuration
# Note: Uses Bash syntax but is compatible with Zsh

# Bash-specific history settings
if [ -n "$BASH_VERSION" ]; then
	# Append to the history file, don't overwrite it
	shopt -s histappend

	# Store history in the XDG-standard location
	HISTFILE="${BASH_CACHE_HOME}/history"

	# Ignore lines starting with a [:space:] and lines which are duplicates of
	# the previous entry.
	HISTCONTROL="ignorespace:ignoredups"

	# Number of commands to keep in the scrollback history
	HISTSIZE=1000

	# Maximum size of $HISTFILE (in lines)
	HISTFILESIZE=2000

	export HISTFILE HISTCONTROL HISTSIZE HISTFILESIZE
fi

# Zsh-specific history settings
if [ -n "$ZSH_VERSION" ]; then
	# Store history in the XDG-standard location
	HISTFILE="${ZSH_CACHE_HOME}/history"

	# Number of commands to keep in the scrollback history
	HISTSIZE=1000

	# Maximum size of $HISTFILE
	SAVEHIST=2000

	export HISTFILE HISTSIZE SAVEHIST
fi
