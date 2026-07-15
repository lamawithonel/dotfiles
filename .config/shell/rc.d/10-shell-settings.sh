#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
#
#----------------------------------------------------------------------
# Interactive shell options and history configuration

HISTSIZE=1000
export HISTSIZE

if [ -n "$BASH_VERSION" ]; then
	# Keep Bash's display dimensions current and enable recursive globbing.
	shopt -s checkwinsize globstar histappend

	# Defensive fallback in case BASH_CACHE_HOME was not inherited
	# (e.g. a nested shell that skipped .bash_profile's export --
	# see .bash_profile), so HISTFILE never resolves to an
	# unwritable empty-prefix path like "/history".
	HISTFILE="${BASH_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/bash}/history"
	[ -d "${HISTFILE%/*}" ] || mkdir -p "${HISTFILE%/*}"
	HISTCONTROL='ignorespace:ignoredups'
	HISTFILESIZE=2000
	export HISTFILE HISTCONTROL HISTFILESIZE
elif [ -n "$ZSH_VERSION" ]; then
	# Completion behavior - make Zsh feel like Bash.
	setopt BASH_AUTO_LIST
	setopt NO_AUTO_MENU
	setopt NO_MENU_COMPLETE
	setopt LIST_AMBIGUOUS

	# History behavior.
	setopt NO_BANG_HIST
	setopt INTERACTIVE_COMMENTS
	setopt EXTENDED_HISTORY
	setopt HIST_IGNORE_ALL_DUPS
	setopt HIST_REDUCE_BLANKS
	setopt HIST_VERIFY
	setopt APPEND_HISTORY
	setopt INC_APPEND_HISTORY

	# Directory navigation conveniences.
	setopt AUTO_CD
	setopt AUTO_PUSHD
	setopt PUSHD_IGNORE_DUPS

	# Defensive fallback in case ZSH_CACHE_HOME was somehow unset
	# (it is always exported by .zshenv, but keep this consistent
	# with the Bash branch's belt-and-suspenders fallback above).
	HISTFILE="${ZSH_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/zsh}/history"
	[ -d "${HISTFILE%/*}" ] || mkdir -p "${HISTFILE%/*}"
	SAVEHIST=2000
	export HISTFILE SAVEHIST
fi
