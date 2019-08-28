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

# {{{ Secret Agents
if hash gnome-keyring-daemon 2>/dev/null; then
	eval "$(gnome-keyring-daemon --start 2> /dev/null)"
elif hash gpg-agent 2>/dev/null; then
	if systemctl --user -q is-active gpg-agent.socket > /dev/null 2>&1; then
		gpg-connect-agent /bye
	else
		gpgconf --launch gpg-agent
	fi
	SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket 2> /dev/null)"
elif hash ssh-agent 2>/dev/null; then
	_ssh_agent_pid() {
		ps -U "$(id -u)" -o pid,comm | awk '/^[[:blank:]]*[[:digit:]]+[[:blank:]]+ssh-agent$/ {print $1}'
	}
	SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent/ssh-agent.socket"
	mkdir -m 0700 "$XDG_RUNTIME_DIR/ssh-agent"
	eval "$(ssh-agent -s -a "$SSH_AUTH_SOCK" > /dev/null 2>&1)" || SSH_AGENT_PID=_ssh_agent_pid
	unset -f _ssh_agent_pid
fi
export SSH_AUTH_SOCK SSH_AGENT_PID
# }}} Secrets Agents


#shellcheck disable=1090
[ -e ~/.profile.local ] && . ~/.profile.local

# vim:foldmethod=marker
# vi:ts=4:sw=4:noexpandtab
