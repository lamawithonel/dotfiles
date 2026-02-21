#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# 100-path-setup.sh
#
# PATH configuration for both Bash and Zsh
# Category: 100-199 PATH and environment setup
# Note: Uses Bash syntax but is compatible with Zsh

# _ensure_path_contains() -- An improved version of Red Hat's pathmunge()
#
# Adds a fully-qualified directory to the PATH variable.
#
# By default the directory is added at the beginning of the PATH variable,
# e.g., "${1}:/bin".  However, if the second argument is set to "after" it
# will append it to the end of PATH, e.g., "/bin:${1}".  If the directory
# path does not exist or is not a directory, it will remove the element.
#
# $1 = /fully/qualified/PATH/element
# $2 = "before" | "after" | "" (optional)
#
_ensure_path_contains() {
	# Must be a fully-qualified path (POSIX-compatible regex check)
	case "$1" in
		/*)
			# Valid absolute path
			;;
		*)
			# Not an absolute path, return error
			return 1
			;;
	esac

	# Remove existing PATH element if present
	PATH="${PATH//:$1:/:}" # Remove from middle
	PATH="${PATH/#$1:/}"   # Remove from beginning
	PATH="${PATH/%:$1/}"   # Remove from end

	# Exit if the path element does not exist OR is not a directory
	[ ! -d "$1" ] && return 0

	# Add the path element
	if [ "$2" = 'after' ]; then
		PATH="${PATH}:${1}"
	else
		PATH="${1}:${PATH}"
	fi
}

# Zsh has built-in PATH deduplication
if [ -n "$ZSH_VERSION" ]; then
	# shellcheck disable=SC2034  # path is used by Zsh internally
	typeset -U PATH path
fi

if [[ "$OSTYPE" =~ 'darwin' ]]; then
	if [ -f /opt/homebrew/etc/paths ]; then
		while IFS= read -r _line; do
			_ensure_path_contains "${_line}"
		done < /opt/homebrew/etc/paths
	fi

	# iTerm2 integration (if available)
	_iterm2_integration_dir="${XDG_DATA_HOME}/iTerm2/iTerm2-shell-integration"
	_iterm2_check="${_iterm2_integration_dir}/utilities/it2check"
	if [ -x "$_iterm2_check" ] && "$_iterm2_check"; then
		_ensure_path_contains "${_iterm2_integration_dir}/utilities"
	fi
fi

_ensure_path_contains "${XDG_DATA_HOME}/cabal/bin"
_ensure_path_contains "${XDG_DATA_HOME}/dotnet/tools" # NOTE: See https://github.com/dotnet/sdk/issues/10390
_ensure_path_contains "${XDG_DATA_HOME}/cargo/bin"

# Add private /bin directories to $PATH
_ensure_path_contains "${XDG_BIN_HOME}"
_ensure_path_contains "${HOME}/bin"

export PATH
