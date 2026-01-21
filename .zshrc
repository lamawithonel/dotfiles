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

# {{{ History Settings

# Store history in the XDG-standard location
HISTFILE="${ZSH_CACHE_HOME}/history"

# Number of commands to keep in the scrollback history
HISTSIZE=1000

# Maximum size of $HISTFILE
SAVEHIST=2000

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

# {{{ Completion System

# Add RVM completion directory to fpath if RVM is installed
# This must be done before compinit
if [ -d "${XDG_DATA_HOME}/rvm/scripts/zsh/Completion" ]; then
	fpath=("${XDG_DATA_HOME}/rvm/scripts/zsh/Completion" $fpath)
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

# {{{ PATH Setup with Zsh's automatic deduplication

# Source the shared PATH management function
# shellcheck source=./.config/shell/path.sh
[ -f "${XDG_CONFIG_HOME}/shell/path.sh" ] && source "${XDG_CONFIG_HOME}/shell/path.sh"

# Zsh has built-in PATH deduplication
typeset -U PATH path

# Most of this could happen elsewhere in this script, but doing it all here
# gives a clean look at what order they'll appear in the final $PATH variable.
# Items added earlier will appear later in the variable (lower precedence).

if [[ "$OSTYPE" =~ 'darwin' ]]; then
	if [ -f /opt/homebrew/etc/paths ]; then
		while IFS= read -r _line; do
			_ensure_path_contains "${_line}"
		done < /opt/homebrew/etc/paths
	fi

	# iTerm2 integration (if available)
	_iterm2_integration_dir="${XDG_DATA_HOME}/iTerm2/iTerm2-shell-integration"
	_iterm2_check="${_iterm2_integration_dir}/utilities/it2check"
	if [ -x "$_iterm2_check" ] && "$_iterm2_check"; then
		_ensure_path_contains "${_iterm2_integration_dir}/utilities"
	fi
fi

_ensure_path_contains "${XDG_DATA_HOME}/tfenv/bin"
_ensure_path_contains "${XDG_DATA_HOME}/cabal/bin"
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

	eval "$(tinty generate-completion zsh)"
fi

if [ -s "${BASE16_SHELL_PATH}/profile_helper.sh" ]; then
	source "${BASE16_SHELL_PATH}/profile_helper.sh"
fi

# Use tput(1) to determine the number of supported colors.
TERMINAL_COLORS="$(tput colors 2> /dev/null || echo -1)"

# If the terminal supports at least 8 colors, source the color theme and
# setup dircolors(1)
if [ "$TERMINAL_COLORS" -ge '8' ]; then
	# shellcheck source=./.config/shell/colors.sh
	[ -f "${XDG_CONFIG_HOME}/shell/colors.sh" ] && source "${XDG_CONFIG_HOME}/shell/colors.sh"

	# dircolors(1)
	case "$OSTYPE" in
		*-gnu)
			if command -v dircolors &> /dev/null; then
				eval "$(dircolors <(dircolors -p | sed 's/ 01;/ /g'))"
			fi
			;;
		bsd* | darwin*)
			if command -v gdircolors &> /dev/null; then
				eval "$(gdircolors <(gdircolors -p | sed 's/ 01;/ /g'))"
			fi
			;;
	esac
else
	if [ -f "${XDG_CONFIG_HOME}/shell/colors_null.sh" ]; then
		# shellcheck source=./.config/shell/colors_null.sh
		source "${XDG_CONFIG_HOME}/shell/colors_null.sh"
	fi
fi
# }}} Color Support

# {{{ Prompt Setup

# Use Starship.rs to configure the prompt if it's available, otherwise use a
# simple two-line prompt with base16 colors.
# FIXME: Ugly hack to disable sudo or fallback to the simple prompt
if command -v starship &> /dev/null && [ "$STARSHIP_SUDO_DISABLE" = 'true' ] && command -v toml &> /dev/null; then
	mkdir -p "${XDG_DATA_HOME}/starship"

	# Copy `starship.toml` to our shadow location with local edits.
	toml set "${XDG_CONFIG_HOME}/starship.toml" sudo.disabled true > "${XDG_DATA_HOME}/starship/config_shadow.toml"
	export STARSHIP_CONFIG="${XDG_DATA_HOME}/starship/config_shadow.toml"

	eval "$(starship init zsh)"
	eval "$(starship completions zsh)"

elif command -v starship &> /dev/null && [ ! "$STARSHIP_SUDO_DISABLE" = 'true' ]; then
	eval "$(starship init zsh)"
	eval "$(starship completions zsh)"
else
	# Simple fallback prompt for Zsh
	if [ "$STARSHIP_SUDO_DISABLE" = 'true' ]; then
		cat <<- EOF
			WARN:   \$STARSHIP_SUDO_DISABLE is set, but toml-cli is not available.
			        Disabling Starship!  Install toml-cli from Cargo to enable Starship.
		EOF
	fi

	# Simple two-line prompt
	autoload -Uz vcs_info
	precmd() { vcs_info }
	zstyle ':vcs_info:git:*' formats '%F{red}[%b]%f'
	zstyle ':vcs_info:*' enable git

	setopt PROMPT_SUBST
	if [ "$TERMINAL_COLORS" -ge '8' ]; then
		if [ $EUID -eq 0 ]; then
			PROMPT='%F{green}[%*]%f %F{yellow}%m%f%F{blue}:%f%F{white}%~%f ${vcs_info_msg_0_} %# '
		else
			PROMPT='%F{green}[%*]%f %F{green}%n@%m%f%F{white}:%f%F{yellow}%~%f ${vcs_info_msg_0_} %# '
		fi
	else
		PROMPT='[%*] %n@%m:%~ ${vcs_info_msg_0_} %# '
	fi
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

# {{{ fnm Node.js Manager

if command -v fnm &> /dev/null; then
	PATH="$(echo "$PATH" | sed -E 's,(^|:)/[^:]+/fnm_multishells/[0-9_]+/bin(:|$),,g')"
	eval "$(fnm env --use-on-cd --shell zsh)"
	eval "$(fnm completions --shell zsh)"
fi

# }}}

# {{{ pyenv

if command -v pyenv &> /dev/null; then
	if eval "$(pyenv init - --no-push-path zsh)"; then
		eval "$(pyenv virtualenv-init - zsh | grep -vF 'export PATH')"
	fi
fi

# }}}

# {{{ pipenv

if pipenv --version &> /dev/null; then
	eval "$(pipenv --completion 2> /dev/null || _PIPENV_COMPLETE=zsh_source pipenv)"
fi

# }}}

# {{{ Rust

if command -v rustup &> /dev/null; then
	eval "$(rustup completions zsh rustup)"
	eval "$(rustup completions zsh cargo)"
fi

if command -v probe-rs &> /dev/null; then
	# FIXME: Why doesn't `probe-rs` shell completion work my MacBook?
	[[ ! "$OSTYPE" =~ 'darwin' ]] && eval "$(probe-rs complete install -m)"
fi

# }}}

# {{{ RVM

# Load RVM into a shell session *as a function*
# RVM has Zsh support and should be sourced after compinit
# See: https://rvm.io/integration/zsh
# shellcheck source=./.local/share/rvm/scripts/rvm
if [ -s "${XDG_DATA_HOME}/rvm/scripts/rvm" ]; then
	source "${XDG_DATA_HOME}/rvm/scripts/rvm"
fi

# If this is set Starship will always show the Ruby version
unset RUBY_VERSION

# }}} RVM

# {{{ $PATH print

# Print $PATH for manual verification
if [ "$TERMINAL_COLORS" -ge '8' ]; then
	# shellcheck disable=SC2001
	echo "${BASE16[BASE08]}PATH${BASE16[BASE05]}=$(sed "s/\\([^:]\\+\\)\\(:\\)\\?/${BASE16[BASE05]}\\1${BASE16[BASE0B]}\\2/g" <<< "$PATH")${ANSI[RESET]}"
else
	echo "PATH=\"${PATH}\"${ANSI[RESET]}"
fi

# }}} $PATH print

# {{{ ~/.zshrc.d/*

if [ -d "${HOME}/.zshrc.d" ]; then
	# Use nullglob (N) to avoid error when no files match
	for _file in "${HOME}/.zshrc.d/"*.sh(N); do
		# shellcheck disable=1090
		[ -r "$_file" ] && . "$_file"
	done
	unset _file
fi

# }}}

# {{{ Local Additions

if [ -d "${HOME}/.zshrc.local.d" ]; then
	# Use nullglob (N) to avoid error when no files match
	for _file in "${HOME}/.zshrc.local.d/"*.sh(N); do
		#shellcheck disable=1090
		[ -r "$_file" ] && . "$_file"
	done
fi

#shellcheck source=./.zshrc.local
[ -e "${HOME}/.zshrc.local" ] && . "${HOME}/.zshrc.local"

# }}}

# {{{ Cleanup

unset -v _iterm2_check _iterm2_integration_dir

# }}}
