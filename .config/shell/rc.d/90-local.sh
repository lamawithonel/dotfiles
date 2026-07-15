#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# Source local additions and overrides

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
	# NUL-delimited find|sort avoids both a Zsh-only glob qualifier
	# (which Bash cannot even parse, since this file is sourced by
	# both shells) and IFS word-splitting on filenames containing
	# whitespace. Process substitution (not a plain pipe) keeps the
	# loop body in the current shell, so a sourced file's variables/
	# functions/aliases persist after the loop instead of vanishing
	# with a piped subshell.
	while IFS= read -r -d '' _file; do
		# shellcheck disable=SC1090  # Dynamic source files
		[ -r "$_file" ] && . "$_file"
	done < <(find "${HOME}/.zshrc.d" -maxdepth 1 -name "*.sh" -type f -print0 2>/dev/null | sort -z)
	unset _file
fi

# Source shell-specific .rc.local files
if [ -n "$BASH_VERSION" ] && [ -e "${HOME}/.bashrc.local" ]; then
	# shellcheck source=./.bashrc.local
	# shellcheck disable=SC1091
	. "${HOME}/.bashrc.local"
fi

if [ -n "$ZSH_VERSION" ] && [ -e "${HOME}/.zshrc.local" ]; then
	# shellcheck source=./.zshrc.local
	# shellcheck disable=SC1091
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
	# See the .zshrc.d block above for why NUL-delimited find|sort via
	# process substitution is used here.
	while IFS= read -r -d '' _file; do
		# shellcheck disable=SC1090  # Dynamic source files
		[ -r "$_file" ] && . "$_file"
	done < <(find "${HOME}/.zshrc.local.d" -maxdepth 1 -name "*.sh" -type f -print0 2>/dev/null | sort -z)
fi
