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
	XDG_RUNTIME_DIR="/tmp/runtime-$(id -un)"; export XDG_RUNTIME_DIR
fi

if [ ! -d "$XDG_RUNTIME_DIR" ]; then
	mkdir -m 0700 "/tmp/runtime-$(id -un)" 2>/dev/null
elif [ ! "$(_get_fmode "$XDG_RUNTIME_DIR")" = '700' ]; then
	chmod 0700 "$XDG_RUNTIME_DIR"
fi

export XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_RUNTIME_PATH
# }}} XDG_RUNTIME_DIR

# {{{ Language environment directories

# These need to be set at install-time. They are set here to ensure they
# are set for all shells, in case the default is not Bash.

CARGO_HOME="${XDG_DATA_HOME}/cargo"
NVM_DIR="${XDG_DATA_HOME}/nvm"
PYENV_ROOT="${XDG_DATA_HOME}/pyenv"

export CARGO_HOME NVM_DIR PYENV_ROOT

# }}}

#shellcheck disable=1090
[ -e ~/.profile.local ] && . ~/.profile.local

# vim:foldmethod=marker
# vi:ts=4:sw=4:noexpandtab
