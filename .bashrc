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

# {{{ bash-preexec hooks

# Setup bash-preexec and bash-postexec hooks.
# These must be configured after shared rc.d but before the fallback prompt.
if [ -f "${BASH_DATA_HOME}/ext/bash-preexec/bash-preexec.sh" ]; then
#shellcheck source=./.local/share/bash/ext/bash-preexec/bash-preexec.sh
source "${BASH_DATA_HOME}/ext/bash-preexec/bash-preexec.sh"

preexec_functions=(
update_gpg_agent_startup_tty
)

export preexec_functions
fi

# }}}

# {{{ Fallback Prompt (if Starship not available)

# This is only used if Starship is not installed
if ! command -v starship &> /dev/null; then
git_is_available() {
command -v git &> /dev/null
}

dir_is_a_git_repo() {
git rev-parse --git-dir &> /dev/null
}

_prompt_command() {

# Start with a boxed timestamp.  Color based on exit status of the previous
# command.
# shellcheck disable=SC2086
if [[ "${PIPESTATUS[-1]}" -eq '0' ]]; then
# shellcheck disable=SC1117
PS1="\[${ANSI[GREEN]}\][\\t]\[${ANSI[RESET]}\] "
else
# shellcheck disable=SC1117
PS1="\[${ANSI[BRRED]}\][\\t]\[${ANSI[RESET]}\] "
fi

# If connected via SSH, display IP address of the client.
# shellcheck disable=SC1117
[ -n "$SSH_CLIENT" ] && PS1+="\[${BASE16[BASE0A]}\](${SSH_CLIENT%% *})\[${ANSI[RESET]}\]"

# Username, Host, and Working Directory
if [[ "$TERMINAL_COLORS" -ge '8' ]]; then
# Gentoo-style, color-indicated root prompt
if [ $EUID -eq 0 ]; then
# shellcheck disable=SC1117
PS1+="\[${BASE16[BASE09]}\]\\h\[${BASE16[BASE0D]}\]:\[${BASE16[BASE05]}\]\\w\[${ANSI[RESET]}\] "
else
# shellcheck disable=SC1117
PS1+="\[${BASE16[BASE0B]}\]\\u@\\h\[${BASE16[BASE05]}\]:\[${BASE16[BASE0A]}\]\\w\[${ANSI[RESET]}\] "
fi
else
PS1+="\\u@\\h:\\w"
fi

# Git status (if in a git repo)
if git_is_available && dir_is_a_git_repo; then
PS1+=" \[${ANSI[RED]}\]["
PS1+="$(git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/')"
PS1+="]\[${ANSI[RESET]}\]"
fi

# End with a newline and the prompt character
PS1+="\\n\$ "
}

PROMPT_COMMAND=_prompt_command
fi

# }}}

# {{{ Cleanup

unset -v _iterm2_check _iterm2_integration_script _iterm2_integration_dir

# }}}
