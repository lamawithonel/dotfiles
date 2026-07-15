#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# Finite-length POSIX.1 EREs for use in scripts

# IPv4 addresses
REGEX_IPv4_ADDRESS='(([01][[:digit:]]{2}|2[0-4][[:digit:]]|25[0-5]|[[:digit:]]{1,2})\.){3}([01][[:digit:]]{2}|2[0-4][[:digit:]]|25[0-5]|[[:digit:]]{1,2})'

# IPv4 CIDR subnet notation
REGEX_IPv4_SUBNET="${REGEX_IPv4_ADDRESS}(\\/[[:digit:]]{1,2})?"

# Hostnames
REGEX_HOSTNAME_LABEL='[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?'

# Fully qualified domain name (FQDN)
REGEX_FQDN="(${REGEX_HOSTNAME_LABEL}\\.)*${REGEX_HOSTNAME_LABEL}"

export REGEX_IPv4_ADDRESS REGEX_IPv4_SUBNET REGEX_HOSTNAME_LABEL REGEX_FQDN
