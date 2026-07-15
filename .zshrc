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
	for _rc_file in "${XDG_CONFIG_HOME}/shell/rc.d/"*.sh(N); do
		[ -r "$_rc_file" ] && . "$_rc_file"
	done
	unset _rc_file
fi

# }}}
