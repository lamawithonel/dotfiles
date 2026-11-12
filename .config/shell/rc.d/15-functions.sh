#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# 15-functions.sh
#
# The canonical implementations live in .config/shell/functions.sh
# (sourced by .profile); they must not be redefined here.

# Same failure mode as 20-path.sh: a shell that inherited an exported
# __PROFILE_SOURCED guard skips .profile, and functions are never
# inherited through the environment, only the guard variable is.
if ! command -v rngstring > /dev/null 2>&1; then
	# shellcheck source=../functions.sh
	# shellcheck disable=SC1091
	[ -f "${XDG_CONFIG_HOME}/shell/functions.sh" ] && . "${XDG_CONFIG_HOME}/shell/functions.sh"
fi
