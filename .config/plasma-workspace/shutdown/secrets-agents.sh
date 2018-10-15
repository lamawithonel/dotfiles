#!/bin/sh

_user_pgrep() {
	ps -U "$(id -u)" -o pid,comm | awk "/^[[:blank:]]*[[:digit:]]+[[:blank:]]+${1}$/ {print \$1}"
}

# Only kill stuff if this is the lone login session for the current user
#shellcheck disable=SC2009
if [ "$(ps -U "$(id -u)" -o lsession= | grep -v '^-' | sort -u | wc -l)" = '1' ]; then
	if command -v gnome-keyring-daemon > /dev/null; then
		kill "$(_user_pgrep gnome-keyring-d)"
	fi

	if command -v gpg-agent > /dev/null; then
		gpg-connect-agent 'SCD KillSCD' /bye > /dev/null
		gpg-connect-agent 'KillAgent'   /bye > /dev/null
	elif command -v ssh-agent > /dev/null 2>&1; then
		gpg-agent -k
	fi
fi
# vi:ts=4:sw=4:noexpandtab
