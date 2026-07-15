#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# Terminal color capability detection, Tinty env exports, and
# dircolors(1)/LS_COLORS setup.
#
# Tinty owns terminal/editor theme application (see
# .config/tinted-theming/tinty/config.toml). This file exports the
# tinted-shell path/feature variables Tinty and tinted-shell's own
# tooling expect to find, but it deliberately does not source
# tinted-shell's profile_helper.sh on every shell startup, and does not
# duplicate its palette into shell associative arrays: no retained
# consumer in this tree (tinted-nvim, Ghostty's theme-file hook,
# tinted-delta's git include) reads profile_helper.sh's exported
# base16-*/chbg aliases or requires it to run. Tinty's own completion
# generation is handled separately, not here. Beyond the Tinty exports,
# this file only handles ls(1)/grep(1) LS_COLORS.

# Export tinted-shell's path/feature variables when Tinty is installed.
# Cheap, side-effect-free exports for any consumer that reads them.
if command -v tinty > /dev/null 2>&1; then
	BASE16_SHELL_PATH="${XDG_DATA_HOME}/tinted-theming/tinty/repos/tinted-shell"
	TINTED_SHELL_ENABLE_BASE16_VARS=1
	TINTED_SHELL_ENABLE_BASE24_VARS=1

	export \
		BASE16_SHELL_PATH \
		TINTED_SHELL_ENABLE_BASE16_VARS \
		TINTED_SHELL_ENABLE_BASE24_VARS
fi

# Use tput(1) to determine the number of supported colors.
TERMINAL_COLORS="$(tput colors 2> /dev/null || echo -1)"

# If the terminal supports at least 8 colors, set up dircolors(1). Prefer
# the tracked dir_colors config; fall back to the platform default
# database when it is absent.
if [ "$TERMINAL_COLORS" -ge '8' ]; then
	# linux* is a broad catch-all so musl-libc Linux (Alpine, OpenWRT,
	# some Yocto images -- $OSTYPE reports e.g. "linux-musl") gets the
	# same GNU-style dircolors handling as glibc Linux: BusyBox/musl
	# coreutils on these platforms are typically GNU-compatible enough
	# for this. Real BSD values (freebsd13.x, openbsd7.x, netbsd,
	# dragonfly, ...) never start with the literal string "bsd", so the
	# pattern must contain a wildcard on both sides to match via
	# substring; dragonfly does not contain "bsd" at all and needs its
	# own arm.
	case "$OSTYPE" in
		linux*)
			_dircolors_cmd='dircolors'
			;;
		*bsd* | dragonfly* | darwin*)
			if command -v gdircolors > /dev/null 2>&1; then
				_dircolors_cmd='gdircolors'
			elif command -v dircolors > /dev/null 2>&1; then
				# Nix-on-macOS (and some BSD GNU-coreutils installs)
				# ship unprefixed GNU dircolors rather than Homebrew's
				# g-prefixed naming convention. There is no native
				# BSD/Darwin dircolors to collide with, so an unprefixed
				# match here can only be a real GNU-compatible binary.
				_dircolors_cmd='dircolors'
			else
				_dircolors_cmd=''
			fi
			;;
		*)
			_dircolors_cmd=''
			;;
	esac

	if [ -n "$_dircolors_cmd" ] && command -v "$_dircolors_cmd" > /dev/null 2>&1; then
		_dircolors_config="${XDG_CONFIG_HOME}/coreutils/dir_colors"
		if [ -r "$_dircolors_config" ]; then
			eval "$("$_dircolors_cmd" "$_dircolors_config")"
		else
			eval "$("$_dircolors_cmd")"
		fi
		unset _dircolors_config
	fi
	unset _dircolors_cmd
fi
