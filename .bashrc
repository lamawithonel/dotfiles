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

if [[ "$-" =~ i ]] && [[ ! ${BASH_SOURCE[*]} =~ ([[:blank:]]|/)\.bash_profile([[:blank:]]|$) ]]; then
	# shellcheck source=./.bash_profile
	[ -f "${HOME}/.bash_profile" ] && source "${HOME}/.bash_profile"
fi

# Everything after this point is intended for interactive shells only.
# Exit if the shell is not interactive.
[[ "$-" =~ i ]] || return

# {{{ Shared Functions

# _ensure_path_contains() -- An improved version of Red Hat's pathmunge()
#
# Adds a fully-qualified directory to the PATH variable.
#
# By default the directory is added at the begining of the PATH variable,
# e.g., "${1}:/bin".  However, if the second argument is set to "after" it
# will append it to the end of PATH, e.g., "/bin:${1}".  If the directory
# path does not exist or is not a directory, it will remove the element.
#
# $1 = /fully/qualified/PATH/element
# $2 = "before" | "after" | "" (optional)
#
_ensure_path_contains() {
	local _dir="$1"
	local _position="${2:-before}"

	# Must be a fully-qualifed path
	[[ "$_dir" =~ ^/[[:print:]]+$ ]] || return 1

	if [ -d "$_dir" ]; then
		if ! [[ "$PATH" =~ (^|:)${_dir}(:|$) ]]; then
			if [ "$_position" = 'after' ]; then
				PATH="${PATH}:${_dir}"
			else
				PATH="${_dir}:${PATH}"
			fi
		fi
	else
		PATH="$(echo "$PATH" | sed "s:\(^|\:\)${_dir}::g")"
	fi

	export PATH
}

export _ensure_path_contains
# }}}

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
HISTFILE="${BASH_CACHE_HOME}/history"

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

[ -d "${BASH_DATA_HOME}/ext" ] || mkdir "${BASH_DATA_HOME}/ext"

if [ ! -d "${BASH_DATA_HOME}/ext/bash-preexec" ]; then
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

# {{{ $PATH Setup

# Most of this could happen elsewhere in this script, but doing it all here
# gives a clean look at what order they'll appear in the final $PATH variable.
# Items added earlier will appear later in the variable (lower precedence).

if [[ "$OSTYPE" =~ 'darwin' ]] && [ -x "$_iterm2_check" ] && "$_iterm2_check"; then
	_ensure_path_contains "${_iterm2_integration_dir}/utilities"
fi

_ensure_path_contains "${XDG_DATA_HOME}/tfenv/bin"
_ensure_path_contains "${XDG_DATA_HOME}/perlbrew/bin"
_ensure_path_contains "${XDG_DATA_HOME}/cabal/bin"
_ensure_path_contains "${XDG_DATA_HOME}/deno/bin"
_ensure_path_contains "${XDG_DATA_HOME}/dotnet/tools" # NOTE: See https://github.com/dotnet/sdk/issues/10390
_ensure_path_contains "${XDG_DATA_HOME}/rvm/bin"
_ensure_path_contains "${XDG_DATA_HOME}/cargo/bin"
_ensure_path_contains "${XDG_DATA_HOME}/pyenv/bin"

if command -v pyenv &> /dev/null; then
	_ensure_path_contains "${XDG_DATA_HOME}/pyenv/shims"
	_ensure_path_contains "${XDG_DATA_HOME}/pyenv/plugins/pyenv-virtualenv/shims"
fi

# Add private /bin directories to $PATH
_ensure_path_contains "${HOME}/bin"

export PATH

# }}} $PATH Setup

# {{{ Color

if command -v tinty &> /dev/null; then
	TINTED_SHELL_ENABLE_BASE16_VARS=1
	TINTED_SHELL_ENABLE_BASE24_VARS=1
	BASE16_SHELL_PATH="${XDG_DATA_HOME}/tinted-theming/tinty/repos/tinted-shell"

	export \
		BASE16_SHELL_PATH \
		TINTED_SHELL_ENABLE_BASE16_VARS \
		TINTED_SHELL_ENABLE_BASE24_VARS

	eval "$(tinty generate-completion bash)"
fi

if [ -s "${BASE16_SHELL_PATH}/profile_helper.sh" ]; then
	# shellcheck source=./.local/share/tinted-theming/tinty/repos/tinted-shell/profile_helper.sh
	source "${BASE16_SHELL_PATH}/profile_helper.sh"
fi

# Use tput(1) to determine the number of supported colors.
TERMINAL_COLORS="$(tput colors 2> /dev/null || echo -1)"

# If the terminal supports at least 8 colors, source the color theme and
# setup dircolors(1)
if [ "$TERMINAL_COLORS" -ge '8' ]; then
	# shellcheck source=./.config/bash/colors.bash
	[ -f "${BASH_CONFIG_HOME}/colors.bash" ] && source "${BASH_CONFIG_HOME}/colors.bash"

	# dircolors(1)
	case "$OSTYPE" in
		*-gnu)
			if command -v dircolors &> /dev/null; then
				eval "$(dircolors <(dircolors -p | sed 's/ 01;/ /g'))"
			fi
			;;
		bsd* | darwin*)
			if command -v gdircolors &> /dev/null; then
				eval "$(gdircolors <(dircolors -p | sed 's/ 01;/ /g'))"
			fi
			;;
	esac
else
	if [ -f "${XDG_CONFIG_HOME}/bash/colors_null.bash" ]; then
		# shellcheck source=./.config/bash/colors_null.bash
		source "${XDG_CONFIG_HOME}/bash/colors_null.bash"
	fi
fi
# }}} Color Support

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

# {{{ Prompt Setup

# Setup bash-preexec and bash-postexec hooks.
# These must be configured before the prompt.
if [ -f "${BASH_DATA_HOME}/ext/bash-preexec/bash-preexec.sh" ]; then
	#shellcheck source=./.local/share/bash/ext/bash-preexec/bash-preexec.sh
	source "${BASH_DATA_HOME}/ext/bash-preexec/bash-preexec.sh"

	preexec_functions=(
		update_gpg_agent_startup_tty
	)
fi

# Use Starship.rs to configure the prompt if it's available, otherwise use a
# simple two-line prompt with base16 colors.
# FIXME: Ugly hack to disable sudo or fallback to the simple prompt
if command -v starship &> /dev/null && [ "$STARSHIP_SUDO_DISABLE" = 'true' ] && toml set --help &> /dev/null; then
	# Copy `starship.toml` to our shadow location with local edits.
	toml "${XDG_CONFIG_HOME}/starship.toml" set sudo.disabled true > "${XDG_DATA_HOME}/starship/config_shadow.toml"
	export STARSHIP_CONFIG="${XDG_DATA_HOME}/starship/config_shadow.toml"
	eval "$(starship init bash)"
	eval "$(starship completions bash)"
elif command -v starship &> /dev/null && [ ! "$STARSHIP_SUDO_DISABLE" = 'true' ]; then
	eval "$(starship init bash)"
	eval "$(starship completions bash)"
else
	if [ "$STARSHIP_SUDO_DISABLE" = 'true' ]; then
		cat <<- EOF
			WARN:   $STARSHIP_SUDO_DISABLE is set, but $(toml-cli) is not available.
			        Disabling Starship!  Install $(toml-cli) from Cargo to enable Starship.
		EOF
	fi
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
	PROMPT_COMMAND=_prompt_command
	PROMPT_DIRTRIM=4
fi

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

if [ "$TERMINAL_COLORS" -ge '8' ]; then
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
		bsd* | darwin*)
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
		*) ;;
	esac
else
	alias ls='ls -F'
	alias ll='ls -alF'
	alias la='ls -A'
	alias l='ls -CF'
fi

hadolint() {
	local _dockerfile
	local _file
	local _hadolint_yaml=''

	if [ -e "$1" ]; then
		_dockerfile="$1"
		shift

		for _file in \
			"${PWD}/.hadolint.yaml" \
			"${XDG_CONFIG_HOME}/hadolint.yaml" \
			"${HOME}/.config/hadolint.yaml" \
			"${HOME}/.hadolint/hadolint.yaml" \
			"${HOME}/hadolint/config.yaml" \
			"${HOME}/.hadolint.yaml"; do
			if [ -f "$_file" ]; then
				_hadolint_yaml="--volume=$_file:/.hadolint.yaml:ro"
				break
			fi
		done

		docker run --rm -i ghcr.io/hadolint/hadolint:latest-alpine /bin/hadolint "$@" - < "$_dockerfile"
	else
		printf 'Usage:\n\thadolint <path-to-Dockerfile> [hadolint-args...]\n'
		return 1
	fi
}

# }}} Functions & Aliases

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

# {{{ iTerm2

_iterm2_integration_dir="${XDG_DATA_HOME}/iTerm2/iTerm2-shell-integration"
_iterm2_integration_script="${_iterm2_integration_dir}/shell_integration/bash"
_iterm2_check="${_iterm2_integration_dir}/utilities/it2check"

if [[ "$OSTYPE" =~ 'darwin' ]] && [ -x "$_iterm2_check" ] && "$_iterm2_check"; then
	# shellcheck source=./.local/share/iterm2/iTerm2-shell-integration/shell_integration/bash
	[ -f "$_iterm2_integration_script" ] && source "$_iterm2_integration_script"
fi

# }}}

# {{{ Perlbrew

# shellcheck source=./.local/share/perlbrew/etc/bashrc
[ -d "${XDG_DATA_HOME}/perlbrew" ] && source "${XDG_DATA_HOME}/perlbrew/etc/bashrc"

# }}}

# {{{ SDKman

# shellcheck source=./.local/share/sdkman/bin/sdkman-init.sh
[ -s "${XDG_DATA_HOME}/bin/sdkman-init.sh" ] && source "${XDG_DATA_HOME}/bin/sdkman-init.sh"

# }}}

# {{{ Deno

command -v deno &> /dev/null && eval "$(deno completions bash)"

# }}}

# {{{ fnm Node.js Manager

if command -v fnm &> /dev/null; then
	PATH="$(echo "$PATH" | sed -E 's,(^|:)/[^:]+/fnm_multishells/[0-9_]+/bin(:|$),,g')"
	eval "$(fnm env --use-on-cd --shell bash)"
	eval "$(fnm completions --shell bash)"
fi

# }}}

# {{{ pyenv

if command -v pyenv &> /dev/null; then
	if eval "$(pyenv init - --no-push-path bash)"; then
		eval "$(pyenv virtualenv-init - bash | grep -vF 'export PATH')"
	fi
fi

# }}}

# {{{ pipenv

if pipenv --version &> /dev/null; then
	eval "$(pipenv --completion 2> /dev/null || _PIPENV_COMPLETE=bash_source pipenv)"
fi

# }}}

# {{{ Rust

if command -v rustup &> /dev/null; then
	eval "$(rustup completions bash rustup)"
	eval "$(rustup completions bash cargo)"
fi

command -v probe-rs &> /dev/null && eval "$(probe-rs complete install -m)"

# }}}

# {{{ RVM

# Load RVM into a shell session *as a function*
# shellcheck source=./.local/share/rvm/scripts/rvm
[ -s "${XDG_DATA_HOME}/rvm/scripts/rvm" ] && source "${XDG_DATA_HOME}/rvm/scripts/rvm"

# If this is set Starship will always show the Ruby version
unset RUBY_VERSION

# }}} RVM

# {{{ $PATH print

# Print $PATH for manual verification
if [ "$TERMINAL_COLORS" -ge '8' ]; then
	# shellcheck disable=SC2001
	echo "${BASE16[BASE08]}PATH${BASE16[BASE05]}=$(sed "s/\\([^:]\\+\\)\\(:\\)\\?/${BASE16[BASE06]}\\1${BASE16[BASE0C]}\\2/g" <<< "$PATH")"
else
	echo "PATH=\"${PATH}\"${ANSI[RESET]}"
fi

# }}} $PATH print

# {{{ Cleanup

unset -v _iterm2_check _iterm2_integration_script _iterm2_integration_dir
unset -f _ensure_path_contains

# }}}

# {{{ ~/.bashrc.d/*

if [ -d "${HOME}/.bashrc.d" ]; then
	for _file in "${HOME}/.bashrc.d/"*".sh"; do
		# shellcheck disable=1090
		[ -r "$_file" ] && . "$_file"
	done
	unset _file
fi

# }}}

# Restore shell options in case we set `errexit` or `nounset` for debugging
eval "${_shopts:-}"
unset _shopts

# {{{ Local Additions

if [ -d "${HOME}/.bashrc.local.d" ]; then
	for _file in "${HOME}/.bashrc.local.d/"*".sh"; do
		#shellcheck disable=1090
		[ -r "$_file" ] && . "$_file"
	done
fi

#shellcheck source=./.bashrc.local
[ -e "${HOME}/.bashrc.local" ] && . "${HOME}/.bashrc.local"

# }}}
