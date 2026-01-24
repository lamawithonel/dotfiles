#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# 500-completions.sh
#
# Tool completions (shell-specific handling)
# Category: 500-599 Tool completions
# Note: Uses Bash syntax but is compatible with Zsh

# pipenv
if pipenv --version >/dev/null 2>&1; then
	if [ -n "$BASH_VERSION" ]; then
		eval "$(pipenv --completion 2>/dev/null || _PIPENV_COMPLETE=bash_source pipenv)"
	elif [ -n "$ZSH_VERSION" ] && [ -d "$ZSH_CACHE_HOME" ]; then
		# Save pipenv completion to fpath directory for autoloading
		{ pipenv --completion 2>/dev/null || _PIPENV_COMPLETE=zsh_source pipenv; } > "${ZSH_CACHE_HOME}/_pipenv" 2>/dev/null
	fi
fi

# Rust (rustup and cargo)
if command -v rustup >/dev/null 2>&1; then
	if [ -n "$BASH_VERSION" ]; then
		eval "$(rustup completions bash rustup)"
		eval "$(rustup completions bash cargo)"
	elif [ -n "$ZSH_VERSION" ] && [ -d "$ZSH_CACHE_HOME" ]; then
		# Save rustup completions to fpath directory for autoloading
		rustup completions zsh rustup > "${ZSH_CACHE_HOME}/_rustup" 2>/dev/null
		rustup completions zsh cargo > "${ZSH_CACHE_HOME}/_cargo" 2>/dev/null
	fi
fi

# probe-rs
if command -v probe-rs >/dev/null 2>&1; then
	# FIXME: Why doesn't `probe-rs` shell completion work on my MacBook?
	if [[ ! "$OSTYPE" =~ 'darwin' ]]; then
		if [ -n "$BASH_VERSION" ]; then
			eval "$(probe-rs complete install -m)"
		elif [ -n "$ZSH_VERSION" ] && [ -d "$ZSH_CACHE_HOME" ]; then
			# Save probe-rs completion to fpath directory for autoloading
			probe-rs complete install -m > "${ZSH_CACHE_HOME}/_probe-rs" 2>/dev/null
		fi
	fi
fi
