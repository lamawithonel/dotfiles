#!/bin/sh
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# 100-path-setup.sh
#
# PATH configuration for both Bash and Zsh
# Category: 100-199 PATH and environment setup

# Source the shared PATH management function
# shellcheck source=./path.sh
[ -f "${XDG_CONFIG_HOME}/shell/path.sh" ] && . "${XDG_CONFIG_HOME}/shell/path.sh"

# Zsh has built-in PATH deduplication
if [ -n "$ZSH_VERSION" ]; then
	typeset -U PATH path
fi

# Most of this could happen elsewhere in this script, but doing it all here
# gives a clean look at what order they'll appear in the final $PATH variable.
# Items added earlier will appear later in the variable (lower precedence).

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

_ensure_path_contains "${XDG_DATA_HOME}/tfenv/bin"
_ensure_path_contains "${XDG_DATA_HOME}/cabal/bin"
_ensure_path_contains "${XDG_DATA_HOME}/dotnet/tools" # NOTE: See https://github.com/dotnet/sdk/issues/10390
_ensure_path_contains "${XDG_DATA_HOME}/rvm/bin"
_ensure_path_contains "${XDG_DATA_HOME}/cargo/bin"
_ensure_path_contains "${XDG_DATA_HOME}/pyenv/bin"

if command -v pyenv >/dev/null 2>&1; then
	_ensure_path_contains "${XDG_DATA_HOME}/pyenv/shims"
	_ensure_path_contains "${XDG_DATA_HOME}/pyenv/plugins/pyenv-virtualenv/shims"
fi

# Add private /bin directories to $PATH
_ensure_path_contains "${HOME}/bin"

export PATH
