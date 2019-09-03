#!/bin/sh
#-----------------------------------------------------------------------
# ~/.profile
#
# This file is read by POSIX-compliant shells when invoked as login shells.
# In the case of Bash, if either ~/.bash_profile or ~/.bash_login exist it
# will read the first one it encounters and ignore the rest.
# See the INVOCATION section of the bash(1) man page for more information.

# {{{ Traps & Cleanup
trap cleanup EXIT

_cleanup() {
	unset -f _get_fmode _cleanup
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
XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"

if [ -z "$XDG_RUNTIME_DIR" ]; then
	echo 'error: XDG_RUNTIME_DIR not set in the environment.'
	XDG_RUNTIME_DIR="/tmp/runtime-$(id -un)"; export XDG_RUNTIME_DIR
fi

if [ ! -d "$XDG_RUNTIME_DIR" ]; then
	mkdir -m 0700 "/tmp/runtime-$(id -un)"
elif [ ! "$(_get_fmode "$XDG_RUNTIME_DIR")" = '700' ]; then
	chmod 0700 "$XDG_RUNTIME_DIR"
fi

export XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_RUNTIME_PATH
# }}} XDG_RUNTIME_DIR

CARGO_HOME="${XDG_DATA_HOME}/cargo"
PYENV_ROOT="${XDG_DATA_HOME}/pyenv"
NVM_DIR="${XDG_DATA_HOME}/nvm"

export CARGO_HOME PYENV_ROOT NVM_DIR

#shellcheck disable=1090
[ -e ~/.profile.local ] && . ~/.profile.local

# vim:foldmethod=marker
# vi:ts=4:sw=4:noexpandtab
