#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# 310-functions.sh
#
# Utility functions for both Bash and Zsh
# Category: 300-399 Aliases and utility functions
# Note: Uses Bash syntax but is compatible with Zsh

hadolint() {
	# Both Bash and Zsh support local
	local _dockerfile _file _hadolint_yaml=''

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

		docker run --rm -i "${_hadolint_yaml}" ghcr.io/hadolint/hadolint:latest-alpine /bin/hadolint "$@" - < "$_dockerfile"
	else
		printf 'Usage:\n\thadolint <path-to-Dockerfile> [hadolint-args...]\n'
		return 1
	fi
}
