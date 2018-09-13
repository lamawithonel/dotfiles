#!/usr/bin/env bash

# This file is only for Bash.  Exit if the shell is NOT Bash.
[ -n "$BASH_VERSION" ] || exit 1

# Define and setup XDG directories
[[ -n "$BASH_CONFIG_HOME" ]] ||	BASH_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}/bash"
[[ -n "$BASH_DATA_HOME" ]]   || BASH_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/bash"
[[ -d "$BASH_CONFIG_HOME" ]] || mkdir -pZ "$BASH_CONFIG_HOME" >&/dev/null || mkdir -p "$BASH_CONFIG_HOME"
[[ -d "$BASH_DATA_HOME" ]]   || mkdir -pZ "$BASH_DATA_HOME" >&/dev/null   || mkdir -p "$BASH_DATA_HOME"

# It's common to source this file from other places.  If this happens for
# a non-interactive shell, it's OK-- and probably a good idea-- to skip anything
# related to interactivity.  Namely, that means everything afer this.
case "${-}" in
	*i*) ;;
	*) exit 1 ;;
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
HISTFILE="${BASH_DATA_HOME}/history"; export HISTFILE

# Ignore lines starting with a [:space:] and lines which are duplicates of
# the previous command.  Also, erase older duplicates.
HISTCONTROL=ignoreboth,erasedups

# Number of commands to keep in the scrollback history
HISTSIZE=1000

# Maximum size of $HISTFILE, in bytes
HISTFILESIZE=2000

export HISTFILE HISTCONTROL HISTSIZE HISTFILESIZE
# }}}

# {{{ System Bash Completion
#
# Enable programmable completion features for non-root users.  Ignore for
# for priveledged users who may be open to shell command injection attacks.
if ! shopt -oq posix && [ $EUID -ne 0 ]; then
	if [ -f /etc/bash_completion ]; then
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
	BASE16_SHELL="$HOME/.local/share/base16-shell/"
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
			if command -v dircolors >&/dev/null; then
				eval "$(dircolors ~/.config/coreutils/dir_colors)"
			fi
			;;
		bsd*)
			if command -v gdircolors >&/dev/null; then
				eval "$(gdircolors ~/.config/coreutils/dir_colors)"
			fi
			;;
	esac
else
	# shellcheck source=.config/bash/colors_null.bash
	[ -f ~/.config/bash/colors_null.bash ] && source ~/.config/bash/colors_null.bash
fi
# }}} Color Support

# {{{ Prompt Setup

# Trim the working directory string in $PS1 to this many elements
PROMPT_DIRTRIM=4

##
# __prompt_command()
#
# This function is executed each time the shell returns, dynamically generating
# the prompt.  It takes no arguments, however it reads a few environment
# variables.
#
__prompt_command() {

	# Start with a boxed timestamp.  Color based on exit status of the previous
	# command.
	# shellcheck disable=SC2086
	if [[ "${PIPESTATUS[-1]}" -eq '0' ]]; then
		PS1="\[${ANSI[GREEN]}\][\\t]\[${ANSI[RESET]}\] "
	else
		PS1="\[${ANSI[BRRED]}\][\\t]\[${ANSI[RESET]}\] "
	fi

	# If connected via SSH, display IP address of the client.
	[ -n "$SSH_CLIENT" ] && PS1+="\[${BASE16[BASE0A]}\](${SSH_CLIENT%% *})\[${ANSI[RESET]}\]"

	# Username, Host, and Working Directory
	if [[ "$TERMINAL_COLORS" -ge '8' ]]; then
		# Gentoo-style, color-indicated root prompt
		if [ $EUID -eq 0 ]; then
			PS1+="\[${BASE16[BASE09]}\]\\h\[${BASE16[BASE0D]}\]:\[${BASE16[BASE05]}\]\\w\[${ANSI[RESET]}\] "
		else
			PS1+="\[${BASE16[BASE0B]}\]\\u@\\h\[${BASE16[BASE05]}\]:\[${BASE16[BASE0A]}\]\\w\[${ANSI[RESET]}\] "
		fi
	else
		PS1+="\\u@\\h:\\w"
	fi

	# Display Git status and working branch, if applicable.
	# TODO: Cleanup using `git status --short`
	if command -v git >&/dev/null; then
		local git_status
		git_status="$(git status -unormal 2>&1)"
		if ! [[ "$git_status" =~ Not\ a\ git\ repo ]]; then
			# parse the porcelain output of git status
			if [[ "$git_status" =~ nothing\ to\ commit ]]; then
				local git_color=${BASE16[BASE0B]}
			elif [[ "$git_status" =~ nothing\ added\ to\ commit\ but\ untracked\ files\ present ]]; then
				local git_color=${BASE16[BASE0D]}
			else
				local git_color=${BASE16[BASE08]}
			fi

			if [[ "$git_status" =~ On\ branch\ ([^[:space:]]+) ]]; then
				branch=${BASH_REMATCH[1]}
			else
				# Detached HEAD. (branch=HEAD is a faster alternative.)
				branch="($(git describe --all --contains --abbrev=4 HEAD 2>/dev/null || echo HEAD))"
			fi

			# add the result to prompt
			PS1+="\[${git_color}\][${branch}]\[${ANSI[RESET]}\] "
		fi
	fi

	# Bash prompt character ('#' for root, '$' for everybody else)
	PS1+='\$ '
}

# shellcheck disable=SC2086
PROMPT_COMMAND=__prompt_command; export PROMPT_COMMAND

# }}} Prompt Setup

# {{{ Functions & Aliases

if command -v nvim >&/dev/null; then
	alias vi='nvim'
elif command -v vim >&/dev/null; then
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
		bsd*)
			if [ -x '/usr/local/bin/ggrep' ]; then
				alias grep='ggrep --color=auto'
				alias fgrep='gfgrep --color=auto'
				alias egrep='gegrep --color=auto'
			fi

			if [ -x '/usr/local/bin/gls' ]; then
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
# }}} Functions & Aliases

# {{{ Setup gpg-agent(1)

if [ -x "$(command -v gpg-agent)" ]; then
	gpgconf --launch gpg-agent

	GPG_TTY=$(tty); export GPG_TTY
fi

# }}} Setup gpg-agent(1)

# {{{ Setup ssh-agent(1)
if [ -x "$(command -v ssh-agent)" ]; then
	function __ssh_agent_status() {
		#shellcheck disable=SC2009
		ps -Ao uid,pid,comm | grep -Eq "^[[:blank:]]*${UID}[[:blank:]]+${SSH_AGENT_PID}[[:blank:]]+ssh-agent$"
		return $?
	}

	if [ ! -S "${SSH_AUTH_SOCK}" ] || ! __ssh_agent_status; then
		#shellcheck source=.ssh-agent-info
		[ -f ~/.ssh-agent-info ] && source ~/.ssh-agent-info
		if [ ! -S "${SSH_AUTH_SOCK}" ] || ! __ssh_agent_status; then
			echo 'Could not find a running ssh-agent.  Starting one now.'
			eval "$(ssh-agent | head -n 2 | tee ~/.ssh-agent-info)"
		fi
	fi
fi

# }}} Setup ssh-agent(1)

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

# {{{ Perlbrew
#shellcheck disable=1090
[[ -d ~/.local/share/perlbrew ]] && source ~/.local/share/perlbrew/etc/bashrc

# }}}

# {{{ RVM

# Load RVM into a shell session *as a function*
#shellcheck disable=1090
[[ -s ~/.rvm/scripts/rvm ]] && source ~/.rvm/scripts/rvm

# }}} RVM

# {{{ $PATH Setup

__ensure_path_contains() {
	local _dir

	[[ "$#" -ge 1 ]] || return

	for _dir in "$@"; do
		[[ -d "$_dir" ]] || continue
		if ! [[ $PATH =~ /^(${_dir}:)|:${_dir}:|(:${_dir})$|^(${_dir})$/ ]]; then
			PATH="${1}:${PATH}"
		fi
	done
}

# Add the private /bin directory to $PATH
__ensure_path_contains ~/bin ~/.rvm/bin ~/.pyenv/bin ~/.cabal/bin

# Add pyenv to $PATH
if [ -d ~/.pyenv/bin ]; then
	__ensure_path_contains ~/.pyenv/bin
fi

if command -v pyenv >&/dev/null; then
	__ensure_path_contains ~/.pyenv/shims ~/.pyenv/plugins/pyenv-virtualenv/shims
fi

export PATH

# Print $PATH for manual verification
if [[ "$TERMINAL_COLORS" -ge '8' ]]; then
	echo "PATH=$(sed "s/\\([^:]\\+\\)\\(:\\)\\?/${BASE16[BASE03]}\\1${BASE16[BASE0C]}\\2/g" <<<"$PATH")"
else
	echo "PATH=\"${PATH}\""
fi

# }}} $PATH Setup

# {{{ NVM

[[ -d ~/.nvm ]] && export NVM_DIR="$HOME/.nvm"
#shellcheck disable=1090
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
#shellcheck disable=1090
[[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"

# }}}

# {{{ pyenv
if command -v pyenv >&/dev/null; then
	eval "$(pyenv init - | grep -v 'PATH')" && eval "$(pyenv virtualenv-init - | grep -v 'PATH')"
fi
# }}}

# {{{ Cleanup
unset -f __ssh_agent_status
# }}} Cleanup

# vim:foldmethod=marker
# vi:ts=4:sw=4:noexpandtab
