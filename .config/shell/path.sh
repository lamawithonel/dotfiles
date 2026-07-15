#!/bin/sh
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# .config/shell/path.sh
#
# POSIX-compatible PATH management functions
# Can be sourced by both Bash and Zsh (and any POSIX shell)
#
# This is the one canonical implementation of _ensure_path_contains().
# Do not duplicate it elsewhere (e.g., in rc.d stage files).

# _ensure_path_contains() -- An improved version of Red Hat's pathmunge()
#
# Adds a fully-qualified directory to the PATH variable.
#
# By default the directory is added at the beginning of the PATH variable,
# e.g., "${1}:/bin".  However, if the second argument is set to "after" it
# will append it to the end of PATH, e.g., "/bin:${1}".  If the directory
# path does not exist or is not a directory, it will remove the element.
#
# Any existing occurrence(s) of the element are removed first, so the
# result never contains duplicates and never has leading/trailing empty
# PATH elements, regardless of the starting value of PATH.
#
# $1 = /fully/qualified/PATH/element
# $2 = "before" | "after" | "" (optional)
#
_ensure_path_contains() {
	# Must be a fully-qualified path (POSIX-compatible check); reject
	# relative paths outright.
	case "$1" in
		/*)
			# Valid absolute path
			;;
		*)
			return 1
			;;
	esac

	# Work on a colon-padded copy so every element (including the first
	# and last) can be matched/removed uniformly. One pass strips every
	# existing occurrence of the element and squeezes any doubled colons
	# (whether produced by that removal or already present in a dirty
	# starting PATH) until neither pattern remains.
	_epc_path=":${PATH}:"
	while true; do
		case "$_epc_path" in
			*"::"*)
				_epc_path="${_epc_path%%::*}:${_epc_path#*::}"
				;;
			*":${1}:"*)
				_epc_path="${_epc_path%%":${1}:"*}:${_epc_path#*":${1}:"}"
				;;
			*)
				break
				;;
		esac
	done

	# Strip the leading/trailing colon padding.
	_epc_path="${_epc_path#:}"
	_epc_path="${_epc_path%:}"

	if [ -d "$1" ]; then
		if [ "$2" = 'after' ]; then
			PATH="${_epc_path:+${_epc_path}:}${1}"
		else
			PATH="${1}${_epc_path:+:${_epc_path}}"
		fi
	else
		# Directory doesn't exist (or no longer exists); leave it
		# removed.
		PATH="$_epc_path"
	fi

	unset _epc_path
	export PATH
}
