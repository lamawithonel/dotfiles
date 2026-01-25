#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# 410-pyenv.sh
#
# Python environment manager initialization
# Category: 400-499 Language/tool environment managers
# Note: Uses Bash syntax but is compatible with Zsh

if command -v pyenv >/dev/null 2>&1; then
	# pyenv init includes completion setup
	if [ -n "$BASH_VERSION" ]; then
		eval "$(pyenv init - --no-push-path bash)"
		# pyenv virtualenv-init also includes its completion setup
		eval "$(pyenv virtualenv-init - bash | grep -vF 'export PATH')"
	elif [ -n "$ZSH_VERSION" ]; then
		eval "$(pyenv init - --no-push-path zsh)"
		# pyenv virtualenv-init also includes its completion setup
		eval "$(pyenv virtualenv-init - zsh | grep -vF 'export PATH')"
	fi
fi
