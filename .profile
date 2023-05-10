#!/bin/sh
#-----------------------------------------------------------------------
# ~/.profile
#
# This file is read by POSIX-compliant shells when invoked as login shells.
# In the case of Bash, if either ~/.bash_profile or ~/.bash_login exist it
# will read the first one it encounters and ignore the rest.
# See the INVOCATION section of the bash(1) man page for more information.

# {{{ Local Functions
_get_fmode() {
	_uname_s="$(uname -s)"

	case "$_uname_s" in
		'Darwin'|"*BSD")
			stat -f '%OLp' "$1"
			  ;;
		*)
			stat -c '%a' "$1"
			;;
	esac
}

_running_macOS() {
	_uname_s="$(uname -s)"

	case "$_uname_s" in
		'Darwin')
			return 0
			;;
		*)
			return 1
			;;
	esac
}
# }}}

# {{{ Set a secure `umask(2)`
#shellcheck disable=2046
if [ $(id -ru) -gt 999 ] && [ "$(id -gn)" = "$(id -un)" ]; then
	umask 0027
else
	umask 0022
fi
# }}}

# {{{ Setup XDG Directories

if _running_macOS; then
	XDG_CACHE_HOME="${XDG_CACHE_HOME:-$(getconf DARWIN_USER_CACHE_DIR)}"
	XDG_CACHE_HOME="${XDG_CACHE_HOME%/}"
	XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$(getconf DARWIN_USER_TEMP_DIR)}"
	XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR%/}"
	XDG_STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"

	# TODO: Setup yadm repo to allow alternate XDG DATA and CONFIG dirs
	#XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/Library/Preferences}"
	#XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/Library/ApplicationSupport}"
	XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
	XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"

	# Some tools don't like spaces, so create a symlink
	if [ ! -e "${HOME}/Library/ApplicationSupport" ]; then
		ln -s "${HOME}/Library/Application Support" "${HOME}/Library/ApplicationSupport"
	fi
else
	XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
	XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
	XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
	XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$(mktemp -d -t "runtime-$(id -ur)")}"
	XDG_STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
fi

for _dir in "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"; do
	[ -d "$_dir" ] || mkdir -p "$_dir"
done

if [ ! -d "$XDG_RUNTIME_DIR" ]; then
	mkdir -m 0700 "$XDG_RUNTIME_DIR" 2>/dev/null
elif [ ! "$(_get_fmode "$XDG_RUNTIME_DIR")" = '700' ]; then
	chmod 0700 "$XDG_RUNTIME_DIR"
fi

unset -f _get_fmode _running_macOS
export XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_RUNTIME_DIR XDG_STATE_HOME
# }}}

# {{{ Language environment directories

# These need to be set at install-time. They are set here to ensure they
# are set for all shells, in case the default is not Bash.

CARGO_HOME="${XDG_DATA_HOME}/cargo"
DENO_INSTALL="${XDG_DATA_HOME}/deno"
DENO_INSTALL_ROOT="${XDG_DATA_HOME}/deno/bin"
GOPATH="${HOME}/src/go"
PYENV_ROOT="${XDG_DATA_HOME}/pyenv"
RUSTUP_HOME="${XDG_DATA_HOME}/rustup"
SDKMAN_DIR="${XDG_DATA_HOME}/sdkman"
VAGRANT_HOME="${XDG_DATA_HOME}/vagrant"
VOLTA_HOME="${XDG_DATA_HOME}/volta"

export CARGO_HOME DENO_INSTALL DENO_INSTALL_ROOT GOPATH PYENV_ROOT RUSTUP_HOME SDKMAN_DIR VAGRANT_HOME VOLTA_HOME

# }}}

#shellcheck disable=1090
[ -e ~/.profile.local ] && . ~/.profile.local

# vim:foldmethod=marker
# vi:ts=4:sw=4:noexpandtab
