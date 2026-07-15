#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# 20-path.sh
#
# Interactive PATH normalization and platform-specific additions.
#
# The canonical _ensure_path_contains() implementation lives in
# .config/shell/path.sh (sourced by .profile); it must not be
# redefined here.

# Guard against the case where this interactive shell inherited an
# exported __PROFILE_SOURCED guard from a parent process but never
# itself sourced .profile: functions and PATH edits made by that
# other process are not inherited, only the plain exported variable
# is.  This reliably happens whenever __PROFILE_SOURCED has been
# imported into the desktop session's environment once at login
# (e.g. via `systemctl --user import-environment`), since every
# graphical app spawned afterward -- including each new terminal
# tab's shell -- starts with the guard already set.  When detected,
# redo both things .profile would have done: restore the function,
# then reapply the same baseline entries it adds.
if ! command -v _ensure_path_contains > /dev/null 2>&1; then
	# shellcheck source=../path.sh
	# shellcheck disable=SC1091
	[ -f "${XDG_CONFIG_HOME}/shell/path.sh" ] && . "${XDG_CONFIG_HOME}/shell/path.sh"

	if command -v _ensure_path_contains > /dev/null 2>&1; then
		_ensure_path_contains "${XDG_DATA_HOME}/cargo/bin"
		_ensure_path_contains "${XDG_BIN_HOME}"
		_ensure_path_contains "${HOME}/bin"
	fi
fi

# Zsh has built-in PATH deduplication
if [ -n "$ZSH_VERSION" ]; then
	# shellcheck disable=SC2034  # path is used by Zsh internally
	typeset -U PATH path
fi

# Platform-specific additions. Baseline paths (XDG bin, ~/bin, Cargo
# bin) are handled above and by .profile; this section only adds
# entries specific to one platform.
if [[ "$OSTYPE" =~ 'darwin' ]]; then
	# /opt/homebrew/bin/brew is the one artifact guaranteed to exist
	# after any successful Homebrew install (the standard curl
	# installer, a manual install, or the less-common .pkg installer),
	# regardless of whether the installer's suggested
	# `eval "$(brew shellenv)"` profile line was ever added -- this
	# project's own .zprofile/.bash_profile replace the user's shell
	# profile outright, so that line is never present here.
	# /opt/homebrew/etc/paths is a .pkg-installer-only artifact; the
	# standard curl-based installer used by virtually every fresh
	# Apple Silicon Mac never creates it, so it must not be the gate.
	if [ -x /opt/homebrew/bin/brew ]; then
		_ensure_path_contains /opt/homebrew/sbin
		_ensure_path_contains /opt/homebrew/bin
	fi
fi

export PATH
