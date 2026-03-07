#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# GPG and SSH agent configuration

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
			# Use gpg-agent for SSH on other systems
			if command -v gpgconf >/dev/null 2>&1; then
				SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
				export SSH_AUTH_SOCK
			fi
			;;
	esac
fi
