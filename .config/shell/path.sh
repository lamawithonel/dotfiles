#!/bin/sh
# vi:ts=4:sw=4:noexpandtab
# vim:foldmethod=marker
#
#----------------------------------------------------------------------
# .config/shell/path.sh
#
# POSIX-compatible PATH management functions
# Can be sourced by both Bash and Zsh (and any POSIX shell)

# _ensure_path_contains() -- An improved version of Red Hat's pathmunge()
#
# Adds a fully-qualified directory to the PATH variable.
#
# By default the directory is added at the beginning of the PATH variable,
# e.g., "${1}:/bin".  However, if the second argument is set to "after" it
# will append it to the end of PATH, e.g., "/bin:${1}".  If the directory
# path does not exist or is not a directory, it will remove the element.
#
# $1 = /fully/qualified/PATH/element
# $2 = "before" | "after" | "" (optional)
#
_ensure_path_contains() {
	# Must be a fully-qualified path (POSIX-compatible regex check)
	case "$1" in
		/*)
			# Valid absolute path
			;;
		*)
			# Not an absolute path, return error
			return 1
			;;
	esac

	if [ -d "$1" ]; then
		# Check if path is already in PATH (POSIX-compatible)
		case ":${PATH}:" in
			*:"$1":*)
				# Already in PATH, do nothing
				;;
			*)
				# Not in PATH, add it
				if [ "$2" = 'after' ]; then
					PATH="${PATH}:${1}"
				else
					PATH="${1}:${PATH}"
				fi
				;;
		esac
	else
		# Directory doesn't exist, remove it from PATH if present
		case ":${PATH}:" in
			*:"$1":*)
				# Present in PATH, remove it
				PATH=":${PATH}:"
				# Replace :$1: with :
				PATH="${PATH%":${1}:"*}:${PATH#*":${1}:"}"
				# Remove leading and trailing colons
				PATH="${PATH#:}"
				PATH="${PATH%:}"
				;;
		esac
	fi

	export PATH
}
