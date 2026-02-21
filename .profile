#!/bin/sh
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#-----------------------------------------------------------------------
# ~/.profile
#
# This file is read by POSIX-compliant shells when invoked as login shells.
# Bash will look for ~/.bash_profile, ~/.bash_login, or ~/.profile, in that
# order.  The first one it finds it reads, then ignores the rest.
#
# See the INVOCATION section of the bash(1) man page for more information.

# For debugging only.  Do not leave uncommented!
#_shopts="$(set +o)"
#set -o errexit
#set -o nounset

# Guard variable to prevent duplicate sourcing of this file
# This is critical for proper login vs interactive shell separation
[ -n "$__PROFILE_SOURCED" ] && return
__PROFILE_SOURCED=1
export __PROFILE_SOURCED

# {{{ Local Functions
_get_fmode() {
	_uname_s="$(uname -s)"

	case "$_uname_s" in
		'Darwin' | "*BSD")
			stat -f '%OLp' "$1"
			;;
		*)
			stat -c '%a' "$1"
			;;
	esac
}

_get_fowner() {
	_uname_s="$(uname -s)"

	case "$_uname_s" in
		'Darwin' | "*BSD")
			stat -f '%u' "$1"
			;;
		*)
			stat -c '%u' "$1"
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

# {{{ Public functions (not unset)
rngstring() {
	_length="${1:-16}"
	_charset="${2:-A-Za-z0-9@%+\\/\'\!\#\$\^\?:.\(\)\{\}\[\]\~_.-}"

	# if '--help' or '-h' are one of the arguments in $@, print usage
	case "$*" in
		*--help* | -h*)
			echo "Usage: rngstring [length] [tr-style-charset]"
			return 0
			;;
	esac

	LANG=C LC_ALL=C tr -cd "$_charset" < /dev/urandom | fold -w "$_length" | head -n 1
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
	XDG_BIN_HOME="${XDG_BIN_HOME:-${HOME}/.local/bin}"
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
	XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -ru)}"
	XDG_STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
fi

# If the XDG_RUNTIME_DIR is not owned by the current user, create a new one
# with a random suffix.
if [ "$(_get_fowner "$XDG_RUNTIME_DIR")" != "$(id -ru)" ]; then
	XDG_RUNTIME_DIR="/tmp/runtime-$(id -ru)-$(rngstring 8 'a-z0-9')"
fi

for _dir in "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"; do
	[ -d "$_dir" ] || mkdir -p "$_dir"
done

if [ ! -d "$XDG_RUNTIME_DIR" ]; then
	mkdir -m 0700 "$XDG_RUNTIME_DIR" 2> /dev/null
fi
[ "$(_get_fmode "$XDG_RUNTIME_DIR")" = '700' ] || chmod 0700 "$XDG_RUNTIME_DIR"

unset -f _get_fmode _get_fowner _running_macOS
export XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_RUNTIME_DIR XDG_STATE_HOME
# }}}

# {{{ Language environment directories

# These need to be set at install-time. They are set here to ensure they
# are set for all shells (in case the default is not Bash).

CARGO_HOME="${XDG_DATA_HOME}/cargo"
DENO_INSTALL="${XDG_DATA_HOME}/deno"
DENO_INSTALL_ROOT="${XDG_DATA_HOME}/deno/bin"
DOTNET_CLI_HOME="${XDG_DATA_HOME}/dotnet"
FNM_DIR="${XDG_DATA_HOME}/fnm"
GOPATH="${HOME}/src/go"
LUAROCKS_CONFIG="${XDG_CONFIG_HOME}/luarocks/config.lua"
LUAROCKS_TREE="${XDG_DATA_HOME}/luarocks"
LUAVER_DIR="${XDG_DATA_HOME}/luaver"
PYENV_ROOT="${XDG_DATA_HOME}/pyenv"
RUSTUP_HOME="${XDG_DATA_HOME}/rustup"
SDKMAN_DIR="${XDG_DATA_HOME}/sdkman"
VAGRANT_HOME="${XDG_DATA_HOME}/vagrant"

export \
	CARGO_HOME \
	DENO_INSTALL \
	DENO_INSTALL_ROOT \
	DOTNET_CLI_HOME \
	FNM_DIR \
	GOPATH \
	LUAROCKS_CONFIG \
	LUAROCKS_TREE \
	LUAVER_DIR \
	PYENV_ROOT \
	RUSTUP_HOME \
	SDKMAN_DIR \
	VAGRANT_HOME

# }}}

# {{{ ~/.profile.d loading

if [ -d "${HOME}/.profile.d" ]; then
	for _file in "${HOME}/.profile.d/"*".sh"; do
		# shellcheck disable=1090
		[ -r "$_file" ] && . "$_file"
	done
	unset _file
fi

# }}}

# {{{ Shared shell configuration

# Source shared PATH management functions
# shellcheck source=.config/shell/path.sh
[ -f "${XDG_CONFIG_HOME}/shell/path.sh" ] && . "${XDG_CONFIG_HOME}/shell/path.sh"

# Source shared environment variables
# shellcheck source=.config/shell/environment.sh
[ -f "${XDG_CONFIG_HOME}/shell/environment.sh" ] && . "${XDG_CONFIG_HOME}/shell/environment.sh"

# }}}

# Restore shell options in case we set `errexit` or `nounset` for debugging
eval "${_shopts:-}"
unset _shopts

# {{{ ~/.profile.local* loading

if [ -d "${HOME}/.profile.local.d" ]; then
	for _file in "${HOME}/.profile.local.d/"*".sh"; do
		#shellcheck disable=1090
		[ -r "$_file" ] && . "$_file"
	done
fi

#shellcheck source=./.profile.local
[ -e "${HOME}/.profile.local" ] && . "${HOME}/.profile.local"

# }}}
