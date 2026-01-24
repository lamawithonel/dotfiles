#!/bin/zsh
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#-----------------------------------------------------------------------
# ~/.zshenv
#
# This file is sourced by all Zsh instances (login, interactive, non-interactive)
# Keep it minimal - only set environment variables that need to be available everywhere

# Set ZDOTDIR if you want to keep Zsh configs in a different location
# For now, we keep them in $HOME for consistency with Bash
# export ZDOTDIR="${HOME}"

#-----------------------------------------------------------------------
# XDG Base Directories
#
# These must be set in .zshenv to ensure they're available in all Zsh contexts,
# including when Zsh is opened from another shell (non-login interactive).
# This prevents accidentally writing files to / or other incorrect locations.

# Set base XDG directories if not already set
[ -n "$XDG_CACHE_HOME" ]  || export XDG_CACHE_HOME="${HOME}/.cache"
[ -n "$XDG_CONFIG_HOME" ] || export XDG_CONFIG_HOME="${HOME}/.config"
[ -n "$XDG_DATA_HOME" ]   || export XDG_DATA_HOME="${HOME}/.local/share"
[ -n "$XDG_STATE_HOME" ]  || export XDG_STATE_HOME="${HOME}/.local/state"

# Zsh-specific XDG directories
# Use parameter expansion with := to set and export in one step
export ZSH_CACHE_HOME="${ZSH_CACHE_HOME:-${XDG_CACHE_HOME}/zsh}"
export ZSH_CONFIG_HOME="${ZSH_CONFIG_HOME:-${XDG_CONFIG_HOME}/zsh}"
export ZSH_DATA_HOME="${ZSH_DATA_HOME:-${XDG_DATA_HOME}/zsh}"
export ZSH_STATE_HOME="${ZSH_STATE_HOME:-${XDG_STATE_HOME}/zsh}"

# Create directories if they don't exist (safety)
[ -d "$ZSH_CACHE_HOME" ]  || mkdir -p "$ZSH_CACHE_HOME"
[ -d "$ZSH_CONFIG_HOME" ] || mkdir -p "$ZSH_CONFIG_HOME"
[ -d "$ZSH_DATA_HOME" ]   || mkdir -p "$ZSH_DATA_HOME"
[ -d "$ZSH_STATE_HOME" ]  || mkdir -p "$ZSH_STATE_HOME"
