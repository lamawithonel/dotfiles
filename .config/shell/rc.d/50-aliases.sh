#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# Common aliases for both Bash and Zsh

# Editor
if command -v nvim >/dev/null 2>&1; then
	alias vi='nvim'
elif command -v vim >/dev/null 2>&1; then
	alias vi='vim'
fi

# Make common file operations interactive for safety
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Use $COLUMNS as the sdiff width
[ -n "$COLUMNS" ] && alias sdiff='sdiff -w $COLUMNS'

# Screen scrollback/terminal alias (migrated from ~/.bash_aliases)
if command -v screen >/dev/null 2>&1; then
	alias screen='screen -h 8192 -T screen-256color'
fi

# Kill a stuck GnuPG smartcard daemon (migrated from ~/.bash_aliases)
if command -v gpg-connect-agent >/dev/null 2>&1; then
	alias gpg-kill-scdaemon='gpg-connect-agent "SCD KILLSCD" "SCD BYE" /bye'
fi

# puppet-lint wrapper that always shows the filename (migrated from
# ~/.bash_aliases)
if command -v puppet-lint >/dev/null 2>&1; then
	alias puppet-lint='puppet-lint --with-filename'
fi

# Linux clipboard aliases via xsel (migrated from ~/.bash_aliases)
if command -v xsel >/dev/null 2>&1; then
	alias pbcopy='xsel --clipboard --input'
	alias pbpaste='xsel --clipboard --output'
fi

# Color support for grep and ls
if [ "$TERMINAL_COLORS" -ge '8' ]; then
	# Enable color support in grep(1) and ls(1), and add a few short-hands
	# linux* is a broad catch-all so musl-libc Linux (Alpine, OpenWRT,
	# some Yocto images -- $OSTYPE reports e.g. "linux-musl") gets the
	# same GNU-style color flags as glibc Linux: BusyBox/musl coreutils
	# on these platforms are typically GNU-compatible enough for
	# --color=auto. Real BSD values (freebsd13.x, openbsd7.x, netbsd,
	# dragonfly, ...) never start with the literal string "bsd", so the
	# pattern must contain a wildcard on both sides to match via
	# substring; dragonfly does not contain "bsd" at all and needs its
	# own arm.
	case "$OSTYPE" in
		linux*)
			alias grep='grep --color=auto'
			alias fgrep='fgrep --color=auto'
			alias egrep='egrep --color=auto'

			alias ls='ls -F --color=auto'
			alias ll='ls -lF --color=auto'
			alias la='ls -alF --color=auto'
			alias l='ls -CF --color=auto'
			;;
		*bsd* | dragonfly* | darwin*)
			if command -v ggrep >/dev/null 2>&1; then
				alias grep='ggrep --color=auto'
				alias fgrep='ggrep -F --color=auto'
				alias egrep='ggrep -E --color=auto'
			elif command -v grep >/dev/null 2>&1; then
				# Nix-on-macOS ships unprefixed GNU grep rather than
				# Homebrew's g-prefixed naming convention, and modern
				# BSD/Darwin system greps (FreeBSD's base grep is GNU
				# grep; macOS/OpenBSD/NetBSD grep accept --color=auto
				# as a documented GNU-compatibility flag) also tolerate
				# this, so falling back to the unprefixed name is safe.
				alias grep='grep --color=auto'
				alias fgrep='fgrep --color=auto'
				alias egrep='egrep --color=auto'
			fi

			# No unprefixed fallback for ls/gls: unlike grep, native
			# BSD/Darwin ls does NOT understand GNU's --color=auto (it
			# uses -G/CLICOLOR instead), so assuming an unprefixed `ls`
			# found here is a GNU stand-in would break plain `ls` on any
			# real BSD/Darwin host that lacks gls. Only alias when the
			# g-prefixed GNU binary is actually present.
			if command -v gls >/dev/null 2>&1; then
				alias ls='gls -F --color=auto'
				alias ll='gls -lF --color=auto'
				alias la='gls -alF --color=auto'
				alias l='gls -CF --color=auto'
			fi
			;;
		*) ;;
	esac
else
	alias ls='ls -F'
	alias ll='ls -alF'
	alias la='ls -A'
	alias l='ls -CF'
fi
