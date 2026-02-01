#!/bin/sh
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# .config/shell/environment.sh
#
# Shared environment variables for all shells
# POSIX-compatible, can be sourced by Bash, Zsh, and other shells

# Define a few finite-length POSIX.1 EREs
#
# IPv4 addresses
IPv4_ADDRESS='(([01][[:digit:]]{2}|2[0-4][[:digit:]]|25[0-5]|[[:digit:]]{1,2})\.){3}([01][[:digit:]]{2}|2[0-4][[:digit:]]|25[0-5]|[[:digit:]]{1,2})'
# IPv4 CIDR subnet notation
IPv4_SUBNET="${IPv4_ADDRESS}(\\/[[:digit:]]{1,2})?"
# hostnames
HOSTNAME_REGEX='[[:digit:]a-zA-Z-][[:digit:]a-zA-Z\.-]{1,63}\.[a-zA-Z]{2,6}\.?'

export IPv4_ADDRESS IPv4_SUBNET HOSTNAME_REGEX

# GPG_TTY setup (if gpg-agent is available)
if command -v gpg-agent >/dev/null 2>&1; then
	GPG_TTY=$(tty)
	export GPG_TTY

	# SSH_AUTH_SOCK setup (not on macOS which uses its own keychain)
	case "$(uname -s)" in
		Darwin)
			# macOS uses its own SSH agent
			;;
		*)
			if command -v gpgconf >/dev/null 2>&1; then
				SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
				export SSH_AUTH_SOCK
			fi
			;;
	esac
fi
