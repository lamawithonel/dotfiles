#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# Shell completion scripts for tools and other miscelany

if [ -n "$ZSH_VERSION" ]; then
    _shell="zsh"
elif [ -n "$BASH_VERSION" ]; then
    _shell="bash"
else
    return 0
fi

_load_comp() {
    command -v "$1" >/dev/null 2>&1 || return
    eval "$("$@" 2>/dev/null)" 2>/dev/null
}

_load_comp starship completions "$_shell"
_load_comp uv generate-shell-completion "$_shell"
_load_comp ruff generate-shell-completion "$_shell"
_load_comp just --completions "$_shell"
_load_comp gh completion -s "$_shell"
_load_comp hugo completion "$_shell"
_load_comp kubectl completion "$_shell"
_load_comp deno completions "$_shell"
_load_comp rg --generate "complete-${_shell}"
_load_comp fzf "--${_shell}"

# pipx strangeness
if command -v pipx >/dev/null 2>&1 && command -v register-python-argcomplete >/dev/null 2>&1; then
    if [ "$_shell" = "zsh" ]; then
        autoload -Uz bashcompinit && bashcompinit
    fi
    eval "$(register-python-argcomplete pipx 2>/dev/null)" 2>/dev/null
fi

# npm (only compatible with bash)
if [ "$_shell" = "bash" ] && command -v npm >/dev/null 2>&1; then
    eval "$(npm completion 2>/dev/null)" 2>/dev/null
fi

unset _shell
unset -f _load_comp
