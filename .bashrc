#!/usr/bin/env bash

# This file is only for Bash.  Exit if the shell is NOT Bash.
[[ -n "$BASH_VERSION" ]] || exit 1

# These should be set in /etc/profile or ~/.profile, but just in case...
XDG_CACHE_HOME=${XDG_CACHE_HOME:-${HOME}/.cache}
XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-${HOME}/.config}
XDG_DATA_HOME=${XDG_DATA_HOME:-${HOME}/.local/share}
export XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME

# Setup XDG directories
[[ -n "$BASH_CONFIG_HOME" ]] || export BASH_CONFIG_HOME="${XDG_CONFIG_HOME}/bash"
[[ -n "$BASH_DATA_HOME"   ]] || export BASH_DATA_HOME="${XDG_DATA_HOME}/bash"
[[ -d "$BASH_CONFIG_HOME" ]] || mkdir -pZ "$BASH_CONFIG_HOME" >&/dev/null || mkdir -p "$BASH_CONFIG_HOME"
[[ -d "$BASH_DATA_HOME"   ]] || mkdir -pZ "$BASH_DATA_HOME" >&/dev/null   || mkdir -p "$BASH_DATA_HOME"

# It's common to source this file from other places.  If this happens for
# a non-interactive shell, it's a good idea to skip anything related to
# interactivity.  Namely, everything afer this.
case "${-}" in
	*i*) ;;
	*) return ;;
esac

# {{{ Miscellaneous shell options

# Check the window size after each command and, if necessary, update the
# values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will match
# all files and zero or more directories and subdirectories.
shopt -s globstar

# }}}

# {{{ History Settings

# Append to the history file, don't overwrite it
shopt -s histappend

# Store history in the XDG-standard location
HISTFILE="${BASH_DATA_HOME}/history"

# Ignore lines starting with a [:space:] and lines which are duplicates of
# the previous command.  Also, erase older duplicates.
HISTCONTROL=ignoreboth:erasedups

# Number of commands to keep in the scrollback history
HISTSIZE=1000

# Maximum size of $HISTFILE, in bytes
HISTFILESIZE=2000

export HISTFILE HISTCONTROL HISTSIZE HISTFILESIZE
# }}}

# {{{ Third-Party Extensions

[[ -d "${BASH_DATA_HOME}/ext" ]] || mkdir "${BASH_DATA_HOME}/ext"

if [[ ! -d ${BASH_DATA_HOME}/ext/bash-preexec ]]; then
	git clone https://github.com/rcaloras/bash-preexec.git "${BASH_DATA_HOME}/ext/bash-preexec"
fi

# }}}

# {{{ System Bash Completion
#
# Enable programmable completion features for non-root users.  Ignore for
# for priveledged users who may be open to shell command injection attacks.
if ! shopt -oq posix && [ $EUID -ne 0 ]; then
	if [ -f /usr/local/etc/profile.d/bash_completion.sh ]; then
		#shellcheck disable=1091
		source /usr/local/etc/profile.d/bash_completion.sh
	elif [ -f /etc/bash_completion ]; then
		#shellcheck disable=1091
		source /etc/bash_completion
	elif [ -f /etc/profile.d/bash_completion.sh ]; then
		#shellcheck disable=1091
		source /etc/profile.d/bash_completion.sh
	elif [ -f /etc/profile.d/bash-completion.sh ]; then
		#shellcheck disable=1091
		source /etc/profile.d/bash-completion.sh
	fi
fi
# }}} Bash Completion

# {{{ Color

if [ -z "$KONSOLE_PROFILE_NAME" ]; then
	BASE16_SHELL="${XDG_DATA_HOME}/base16/base16-shell/"
	if [ -s "${BASE16_SHELL}/profile_helper.sh" ]; then
		eval "$("${BASE16_SHELL}/profile_helper.sh")"
	fi
fi

# Use tput(1) to determine the number of supported colors.
TERMINAL_COLORS="$(tput colors 2>/dev/null || echo -1)"

# If the terminal supports at least 8 colors, source the color theme and
# setup dircolors(1)
if [[ "$TERMINAL_COLORS" -ge '8' ]]; then
	# shellcheck source=.config/bash/colors.bash
	[ -f "${BASH_CONFIG_HOME}/colors.bash" ] && source "${BASH_CONFIG_HOME}/colors.bash"

	# dircolors(1)
	case "$OSTYPE" in
		*-gnu)
			if command -v dircolors &> /dev/null; then
				eval "$(dircolors "${XDG_CONFIG_HOME}/coreutils/dir_colors")"
			fi
			;;
		bsd*|darwin*)
			if command -v gdircolors &> /dev/null; then
				eval "$(gdircolors "${XDG_CONFIG_HOME}/coreutils/dir_colors")"
			fi
			;;
	esac
else
	if [ -f "${XDG_CONFIG_HOME}/bash/colors_null.bash" ]; then
		# shellcheck source=.config/bash/colors_null.bash
		source "${XDG_CONFIG_HOME}/bash/colors_null.bash"
	fi
fi
# }}} Color Support

# {{{ Prompt Setup

# Trim the working directory string in $PS1 to this many elements
PROMPT_DIRTRIM=4

git_is_available() {
	command -v git &> /dev/null
}

dir_is_a_git_repo() {
	git rev-parse --git-dir &>/dev/null
}

##
# _prompt_command()
#
# This function is executed each time the shell returns, dynamically generating
# the prompt.  It takes no arguments, however it reads a few environment
# variables.
#
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

	# Display Git status and working branch, if applicable.
	# FIXME: Git's standard status format may change from version to version.
	#        This should instead use `git status --porcelain`, which uses
	#        a stable, versioned output format.
	if git_is_available && dir_is_a_git_repo; then
		local git_status git_color branch

		git_status="$(git status -unormal 2>&1)"

		if [[ "$git_status" =~ nothing\ to\ commit ]]; then
			git_color=${ANSI[GREEN]}
		elif [[ "$git_status" =~ nothing\ added\ to\ commit\ but\ untracked\ files\ present ]]; then
			git_color=${ANSI[MAGENTA]}
		else
			git_color=${ANSI[RED]}
		fi

		branch="$(git symbolic-ref -q --short HEAD || echo "($(git describe --all --contains HEAD))")"

		# shellcheck disable=SC1117
		PS1+="\[${git_color}\][${branch}]\[${ANSI[RESET]}\] "
	fi

	# Bash prompt character ('#' for root, '$' for everybody else)
	PS1+='\$ '
}

# shellcheck disable=SC2086
PROMPT_COMMAND=_prompt_command

# }}} Prompt Setup

# {{{ Functions & Aliases

if command -v nvim &> /dev/null; then
	alias vi='nvim'
elif command -v vim &> /dev/null; then
	alias vi='vim'
fi

# Make common file operations interactive for safety
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Make tee append by default (for safety)
alias tee='tee -a'

# Use $COLUMNS as the sdiff width
[ -n "$COLUMNS" ] && alias sdiff='sdiff -w $COLUMNS'

if [[ "$TERMINAL_COLORS" -ge '8' ]]; then
	# Enable color support in grep(1) and ls(1), and add a few short-hands
	case "$OSTYPE" in
		*-gnu)
			alias grep='grep --color=auto'
			alias fgrep='fgrep --color=auto'
			alias egrep='egrep --color=auto'

			alias ls='ls -F --color=auto'
			alias ll='ls -lF --color=auto'
			alias la='ls -alF --color=auto'
			alias l='ls -CF --color=auto'
			;;
		bsd*|darwin*)
			if command -v ggrep &> /dev/null; then
				alias grep='ggrep --color=auto'
				alias fgrep='gfgrep --color=auto'
				alias egrep='gegrep --color=auto'
			fi

			if command -v gls &> /dev/null; then
				alias ls='gls -F --color=auto'
				alias ll='gls -lF --color=auto'
				alias la='gls -alF --color=auto'
				alias l='gls -CF --color=auto'
			fi
			;;
		*)
			;;
	esac
else
	alias ls='ls -F'
	alias ll='ls -alF'
	alias la='ls -A'
	alias l='ls -CF'
fi

# An improved version of Red Hat's pathmunge() function
#
# Takes a fully-qualified directory path and adds it to the PATH variable.
# By default it will add it to the begining of the PATH variable.  If the
# second argument is set to "after" it will append it to the end of PATH
# instead.  If the directory path does not exist or is not a directory, it
# will remove the element from PATH.
_ensure_path_contains() {
	# Must be a fully-qualifed path
	echo "$1" | grep -qE '^/[[:print:]]+$' || return 1

	if [ -d "$1" ]; then
		if ! echo "$PATH" | grep -qE "(^|:)${1}($|:)"; then
			if [ "$2" = 'after' ]; then
				PATH="${PATH}:${1}"
			else
				PATH="${1}:${PATH}"
			fi
		fi
	else
		PATH="$(echo "$PATH" | sed "s:\(^|\:\)${1}::g")"
	fi

	export PATH
}

export _ensure_path_contains

# }}} Functions & Aliases

# {{{ Setup gpg-agent(1)

if command -v gpg-agent &> /dev/null; then
	GPG_TTY=$(tty)

	if [[ ! "$OSTYPE" =~ ^darwin ]]; then
		SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
	fi

	export GPG_TTY SSH_AUTH_SOCK

	update_gpg_agent_startup_tty() {
		gpg-connect-agent UpdateStartupTTY /bye &> /dev/null
	}
fi

# }}} Setup gpg-agent(1)

# {{{ Misc. Environment Variables

# Define a few finite-length POSIX.1 EREs
#
# IPv4 addresses
IPv4_ADDRESS='(([01][[:digit:]]{2}|2[0-4][[:digit:]]|25[0-5]|[[:digit:]]{1,2})\.){3}([01][[:digit:]]{2}|2[0-4][[:digit:]]|25[0-5]|[[:digit:]]{1,2})'
# IPv4 CIDR subnet notation
IPv4_SUBNET="${IPv4_ADDRESS}(\\/[[:digit:]]{1,2})?"
# hostnames
HOSTNAME_REGEX='[[:digit:]a-zA-Z-][[:digit:]a-zA-Z\.-]{1,63}\.[a-zA-Z]{2,6}\.?'

export IPv4_ADDRESS IPv4_SUBNET HOSTNAME_REGEX
# }}} Misc. Environment Variables

# {{{ Local Additions

# Source an un-tracked file for private and per-machine commands
if [ -f ~/.bashrc.local ]; then
	#shellcheck disable=1090
	source ~/.bashrc.local
fi
# }}} Local Additions

# {{{ iTerm2

_iterm2_integration_dir="${XDG_DATA_HOME}/iterm2/iterm2-website"
_iterm2_integration_script="${_iterm2_integration_dir}/source/shell_integration/bash"
_iterm2_check="${_iterm2_integration_dir}/source/utilities/it2check"

if [ -x "$_iterm2_check" ] && "$_iterm2_check"; then
	# shellcheck source=.local/share/iterm2/iterm2-website/source/shell_integration/bash
	[ -f "$_iterm2_integration_script" ] && source "$_iterm2_integration_script"
fi

# }}}

# {{{ $PATH Setup

# Most of this could happen elsewhere in this script, but doing it all here
# gives a clean look at what order they'll appear in the final $PATH variable.
# Items added earlier will appear later in the variable (lower precedence).

if [ -x "$_iterm2_check" ] && "$_iterm2_check"; then
	_ensure_path_contains "${XDG_DATA_HOME}/iterm2/iterm2-website/source/utilities"
fi

_ensure_path_contains "${XDG_DATA_HOME}/tfenv/bin"
_ensure_path_contains "${XDG_DATA_HOME}/perlbrew/bin"
_ensure_path_contains "${XDG_DATA_HOME}/cabal/bin"
_ensure_path_contains "${XDG_DATA_HOME}/volta/bin"
_ensure_path_contains "${XDG_DATA_HOME}/rvm/bin"
_ensure_path_contains "${XDG_DATA_HOME}/cargo/bin"
_ensure_path_contains "${XDG_DATA_HOME}/pyenv/bin"

if command -v pyenv &> /dev/null; then
	_ensure_path_contains "${XDG_DATA_HOME}/pyenv/shims"
	_ensure_path_contains "${XDG_DATA_HOME}/pyenv/plugins/pyenv-virtualenv/shims"
fi

# Add private /bin directories to $PATH
_ensure_path_contains ~/bin

export PATH

# }}} $PATH Setup

# {{{ Perlbrew

#shellcheck disable=1090
[[ -d "${XDG_DATA_HOME}/perlbrew" ]] && source "${XDG_DATA_HOME}/perlbrew/etc/bashrc"

# }}}

# {{{ SDKman

#shellcheck disable=1090
[[ -s "${XDG_DATA_HOME}/bin/sdkman-init.sh" ]] && source "${XDG_DATA_HOME}/bin/sdkman-init.sh"

# }}}

# {{{ pyenv

if command -v pyenv &> /dev/null; then
	eval "$(pyenv init - | grep -F -ve 'pyenv init' -ve 'PATH')" && eval "$(pyenv virtualenv-init - | grep -v 'PATH')"
fi

# }}}

# {{{ pipenv

if pipenv --version &> /dev/null; then
	eval "$(pipenv --completion)"
fi

# }}}

# {{{ RVM

# Load RVM into a shell session *as a function*
#shellcheck disable=1090
[[ -s "${XDG_DATA_HOME}/rvm/scripts/rvm" ]] && source "${XDG_DATA_HOME}/rvm/scripts/rvm"

# }}} RVM

# {{{ bash-preexec

if [[ -f "${BASH_DATA_HOME}/ext/bash-preexec/bash-preexec.sh" ]]; then
	#shellcheck source=.local/share/bash/ext/bash-preexec/bash-preexec.sh
	source "${BASH_DATA_HOME}/ext/bash-preexec/bash-preexec.sh"

	preexec_functions=(
		update_gpg_agent_startup_tty
	)
fi

# }}}

# {{{ $PATH print

# Print $PATH for manual verification
if [[ "$TERMINAL_COLORS" -ge '8' ]]; then
	# shellcheck disable=SC2001
	echo "${BASE16[BASE08]}PATH${BASE16[BASE05]}=$(sed "s/\\([^:]\\+\\)\\(:\\)\\?/${BASE16[BASE06]}\\1${BASE16[BASE0C]}\\2/g" <<<"$PATH")"
else
	echo "PATH=\"${PATH}\""
fi

# }}} $PATH print

# {{{ Cleanup

unset -v _iterm2_check _iterm2_integration_script _iterm2_integration_dir
unset -f _ensure_path_contains

# }}}

# vim:foldmethod=marker
# vi:ts=4:sw=4:noexpandtab
