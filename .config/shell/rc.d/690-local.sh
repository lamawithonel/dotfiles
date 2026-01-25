#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# 690-local.sh
#
# Source local additions and overrides
# Category: 600-699 Final setup and local overrides
# Note: Uses Bash syntax but is compatible with Zsh

# Source shell-specific .rc.d directories
if [ -n "$BASH_VERSION" ] && [ -d "${HOME}/.bashrc.d" ]; then
	for _file in "${HOME}/.bashrc.d/"*.sh; do
		# Skip if glob didn't match (returns literal pattern)
		[ -r "$_file" ] || continue
		# shellcheck disable=SC1090  # Dynamic source files
		. "$_file"
	done
	unset _file
fi

if [ -n "$ZSH_VERSION" ] && [ -d "${HOME}/.zshrc.d" ]; then
	# Zsh-specific: Use nullglob (N) to avoid error when no files match
	# This must be in a subshell or eval to work
	for _file in $(find "${HOME}/.zshrc.d" -maxdepth 1 -name "*.sh" -type f 2>/dev/null | sort); do
		# shellcheck disable=SC1090  # Dynamic source files
		[ -r "$_file" ] && . "$_file"
	done
	unset _file
fi

# Source shell-specific .rc.local files
if [ -n "$BASH_VERSION" ] && [ -e "${HOME}/.bashrc.local" ]; then
	# shellcheck source=./.bashrc.local
	. "${HOME}/.bashrc.local"
fi

if [ -n "$ZSH_VERSION" ] && [ -e "${HOME}/.zshrc.local" ]; then
	# shellcheck source=./.zshrc.local
	. "${HOME}/.zshrc.local"
fi

# Source shell-specific .rc.local.d directories (if they exist)
if [ -n "$BASH_VERSION" ] && [ -d "${HOME}/.bashrc.local.d" ]; then
	for _file in "${HOME}/.bashrc.local.d/"*.sh; do
		[ -r "$_file" ] || continue
		# shellcheck disable=SC1090  # Dynamic source files
		. "$_file"
	done
fi

if [ -n "$ZSH_VERSION" ] && [ -d "${HOME}/.zshrc.local.d" ]; then
	# Use find to avoid Zsh-specific glob syntax
	for _file in $(find "${HOME}/.zshrc.local.d" -maxdepth 1 -name "*.sh" -type f 2>/dev/null | sort); do
		# shellcheck disable=SC1090  # Dynamic source files
		[ -r "$_file" ] && . "$_file"
	done
fi

