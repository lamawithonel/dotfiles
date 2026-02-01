#!/usr/bin/env bash
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker

# Style Guide:
# - Wrap comments at the first word extended beyond 72 characters, and do
#   not exceed 80 characters.  Wrap before 72 characters if the last word
#   would extend beyond 80 characters.  Exceptions: URLs, long paths, and
#   code examples.
# - Prefer POSIX syntax over Bash-specific syntax, except in the following
#   cases:
#     a. Where Bash features are faster to execute, e.g., `[[ "abc123" =~ c1 ]]
#        instead of `echo abc123 | grep -q c1`.
#     b. Where Bash features are significantly more readable, e.g.,  `<<-`
#        heredocs with indented content and `source` insead of `.`.
# - Use Bash features that add safety, e.g., `set -o pipefail`, `local`,
#  `readonly`, `typeset`, etc.
# - Quote strings with 'hard quotes' unless variable expansion is needed.
# - Enclose all variables in curly braces when they are part of a larger
#   string, e.g., "this ${string}", but not when they are a standalone, e.g.,
#   "$solitary_variable".
# - Prefix all internal functions with an underscore, e.g., `_function_name`.
# - Unset all functions and variables not needed after setup.
# - Batch unsets as a micro-optimization-- startup speeed matters!
# - Use XDG Base Directory Specification wherever possible.
#

# For debugging only.  Do not leave uncommented!
#$_shopts="$(set +o)"
#set -o errexit
#set -o nounset

_fail() {
	echo "ERROR: ${*}" >&2
	return 1
}

# This file is only for Bash.  Exit if the shell is NOT Bash.
[ -n "$BASH_VERSION" ] || _fail "File incompatible with the current shell: ${0}"

# Everything after this point is intended for interactive shells only.
# Exit if the shell is not interactive.
[[ $- != *i* ]] && return

# If .profile hasn't been sourced yet (e.g., non-login interactive shell),
# source .bash_profile which will handle it, then continue with interactive setup
if [ -z "$__PROFILE_SOURCED" ]; then
	# shellcheck source=./.bash_profile
	[ -f "${HOME}/.bash_profile" ] && source "${HOME}/.bash_profile"
fi

# If profile still not sourced after attempting, something is wrong - exit
[ -z "$__PROFILE_SOURCED" ] && return

# {{{ Miscellaneous shell options

# Check the window size after each command and, if necessary, update the
# values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will match
# all files and zero or more directories and subdirectories.
shopt -s globstar

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

# {{{ Cleanup

unset -v _iterm2_check _iterm2_integration_script _iterm2_integration_dir

# }}}
