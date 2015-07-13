# ~/.bashrc
#
# This file is sourced by bash(1) for interactive shells which are not
# login shells, not called with the -l or -p options, and not called as
# 'sh', as in the symbolic link at /bin/sh.  It's also common to source
# this file from ~/.bash_profile, ~/.bash_login or ~/.profile.
#

##
# Sanity checks
#
# {{{ (sanity checks)
# Before doing anything, check that the shell is both bash(1) and
# running interactively.  Return if it is not.
case "${-}" in *i*) INTERACTIVE=1;; esac
[ -z "$BASH_VERSION" ] && return
[ -z "$INTERACTIVE"  ] && return
# }}} Sanity Check

##
# Configuration variables for this file
#
# {{{ (config)
# Note: booleans in this section must be either 'Y' or 'N'

# Should the $PATH variable be printed for varification? (boolean)
print_path=Y			

# Toggles colorization of ls(1) and grep(1) (boolean)
colorful_commands=Y

# Toggles colorization of the prompt (boolean)
colorful_prompt=Y

# Adds a lot of extra status info in the prompt, implies color
# (boolean)
fancy_prompt=Y

# The basename of a color theme file in ~/.bash_colors.d/,
# defaults to 'default'
color_theme=solarized

# The basename of a dircolors(1) database file in ~/.dircolors.d/,
# defaults to 'default' or 'default.256' depending on terminal support.
dircolors_theme=solarized.ansi-dark

# }}} (config)

##
# Shell options (built-in)
#
# {{{ (shell options)

# Trim the working directory string in $PS1 to this many elements
PROMPT_DIRTRIM=4

# Don't put duplicate lines or lines starting with space in the history.
HISTCONTROL=ignoreboth

# Number of commands to keep in the scrollback history
HISTSIZE=1000

# Maximum size of ~/.bash_history, in bytes
HISTFILESIZE=2000

# Append to the history file, don't overwrite it
shopt -s histappend

# Check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# }}}

##
# Script statements
#
# {{{ (statements)

# {{{ Bash Completion
#
# Enable programmable completion features for non-root users.
# Priveledged users should never enable this, because it opens up the
# shell to command injection attacks.

if ! shopt -oq posix && [ ${EUID} -ne 0 ]; then
	if [ -f /etc/bash_completion ]; then
		. /etc/bash_completion
	elif [ -f /etc/profile.d/bash-completion.sh ]; then
		. /etc/profile.d/bash-completion.sh
	fi
fi
# }}} Bash Completion

# {{{ Color Support
#
# This portion determins if the terminal supports color then, based on
# the configuration varibles set near the top, it will set a few state
# variables.

if [ "$colorful_prompt" = 'Y' -o "$colorful_commands" = 'Y' ] || [ "$fancy_prompt" = 'Y' ]; then
	# Use tput(1) to determin how many colors the terminal supports.
	# Capture the value for later use.
	tput_colors=$(tput colors 2>/dev/null) || tput_colors=1
	export tput_colors colorful_prompt colorful_commands fancy_prompt

	# If the terminal supports at least 16 colors, source the color theme
	# and setup dircolors(1)
	if [ $tput_colors -ge 8 ]; then

		# __tput_COLOR function theming
		if [ -f ~/.bash_colors.d/${color_theme} ]; then
			. ~/.bash_colors.d/${color_theme}
		else
			. ~/.bash_colors.d/default
		fi

		# dircolors(1)
		if [ -f ~/.dircolors.d/${dircolors_theme} ]; then
			if [ -x /usr/local/bin/gdircolors ]; then
				eval $(gdircolors ~/.dircolors.d/${dircolors_theme})
			else
				eval $(dircolors ~/.dircolors.d/${dircolors_theme})
			fi
		elif [ $tput_colors -ge 256 ] && [ -f ~/.dircolors.d/default.256color ]; then
			if [ -x /usr/local/bin/gdircolors ]; then
				eval $(gdircolors ~/.dircolors.d/default.256color)
			else
				eval $(dircolors ~/.dircolors.d/default.256color)
			fi
		elif [ -f ~/.dircolors.d/default ]; then
			if [ -x /usr/local/bin/gdircolors ]; then
				eval $(gdircolors ~/.dircolors.d/default)
			else
				eval $(dircolors ~/.dircolors.d/default)
			fi
		fi
	else
		function __tput_GREEN  { return; }
		function __tput_RESET  { return; }
		function __tput_YELLOW { return; }
		function __tput_RESET  { return; }
		function __tput_RED    { return; }
		function __tput_RESET  { return; }
	fi
else
	tput_colors=1
fi
# }}} Color Support

# {{{ Prompt Setup


# For normal usage, the end-result will look like this:
#
#    [1] user@host:~ $
#
# If you're in a Git repo, it would look like this:
#
#    [1] user@host:~ [master] $
#
# And if you've access the machine via SSH, it would look like this:
#
#    [1] (192.168.1.1)user@host:~ [master] $
#

# {{{ Debian chroot(2)
#
# Setup a variable identifying the Debian chroot(2).  This shouldn't
# change except at shell invocation, so do it outside the
# __prompt_command() to save cycles.

if [ -z "$debian_chroot" ] && [ -r /etc/debian_chroot ]; then
	debian_chroot=$(cat /etc/debian_chroot)
fi
# }}} Debian chroot(2)

if [ "$fancy_prompt" = 'Y' ]; then

	##
	# __prompt_command()
	#
	# This function is executed each time the shell returns, dynamically
	# generating the prompt.  It takes no arguments, however it reads a
	# few environment variables.
	#
	function __prompt_command() {

		# {{{ Last command status capture
		# Before anything else, capture the exit status of the last
		# command.
		EXIT="$?"
		# }}}

		# {{{ Command number & status
		#
		# This portion prints the bash command sequence number, coloring
		# the output based on the exit status of the last command.
		if [ $EXIT -eq 0 ]; then
			PS1="\[$(__tput_GREEN)\][\!]\[$(__tput_RESET)\] "
		else
			PS1="\[$(__tput_RED)\][\!]\[$(__tput_RESET)\] "
		fi
		# }}} Command number & status

		# {{{ SSH client IP
		#
		# If connected via SSH, this will print the IP address of the client
		# machine.
		if [ -n "$SSH_CLIENT" ]; then
			PS1+="\[$(__tput_YELLOW)\]("${SSH_CLIENT%% *}")\[$(__tput_RESET)\]"
		fi
		# }}} SSH client IP
 
		# {{{ Debian chroot(2)
		PS1+="${debian_chroot:+($debian_chroot)}"
		# }}}

		# {{{ Basic Information
		#
		# This staple of the prompt is a common default in many
		# operating systems, most notably Debian and Ubuntu.  It is based
		# on the OpenSSH syntax for sftp(1) and scp(1), providing a
		# solid peice of text for copy-paste operations.
		#
		if [ $tput_colors -ge 16 ] || [ $tput_colors -ge 8 ] && [ $(tput bold 2>/dev/null) ]; then
			if [ $EUID -eq 0 ]; then
				PS1+="\[$(__tput_BRRED)\]\h\[$(__tput_BLUE)\]:\[$(__tput_BASE05)\]\w\[$(__tput_RESET)\] "
			else
				PS1+="\[$(__tput_BRGREEN)\]\u@\h\[$(__tput_BLUE)\]:\[$(__tput_BASE05)\]\w\[$(__tput_RESET)\] "
			fi
		else
			if [ $EUID -eq 0 ]; then
				PS1+="\[$(__tput_RED)\]\h\[$(__tput_RESET)\]:\w "
			else
				PS1+="\[$(__tput_GREEN)\]\u@\h\[$(__tput_RESET)\]:\w "
			fi
		fi
		# }}} Basic Information

		# {{{ Git status
		#
		# If the current working directory is part of a git(1) repository
		# this portion will print the working branch name, colored based on
		# the commit status.
		#
		if which git >/dev/null 2>&1; then
			local git_status="$(git status -unormal 2>&1)"
			if ! [[ "$git_status" =~ Not\ a\ git\ repo ]]; then
				# parse the porcelain output of git status
				if [[ "$git_status" =~ nothing\ to\ commit ]]; then
					local git_color=$(__tput_GREEN)
				elif [[ "$git_status" =~ nothing\ added\ to\ commit\ but\ untracked\ files\ present ]]; then
					local git_color=$(__tput_VIOLET)
				else
					local git_color=$(__tput_RED)
				fi

				if [[ "$git_status" =~ On\ branch\ ([^[:space:]]+) ]]; then
					branch=${BASH_REMATCH[1]}
				else
					# Detached HEAD. (branch=HEAD is a faster alternative.)
					branch="($(git describe --all --contains --abbrev=4 HEAD 2> /dev/null || echo HEAD))"
				fi

				# add the result to prompt
				PS1+="\[${git_color}\][${branch}]\[$(__tput_RESET)\] "
			fi
		fi
		# }}} Git status

		# {{{ Prompt character
		# (# for root, $ for everybody else)
		PS1+='\$ '
		# }}}
	}

	PROMPT_COMMAND=__prompt_command

elif [ $tput_colors -ge 8 ] && [ "$colorful_promt" = 'Y' ]; then

	if [ $EUID -eq 0 ]; then
		PS1="${debian_chroot:+($debian_chroot)}\[$(__tput_BRRED)\]\h\[$(__tput_BLUE)\]:\[$(__tput_BASE05)\]\w\[$(__tput_RESET)\] "
	else
		PS1="${debian_chroot:+($debian_chroot)}\[$(__tput_BRGREEN)\]\u@\h\[$(__tput_BLUE)\]:\[$(__tput_BASE05)\]\w\[$(__tput_RESET)\] "
	fi

else
	PS1="${debian_chroot:+($debian_chroot)}\u@\h:\w \$ "; export PS1

fi
# }}} Prompt Setup

# {{{ Functions & Aliases

# Make common file operations interactive for safety
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

if [ "$colorful_commands" = 'Y' -a $tput_colors -ge 4 ]; then
	# Enable color support in grep(1)
	if [ -x '/usr/local/bin/ggrep' ]; then
		alias grep='ggrep --color=auto'
		alias fgrep='gfgrep --color=auto'
		alias egrep='gegrep --color=auto'

	else
		alias grep='grep --color=auto'
		alias fgrep='fgrep --color=auto'
		alias egrep='egrep --color=auto'
	fi

	# Enable color support in ls(1) and add a few handy aliases
	if [ -x '/usr/local/bin/gls' ]; then
		alias ls='gls -F --color=auto'
		alias ll='gls -lF --color=auto'
		alias la='gls -alF --color=auto'
		alias l='gls -CF --color=auto'
	else
		alias ls='ls -F --color=auto'
		alias ll='ls -lF --color=auto'
		alias la='ls -alF --color=auto'
		alias l='ls -CF --color=auto'
	fi
else
	alias ls='ls -F'
	alias ll='ls -alF'
	alias la='ls -A'
	alias l='ls -CF'
fi
# }}} Functions & Aliases

# {{{ Misc. Environment Variables

# gpg-agent(1)
GPG_TTY=$(tty)

# Define a few finite-length POSIX.1 EREs
#
# IPv4 addresses
IPv4_ADDRESS='(([01][[:digit:]]{2}|2[0-4][[:digit:]]|25[0-5]|[[:digit:]]{1,2})\.){3}([01][[:digit:]]{2}|2[0-4][[:digit:]]|25[0-5]|[[:digit:]]{1,2})'
# IPv4 CIDR subnet notation
IPv4_SUBNET="${IPv4_ADDRESS}(\/[[:digit:]]{1,2})?"
# hostnames
HOSTNAME_REGEX='[[:digit:]a-zA-Z-][[:digit:]a-zA-Z\.-]{1,63}\.[a-zA-Z]{2,6}\.?'

export GPG_TTY IPv4_ADDRESS IPv4_SUBNET HOSTNAME_REGEX
# }}} Misc. Environment Variables

# {{{ Local Additions
# Source an un-tracked file for private and per-machine commands
if [ -f ~/.bash.local ]; then
	. ~/.bash.local
fi
# }}} Local Additions

# {{{ $PATH Print
#
# This last step prints  the all-important $PATH variable for manual
# verification.

if [ "$print_path" = 'Y' ] && [ $tput_colors -ge 8 ]; then
	printf "$(__tput_CYAN)PATH$(__tput_RESET)=$(__tput_YELLOW)\"$(__tput_VIOLET)${PATH}$(__tput_YELLOW)\"$(__tput_RESET)\n"
elif [ "$print_path" = 'Y' ]; then
	echo "PATH=\"${PATH}\""
fi
# }}} $PATH Print

# {{{ Cleanup
unset INTERACTIVE colorful_commands colorful_prompt fancy_prompt
# }}} Cleanup

# }}} (statements)

# vim:foldmethod=marker
# vi:ts=4:sw=4:noexpandtab:tw=72:ft=sh
