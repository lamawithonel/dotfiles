#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# 050-environment.sh
#
# General environment variables and regex patterns
# Category: 000-099 Core shell configuration
# Note: Uses Bash syntax but is compatible with Zsh

# Define a few finite-length POSIX.1 EREs for use in scripts
#
# IPv4 addresses
IPv4_ADDRESS='(([01][[:digit:]]{2}|2[0-4][[:digit:]]|25[0-5]|[[:digit:]]{1,2})\.){3}([01][[:digit:]]{2}|2[0-4][[:digit:]]|25[0-5]|[[:digit:]]{1,2})'
# IPv4 CIDR subnet notation
IPv4_SUBNET="${IPv4_ADDRESS}(\\/[[:digit:]]{1,2})?"
# hostnames
HOSTNAME_REGEX='[[:digit:]a-zA-Z-][[:digit:]a-zA-Z\.-]{1,63}\.[a-zA-Z]{2,6}\.?'

export IPv4_ADDRESS IPv4_SUBNET HOSTNAME_REGEX
