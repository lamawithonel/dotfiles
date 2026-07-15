# vi:ts=4:sw=4:noet
#
# bin/lib/real-dir-safety.sh
#
# Shared by bin/check-shell-config and bin/bench-shell-startup. Both
# scripts wire a handful of *real* (not fixture) directories --
# MISE_DATA_DIR, MISE_CONFIG_DIR, MISE_STATE_DIR, the cargo bin dir --
# into their isolated fixture environments so mise can resolve
# fnox/pitchfork/starship (see the module comment at the top of
# bin/check-shell-config for the full rationale). Neither script may
# trust a real directory for this just because it happens to exist:
# an attacker-writable one must never be wired in. This file is
# sourced (not executed) by both; it defines exactly one function and
# has no side effects of its own.

# _real_dir_is_safe <dir>
# Mirrors 70-completions.sh's zstat-based safety check on
# $ZSH_CACHE_HOME: the directory must exist, be owned by the current
# EUID, and must not be group- or world-writable.
_real_dir_is_safe() {
	_rdis_dir="$1" _rdis_owner="" _rdis_mode=""
	[ -d "$_rdis_dir" ] || return 1
	case "$(uname -s)" in
		Darwin | *BSD)
			_rdis_owner="$(stat -f '%u' "$_rdis_dir" 2> /dev/null)"
			_rdis_mode="$(stat -f '%OLp' "$_rdis_dir" 2> /dev/null)"
			;;
		*)
			_rdis_owner="$(stat -c '%u' "$_rdis_dir" 2> /dev/null)"
			_rdis_mode="$(stat -c '%a' "$_rdis_dir" 2> /dev/null)"
			;;
	esac
	[ -n "$_rdis_owner" ] && [ -n "$_rdis_mode" ] || return 1
	[ "$_rdis_owner" = "$(id -u)" ] || return 1
	(( (8#$_rdis_mode & 8#0022) == 0 ))
}
