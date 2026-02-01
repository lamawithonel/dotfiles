#!/usr/bin/env zsh
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker

# Style Guide:
# - Wrap comments at the first word extended beyond 72 characters, and do
#   not exceed 80 characters.  Wrap before 72 characters if the last word
#   would extend beyond 80 characters.  Exceptions: URLs, long paths, and
#   code examples.
# - Use XDG Base Directory Specification wherever possible.
#

# For debugging only.  Do not leave uncommented!
#set -o errexit
#set -o nounset

# Exit if the shell is not interactive.
[[ -o interactive ]] || return

# If .profile hasn't been sourced yet (e.g., non-login interactive shell),
# source .zprofile which will handle it
if [ -z "$__PROFILE_SOURCED" ]; then
	[ -f "${HOME}/.zprofile" ] && source "${HOME}/.zprofile"
	# If still not sourced, something is wrong
	[ -z "$__PROFILE_SOURCED" ] && return
fi

# {{{ Zsh Options

# Completion behavior - make Zsh feel like Bash
setopt BASH_AUTO_LIST       # List completions on first tab
setopt NO_AUTO_MENU         # Don't show menu on second tab
setopt NO_MENU_COMPLETE     # Don't insert first match automatically
setopt LIST_AMBIGUOUS       # Complete up to ambiguity point

# History improvements
setopt NO_BANG_HIST         # Disable ! history expansion
setopt INTERACTIVE_COMMENTS # Allow # comments in interactive shell
setopt EXTENDED_HISTORY     # Timestamps in history
setopt HIST_IGNORE_ALL_DUPS # Deduplicate history
setopt HIST_REDUCE_BLANKS   # Clean up whitespace in history
setopt HIST_VERIFY          # Show expanded history before executing
setopt APPEND_HISTORY       # Append to history file
setopt INC_APPEND_HISTORY   # Append immediately, not on exit

# Convenience features
setopt AUTO_CD              # Type directory name to cd into it
setopt AUTO_PUSHD           # cd pushes onto directory stack
setopt PUSHD_IGNORE_DUPS    # Don't duplicate dirs in stack

# Keep Zsh's better defaults
# - Array indexing starts at 1 (don't set KSH_ARRAYS)
# - Extended globs enabled by default

# }}}

# {{{ Completion System

# Add completion directories to fpath before compinit
# This must be done before compinit initializes completions

# Add RVM completion directory if RVM is installed
if [ -d "${XDG_DATA_HOME}/rvm/scripts/zsh/Completion" ]; then
	fpath=("${XDG_DATA_HOME}/rvm/scripts/zsh/Completion" $fpath)
fi

# Add custom completion cache directory for tool completions
if [ -d "$ZSH_CACHE_HOME" ]; then
	fpath=("$ZSH_CACHE_HOME" $fpath)
fi

# Initialize the completion system
autoload -Uz compinit

# Use XDG-standard location for completion cache
if [ -d "$ZSH_CACHE_HOME" ]; then
	compinit -d "${ZSH_CACHE_HOME}/zcompdump"
else
	compinit
fi

# }}}

# {{{ Key Bindings

# Emacs mode (like Bash default)
bindkey -e

# Standard key bindings
bindkey '^[[3~' delete-char          # Delete key
bindkey '^[[H'  beginning-of-line    # Home key
bindkey '^[[F'  end-of-line          # End key
bindkey '^[[1;5C' forward-word       # Ctrl+Right
bindkey '^[[1;5D' backward-word      # Ctrl+Left
bindkey '^R' history-incremental-search-backward
bindkey '^S' history-incremental-search-forward

# }}}

# {{{ Source shared RC files

# Source all shared configuration from rc.d directory
if [ -d "${XDG_CONFIG_HOME}/shell/rc.d" ]; then
	for _rc_file in "${XDG_CONFIG_HOME}/shell/rc.d/"*.sh; do
		[ -r "$_rc_file" ] && . "$_rc_file"
	done
	unset _rc_file
fi

# }}}
