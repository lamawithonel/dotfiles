#!/usr/bin/env bash
# shellcheck shell=bash
# vi:ts=4:sw=4:noexpandtab
#
#----------------------------------------------------------------------
# Native, cached, and lazy per-tool shell completion setup
#
# Per-tool completion generators are driven by the shared data table
# in ../completion-tools.conf (one line per tool; see the format notes
# there).  Tools whose completions ship with OS packages (kubectl,
# rg, deno, rustup; node/npm in Zsh) need no rows: the native
# bash-completion/compinit discovery below already finds them.

_completion_tools="${XDG_CONFIG_HOME:-${HOME}/.config}/shell/completion-tools.conf"

# fzf: `--bash`/`--zsh` emit whole-shell integration (key bindings,
# '**' trigger completion), not a per-command completer, so this must
# be eager, not a lazy stub.
#
# `--bash`/`--zsh` need fzf >= 0.48.0; older distro-packaged fzf
# (Ubuntu 22.04: 0.29, Debian 12: 0.38) emits nothing and fails
# silently. Fall back to the common distro-packaged key-binding/
# completion file locations in that case.
_ct_fzf_init() {
	command -v fzf > /dev/null 2>&1 || return 0
	_fzf_shell_init="$(fzf "--$1" 2> /dev/null)"
	if [ -n "$_fzf_shell_init" ]; then
		eval "$_fzf_shell_init"
	else
		for _fzf_legacy in \
			"/usr/share/doc/fzf/examples/key-bindings.$1" \
			"/usr/share/fzf/key-bindings.$1" \
			"/usr/share/doc/fzf/examples/completion.$1" \
			"/usr/share/fzf/completion.$1"; do
			# shellcheck disable=SC1090
			[ -r "$_fzf_legacy" ] && . "$_fzf_legacy"
		done
		unset _fzf_legacy
	fi
	unset _fzf_shell_init
}

if [ -n "$BASH_VERSION" ]; then
	# bash-completion loads providers on demand. Do not run individual tools'
	# completion generators during shell startup.
	if ! declare -F _completion_loader > /dev/null 2>&1; then
		for _bash_completion in \
			/usr/share/bash-completion/bash_completion \
			/etc/bash_completion \
			/usr/local/share/bash-completion/bash_completion \
			/usr/pkg/share/bash-completion/bash_completion \
			/opt/homebrew/etc/profile.d/bash_completion.sh \
			/usr/local/etc/profile.d/bash_completion.sh; do
			if [ -r "$_bash_completion" ]; then
				# shellcheck disable=SC1090
				. "$_bash_completion"
				break
			fi
		done
		unset _bash_completion
	fi

	# Lazy per-tool completions from the shared table. Every listed
	# tool's bash completion script self-registers its real completer
	# when eval'd, so one dispatcher covers all of them: on the first
	# completion attempt it deregisters itself, evals the tool's own
	# generator output, and returns 124 -- the documented programmable-
	# completion protocol that makes readline retry with whatever
	# completer is then registered (the same protocol bash-completion's
	# own _completion_loader uses). If the generator fails, the retry
	# simply falls back to default completion.
	#
	# `declare -A` (associative arrays) requires Bash >= 4.0. macOS
	# ships stock /bin/bash 3.2.57 (a stated compatibility baseline),
	# where `declare -A` prints "declare: -A: invalid option" and the
	# per-tool assignments below would silently collapse into index 0
	# of a plain indexed array -- the dispatcher would then eval
	# whichever tool's generator was registered last for every
	# completed command, with no visible error. Skip the whole lazy
	# table on Bash < 4; native bash-completion discovery above and the
	# aws/fzf special cases below do not touch this array and still
	# work unaffected.
	if (( BASH_VERSINFO[0] >= 4 )); then
		declare -A _lazy_completion_cmds
		_lazy_completion_dispatch() {
			local _cmd="${1##*/}"
			local _gen="${_lazy_completion_cmds[$_cmd]:-}"
			complete -r "$_cmd" 2> /dev/null
			if [ -n "$_gen" ]; then
				eval "$(eval "$_gen" 2> /dev/null)" 2> /dev/null
			fi
			return 124
		}
		if [ -r "$_completion_tools" ]; then
			while IFS='|' read -r _ct_name _ct_template _ct_shells _ct_strategy; do
				case "$_ct_name" in '' | \#*) continue ;; esac
				case " $_ct_shells " in *' bash '*) ;; *) continue ;; esac
				command -v "$_ct_name" > /dev/null 2>&1 || continue
				_lazy_completion_cmds["$_ct_name"]="${_ct_template//SHELL/bash}"
				complete -F _lazy_completion_dispatch "$_ct_name"
			done < "$_completion_tools"
			unset _ct_name _ct_template _ct_shells _ct_strategy
		fi
	fi

	# aws-cli: completion comes from the separate aws_completer binary
	# (installed alongside aws by mise's aws-cli tool with
	# symlink_bins), not from an `aws completion` subcommand.
	if command -v aws_completer > /dev/null 2>&1; then
		complete -C "$(command -v aws_completer)" aws
	fi

	# fzf: eager (see _ct_fzf_init above for rationale).
	_ct_fzf_init bash
elif [ -n "$ZSH_VERSION" ]; then
	autoload -Uz compinit

	# `-F zsh/stat b:zstat` imports only the zstat builtin under that
	# name. A plain `zmodload zsh/stat` would instead shadow the
	# external stat(1) for the rest of the interactive session (any
	# later `stat -c ...`/`stat -f ...` a user or a sourced local file
	# runs would hit zsh's incompatible builtin and error; a plain
	# `zmodload zsh/stat` breaks `stat -c %a <path>` this way.
	# fails with "bad option: -c", while the `-F b:zstat` form leaves
	# `stat -c %a /etc/passwd` working normally.
	if zmodload -F zsh/stat b:zstat 2> /dev/null; then
		_zstat_available=1
	else
		_zstat_available=0
	fi

	# Homebrew-packaged Zsh completions (kubectl, rg, deno, ...) live
	# here on Apple Silicon macOS and are otherwise invisible to
	# compinit; a no-op everywhere else.
	# shellcheck disable=SC2206
	[ -d /opt/homebrew/share/zsh/site-functions ] && fpath=(/opt/homebrew/share/zsh/site-functions $fpath)

	# .zshrc skips sourcing .zprofile (the only place that otherwise
	# creates $ZSH_CACHE_HOME) whenever __PROFILE_SOURCED is already
	# inherited as an exported variable -- a common case for a Zsh
	# spawned interactively from within an existing login shell. Ensure
	# the directory exists here too, immediately before it is tested,
	# so the safety check below never fails just because nothing ever
	# created it. Mode 0700 also makes it pass the check on its own.
	# shellcheck disable=SC2174
	[ -d "$ZSH_CACHE_HOME" ] || mkdir -m 0700 -p "$ZSH_CACHE_HOME"

	# True iff path exists, is owned by EUID, and is not group/other-
	# writable. Requires zstat (caller checks _zstat_available). Shared
	# by both checks below so this security predicate has one definition.
	_ct_path_safe() {
		local -A _st
		zstat -H _st "$1" 2> /dev/null &&
			(( _st[uid] == EUID )) &&
			(( (_st[mode] & 8#022) == 0 ))
	}

	_zcompdump="${ZSH_CACHE_HOME}/zcompdump"
	_zcompinit_cache_safe=0
	if (( _zstat_available )) && [ -d "$ZSH_CACHE_HOME" ] && _ct_path_safe "$ZSH_CACHE_HOME"; then
		_zcompinit_cache_safe=1
	fi

	# fpath-strategy rows from the shared table: their generators emit
	# classic '#compdef' autoload files whose bodies run top-level
	# completion code, so direct eval breaks -- they must be real files
	# in fpath before compinit runs instead.
	# Materialize each one into $ZSH_CACHE_HOME/_<name>, regenerating
	# only when the tool binary is newer than the cached file, and
	# invalidate the compinit dump when anything was (re)generated so
	# the new function is actually discovered. Gated on the same
	# cache-directory safety check as the dump itself.
	if (( _zcompinit_cache_safe )) && [ -r "$_completion_tools" ]; then
		while IFS='|' read -r _ct_name _ct_template _ct_shells _ct_strategy; do
			case "$_ct_name" in '' | \#*) continue ;; esac
			[ "$_ct_strategy" = "fpath" ] || continue
			case " $_ct_shells " in *' zsh '*) ;; *) continue ;; esac
			_ct_bin="$(command -v "$_ct_name" 2> /dev/null)" || continue
			_ct_bin="${_ct_bin:A}"
			_ct_cache="${ZSH_CACHE_HOME}/_${_ct_name}"
			# Trailer comment recording the resolved binary path as of
			# the last (re)generation, appended after the generated
			# function body -- a harmless comment as far as zsh's
			# autoload parsing of the '#compdef' file is concerned.
			_ct_stamp="# _ct_bin: ${_ct_bin}"
			_ct_stale=0
			if [ ! -r "$_ct_cache" ] || [ "$_ct_bin" -nt "$_ct_cache" ]; then
				_ct_stale=1
			else
				# Nix normalizes every store file's mtime to a fixed
				# epoch, so a Nix-installed tool's binary is never
				# "newer than" its cache file after the first
				# generation (Nix is a stated baseline platform) --
				# the mtime check above alone would leave the cache
				# stale forever after a tool upgrade. Cross-check the
				# resolved path recorded in the trailer stamp against
				# the tool's current resolution; a mismatch (upgrade,
				# reinstall, PATH change) forces regeneration even
				# when mtime says nothing changed. Read the file via
				# zsh's builtin `$(<file)` form (no external process)
				# and compare with a plain string comparison -- no new
				# subprocess is spawned per row.
				# shellcheck disable=SC2296
				_ct_cache_lines=("${(f)"$(<"$_ct_cache")"}")
				[ "${_ct_cache_lines[-1]}" = "$_ct_stamp" ] || _ct_stale=1
			fi
			if (( _ct_stale )); then
				if eval "${_ct_template//SHELL/zsh}" > "${_ct_cache}.new" 2> /dev/null; then
					printf '\n%s\n' "$_ct_stamp" >> "${_ct_cache}.new"
					mv -f "${_ct_cache}.new" "$_ct_cache"
					# Match the zcompdump's defensive posture: strip
					# group/other write after (re)generation. Only
					# go-w is needed (not a full 600) since completion
					# files are meant to be readable.
					chmod go-w "$_ct_cache" 2> /dev/null
					rm -f "$_zcompdump"
				else
					rm -f "${_ct_cache}.new"
				fi
			fi
		done < "$_completion_tools"
		unset _ct_name _ct_template _ct_shells _ct_strategy _ct_bin _ct_cache
		unset _ct_stamp _ct_stale _ct_cache_lines
	fi

	# Completion files generated outside startup may be placed here. Only
	# add $ZSH_CACHE_HOME to fpath once it has been judged safe above: an
	# unsafe directory must never be used for cached compinit (see below),
	# and compinit does not reliably prune an already-unsafe directory back
	# out of fpath on the -D fallback path, so it must not be added in the
	# first place. Delete $ZSH_CACHE_HOME/zcompdump to explicitly rebuild
	# after fpath changes.
	if (( _zcompinit_cache_safe )); then
		# shellcheck disable=SC2128,SC2206
		fpath=("$ZSH_CACHE_HOME" $fpath)
	fi

	if (( _zcompinit_cache_safe )) && [ -r "$_zcompdump" ]; then
		if _ct_path_safe "$_zcompdump"; then
			# Only a user-owned, non-group/world-writable dump may bypass the
			# normal checks on a cached startup.
			compinit -C -d "$_zcompdump"
		else
			# Do not read or replace an unsafe dump. -D only suppresses
			# auto-writing the dump file; compinit's normal ownership/mode
			# security checks still run (the same checks that always run
			# whenever -C is absent). Anchor the dump path explicitly so
			# it does not silently fall back to
			# ${ZDOTDIR:-$HOME}/.zcompdump.
			compinit -D -d "$_zcompdump"
		fi
	elif (( _zcompinit_cache_safe )); then
		# First build performs compinit's normal ownership and permission checks.
		compinit -d "$_zcompdump"
		[ -f "$_zcompdump" ] && chmod 600 "$_zcompdump"
	else
		# An unsafe cache directory must never be used for cached compinit,
		# and (per above) is never added to fpath either. -D suppresses
		# dump writing/caching; anchor the path explicitly (see comment
		# above) rather than relying on compinit's own default.
		compinit -D -d "$_zcompdump"
		if (( _zstat_available )); then
			# Genuinely unsafe ownership/permissions -- the directory
			# check ran and failed.
			echo "70-completions.sh: \$ZSH_CACHE_HOME is not safely owned/permissioned; skipping completion cache" >&2
		else
			# The directory may well be fine; the check itself could
			# not run because this zsh build lacks zsh/stat (e.g. a
			# minimal/static build). Say so plainly instead of
			# implying an ownership/permission problem that may not
			# exist.
			echo "70-completions.sh: zsh/stat module unavailable; skipping completion cache" >&2
		fi
	fi

	# compdef-strategy rows from the shared table: their generators emit
	# eval-safe scripts that define a real `_<name>` completion
	# function. One dispatcher stub covers all of them: the first
	# completion attempt evals the generator output,
	# re-registers the real function for the rest of the session, and
	# runs it for the in-flight attempt. $service is set by the
	# completion system to the name compdef matched.
	typeset -gA _lazy_completion_cmds
	_lazy_completion_dispatch() {
		local _gen="${_lazy_completion_cmds[$service]:-}"
		local _fn="_${service}"
		if [ -n "$_gen" ]; then
			eval "$(eval "$_gen" 2> /dev/null)" 2> /dev/null
		fi
		# shellcheck disable=SC2154,SC2004
		if (( $+functions[$_fn] )); then
			compdef "$_fn" "$service"
			"$_fn" "$@"
		else
			# The generator produced no usable completion function
			# (bad template, tool CLI changed, ...). Staying
			# registered via compdef would leave this command's Tab
			# completion permanently dead -- every attempt would
			# re-run the failing generator and return nothing,
			# indistinguishable from "completions just don't work".
			# Deregister the stub and degrade to Zsh's default
			# completion instead, so one failed attempt falls back to
			# normal filename/default completion.
			compdef -d "$service" 2> /dev/null
			_default "$@"
		fi
	}
	if [ -r "$_completion_tools" ]; then
		while IFS='|' read -r _ct_name _ct_template _ct_shells _ct_strategy; do
			case "$_ct_name" in '' | \#*) continue ;; esac
			[ "$_ct_strategy" = "compdef" ] || continue
			case " $_ct_shells " in *' zsh '*) ;; *) continue ;; esac
			command -v "$_ct_name" > /dev/null 2>&1 || continue
			_lazy_completion_cmds[$_ct_name]="${_ct_template//SHELL/zsh}"
			compdef _lazy_completion_dispatch "$_ct_name"
		done < "$_completion_tools"
		unset _ct_name _ct_template _ct_shells _ct_strategy
	fi

	# aws-cli: same aws_completer mechanism as the Bash branch, bridged
	# through bashcompinit's `complete -C` emulation.
	if command -v aws_completer > /dev/null 2>&1; then
		autoload -Uz bashcompinit && bashcompinit
		complete -C "$(command -v aws_completer)" aws
	fi

	# pkl: `pkl shell-completion zsh` emits a bash-style script that
	# runs its own bare `compinit` (which would rewrite the dump at the
	# default ${ZDOTDIR:-$HOME}/.zcompdump path) and registers through
	# bashcompinit's `complete -F`, so neither generic strategy fits.
	# The lazy stub strips the script's own compinit/bashcompinit
	# bootstrap lines, provides bashcompinit itself, and lets the
	# script's `complete -F _pkl pkl` line re-register through the
	# bridge; the in-flight attempt then runs whatever that installed.
	if command -v pkl > /dev/null 2>&1; then
		_lazy_complete_pkl() {
			autoload -Uz bashcompinit && bashcompinit
			eval "$(pkl shell-completion zsh 2> /dev/null |
				grep -Ev '^(autoload -Uz (compinit|bashcompinit)|compinit|bashcompinit)[[:space:]]*$')" 2> /dev/null
			if [ -n "${_comps[pkl]:-}" ] && [ "${_comps[pkl]}" != "_lazy_complete_pkl" ]; then
				"${_comps[pkl]}" "$@"
			else
				return 1
			fi
		}
		compdef _lazy_complete_pkl pkl
	fi

	# fzf: eager (see _ct_fzf_init above for rationale). Must run
	# after compinit.
	_ct_fzf_init zsh

	unset _zcompdump _zcompinit_cache_safe _zstat_available
	unset -f _ct_path_safe
fi

unset -f _ct_fzf_init
unset _completion_tools
