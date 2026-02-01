#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# 440-rvm.sh
#
# Ruby version manager initialization
# Category: 400-499 Language/tool environment managers
# Note: Uses Bash syntax but is compatible with Zsh

# Load RVM into a shell session *as a function*
# RVM has Zsh support and should be sourced after compinit
# See: https://rvm.io/integration/zsh
# shellcheck source=../.local/share/rvm/scripts/rvm
if [ -s "${XDG_DATA_HOME}/rvm/scripts/rvm" ]; then
	. "${XDG_DATA_HOME}/rvm/scripts/rvm"
fi

# If this is set Starship will always show the Ruby version
unset RUBY_VERSION
