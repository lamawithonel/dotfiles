#!/bin/sh
# bootstrap-work.sh -- gh-only, mise-registered portable toolchain install.
#
# Installs jj, ast-grep, and difftastic (cocogitto optionally, via
# --with-cocogitto) on a locked-down machine where the sandbox excludes
# `gh`, `pip`, `pip3`, and `sbt` from its network policy but subjects
# every other process -- including mise itself -- to a domain allowlist
# that does NOT cover GitHub's release-asset CDN
# (release-assets.githubusercontent.com).
#
# Design (see wave-4 dive receipt for the live proof of each claim):
#   1. FETCH   -- `gh release download` (gh is unsandboxed: its network
#                 path never touches the sandbox's allowlist at all).
#   2. VERIFY  -- sha256 against a TOFU-pinned manifest below (none of
#                 the four upstream repos publish a checksums file, so
#                 this script IS the checksum authority: the hashes were
#                 captured from a live `gh release download` +
#                 `sha256sum` run on the tag/asset named in the
#                 manifest -- see MANIFEST CAPTURE below), plus a
#                 best-effort `gh attestation verify` that is
#                 non-fatal ONLY on "no attestation published" (all
#                 four repos returned that as of the capture date) and
#                 fatal on any other outcome, so the script
#                 automatically upgrades itself the day any of these
#                 projects starts publishing attestations.
#   3. INSTALL -- extract to $VCS_TOOLCHAIN_STATE_ROOT/<tool>/<version>/,
#                 a location this script owns (never inside mise's own
#                 installs/ tree), then a --version sanity check.
#   4. REGISTER -- `mise link` that directory into mise's install tree
#                 (pure filesystem symlink, zero network -- this is
#                 mise's own documented mechanism for "installs either
#                 custom compiled outside mise or built with a
#                 different tool"), then `mise config set --file
#                 <global config>` to pin the version.  `mise config
#                 set` writes TOML directly and, like `mise link`, was
#                 proven live to make zero network calls -- unlike
#                 `mise use`, which unconditionally probes
#                 mise-versions.jdx.dev and api.github.com even when
#                 the version is already linked locally (non-fatal, but
#                 3 retries x up to ~3s backoff x 4 tools of pure
#                 latency for nothing, so this script does not call it).
#
# MANIFEST CAPTURE
#   Captured 2026-08-10 on x86_64 linux (glibc host) via:
#     gh release view <tag> --repo <repo> --json tagName,assets
#     gh release download <tag> --repo <repo> --pattern '<asset>'
#     sha256sum '<asset>'
#   To bump a tool version: repeat those three commands for the new
#   tag, paste the new tag/asset/sha256 into the matching
#   bootstrap_tool call below, and re-run this script.  A mismatch
#   against the pinned hash is always fatal (P-FAIL-CLOSED) -- there is
#   deliberately no "trust the download and record what I got" path.
#
# Attestation finding (2026-08-10): `gh attestation verify` against the
# freshly downloaded asset returned HTTP 404 "no attestations found"
# for all four of jj-vcs/jj, ast-grep/ast-grep, Wilfred/difftastic, and
# cocogitto/cocogitto, both --repo- and --owner-scoped.  None of the
# four publish GitHub Artifact Attestations today.  The sha256 pin
# above is therefore this script's real integrity anchor, not the
# attestation check -- the attestation check is kept as a forward
# looking, fail-closed-on-failure, no-op-on-absence safety net.
#
# Requires on PATH: gh (authenticated), mise, tar, unzip, sha256sum (or
# shasum/openssl), mktemp.  No curl.  No network calls outside gh's own
# (unsandboxed) HTTPS to GitHub.

set -o errexit
set -o nounset

readonly SCRIPT_NAME="bootstrap-work.sh"
STATE_ROOT="${VCS_TOOLCHAIN_STATE_ROOT:-$HOME/.local/state/vcs-toolchain}"
GLOBAL_MISE_CFG="${MISE_CONFIG_DIR:-$HOME/.config/mise}/config.toml"
WITH_COCOGITTO=0
INSTALLED=""
FAILED=""

log() {
	printf '%s: %s\n' "$SCRIPT_NAME" "$*" >&2
}

die() {
	printf '%s: FATAL: %s\n' "$SCRIPT_NAME" "$*" >&2
	exit 1
}

usage() {
	cat <<- EOF
		Usage: $SCRIPT_NAME [--with-cocogitto] [-h|--help]

		Installs jj, ast-grep, and difftastic via unsandboxed gh + mise link.
		Pass --with-cocogitto to also install cocogitto (not yet adopted by
		the vcs-workflow redesign; opt-in only).

		Env overrides:
		  VCS_TOOLCHAIN_STATE_ROOT  default: \$HOME/.local/state/vcs-toolchain
		  MISE_CONFIG_DIR           default: \$HOME/.config/mise
	EOF
}

need_cmd() {
	command -v "$1" > /dev/null 2>&1 || die "required command not found on PATH: $1"
}

sha256_of() {
	# Portable sha256: prefer sha256sum, fall back to shasum/openssl.
	_f=$1
	if command -v sha256sum > /dev/null 2>&1; then
		sha256sum "$_f" | awk '{print $1}'
	elif command -v shasum > /dev/null 2>&1; then
		shasum -a 256 "$_f" | awk '{print $1}'
	elif command -v openssl > /dev/null 2>&1; then
		openssl dgst -sha256 -r "$_f" | awk '{print $1}'
	else
		die "no sha256 tool found (need sha256sum, shasum, or openssl)"
	fi
}

extract_archive() {
	_archive=$1
	_destdir=$2
	case "$_archive" in
		*.zip)
			unzip -q -o "$_archive" -d "$_destdir"
			;;
		*.tar.gz | *.tgz)
			tar -xzf "$_archive" -C "$_destdir"
			;;
		*)
			die "extract_archive: unsupported archive suffix: $_archive"
			;;
	esac
}

verify_attestation() {
	# Best-effort: OK on real verification, WARN-and-continue on "no
	# attestation published" (confirmed 0/4 upstream repos as of the
	# manifest capture date), FATAL on any other failure shape --
	# a rejected/invalid attestation must never be waved through.
	_file=$1
	_repo=$2
	_att_out=$(gh attestation verify "$_file" --repo "$_repo" 2>&1) && {
		log "attestation: OK verified for $_repo ($_file)"
		return 0
	}
	case "$_att_out" in
		*"HTTP 404"*"attestations/sha256:"*)
			log "attestation: none published by $_repo (known gap, sha256 pin is the integrity anchor here)"
			return 0
			;;
		*)
			die "attestation verify failed for $_repo ($_file), and it is not the known no-attestation-published case: $_att_out"
			;;
	esac
}

# bootstrap_tool NAME REPO TAG ASSET SHA256 VERSION SUBDIR BIN...
#   NAME    mise registry short name (jj, ast-grep, difftastic, cocogitto)
#   REPO    owner/repo on GitHub
#   TAG     release tag as gh expects it
#   ASSET   exact linux-x86_64 asset filename
#   SHA256  pinned expected sha256 of ASSET (lowercase hex, 64 chars)
#   VERSION mise version string to pin (no leading "v")
#   SUBDIR  path inside the extracted archive containing the binaries,
#           or "" if the archive is already flat
#   BIN...  one or more binary filenames (relative to SUBDIR); the
#           first is the primary binary used for the --version sanity
#           check
bootstrap_tool() {
	_name=$1
	_repo=$2
	_tag=$3
	_asset=$4
	_sha256=$5
	_version=$6
	_subdir=$7
	shift 7
	# Remaining positional args ($@): binary filenames.
	if [ "$#" -eq 0 ]; then
		die "bootstrap_tool $_name: no binaries listed"
	fi
	_primary_bin=$1

	log "=== $_name $_version ($_repo @ $_tag) ==="

	_dl_dir="$STATE_ROOT/.download/$_name"
	rm -rf "$_dl_dir"
	mkdir -p "$_dl_dir"

	log "fetching $_asset via gh (unsandboxed)"
	gh release download "$_tag" --repo "$_repo" \
		--pattern "$_asset" --dir "$_dl_dir" --clobber \
		|| die "$_name: gh release download failed"

	_dl_file="$_dl_dir/$_asset"
	[ -f "$_dl_file" ] || die "$_name: expected asset missing after download: $_dl_file"

	_got_sha256=$(sha256_of "$_dl_file")
	if [ "$_got_sha256" != "$_sha256" ]; then
		die "$_name: sha256 mismatch for $_asset -- expected $_sha256, got $_got_sha256 (P-FAIL-CLOSED, refusing to install)"
	fi
	log "checksum: OK ($_got_sha256)"

	verify_attestation "$_dl_file" "$_repo"

	_tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/vcs-toolchain-bootstrap.XXXXXX")
	extract_archive "$_dl_file" "$_tmpdir" \
		|| die "$_name: extraction failed"

	if [ -n "$_subdir" ]; then
		_srcdir="$_tmpdir/$_subdir"
	else
		_srcdir="$_tmpdir"
	fi
	[ -d "$_srcdir" ] || die "$_name: expected extracted subdir missing: $_srcdir"

	for _bin in "$@"; do
		_binpath="$_srcdir/$_bin"
		[ -f "$_binpath" ] || die "$_name: expected binary missing after extraction: $_binpath"
		chmod +x "$_binpath"
	done

	_version_out=$("$_srcdir/$_primary_bin" --version 2>&1) \
		|| die "$_name: $_primary_bin --version failed to run: $_version_out"
	case "$_version_out" in
		*"$_version"*) : ;;
		*) die "$_name: $_primary_bin --version did not report $_version: $_version_out" ;;
	esac
	log "sanity check: OK ($_primary_bin --version reports $_version)"

	_install_dir="$STATE_ROOT/$_name/$_version"
	mkdir -p "$STATE_ROOT/$_name"
	rm -rf "$_install_dir"
	mv "$_srcdir" "$_install_dir"
	rm -rf "$_tmpdir" "$_dl_dir"

	mise link --force "${_name}@${_version}" "$_install_dir" \
		|| die "$_name: mise link failed"

	[ -f "$GLOBAL_MISE_CFG" ] || : > "$GLOBAL_MISE_CFG"
	mise config set --file "$GLOBAL_MISE_CFG" "tools.${_name}" "$_version" > /dev/null \
		|| die "$_name: mise config set failed"

	_x_out=$(mise x -- "$_primary_bin" --version 2>&1) \
		|| die "$_name: post-install 'mise x -- $_primary_bin --version' failed: $_x_out"
	case "$_x_out" in
		*"$_version"*) : ;;
		*) die "$_name: post-install mise x did not report $_version: $_x_out" ;;
	esac

	log "$_name $_version: registered with mise, verified end to end"
	INSTALLED="$INSTALLED ${_name}=${_version}"
}

main() {
	for arg in "$@"; do
		case "$arg" in
			--with-cocogitto)
				WITH_COCOGITTO=1
				;;
			-h | --help)
				usage
				exit 0
				;;
			*)
				usage >&2
				die "unknown argument: $arg"
				;;
		esac
	done

	need_cmd gh
	need_cmd mise
	need_cmd tar
	need_cmd unzip
	need_cmd mktemp

	gh auth status > /dev/null 2>&1 || die "gh is not authenticated (run: gh auth login)"

	mkdir -p "$STATE_ROOT"

	bootstrap_tool jj jj-vcs/jj v0.44.0 \
		jj-v0.44.0-x86_64-unknown-linux-musl.tar.gz \
		0a07bab4641a55fd2bc2fd1563ba3a3f9a577584086ad74086a1c5b69b3ffce9 \
		0.44.0 "" jj \
		|| FAILED="$FAILED jj"

	bootstrap_tool ast-grep ast-grep/ast-grep 0.45.1 \
		app-x86_64-unknown-linux-gnu.zip \
		76fb6555be6734fb5057dba8d2fb756430f374bb9e1af694cf1ce00e13238d63 \
		0.45.1 "" ast-grep sg \
		|| FAILED="$FAILED ast-grep"

	bootstrap_tool difftastic Wilfred/difftastic 0.70.0 \
		difft-x86_64-unknown-linux-gnu.tar.gz \
		2997d2bbe620534edbd79b0049f00ce84eef3fedb15c7822456d58e38d8b05c9 \
		0.70.0 "" difft \
		|| FAILED="$FAILED difftastic"

	if [ "$WITH_COCOGITTO" -eq 1 ]; then
		bootstrap_tool cocogitto cocogitto/cocogitto 7.0.0 \
			cocogitto-7.0.0-x86_64-unknown-linux-musl.tar.gz \
			e03938ff2c4c86d71c00c0f3284dbbe95c5ca76fe34a51f33e945c23010d59bb \
			7.0.0 x86_64-unknown-linux-musl cog \
			|| FAILED="$FAILED cocogitto"
	fi

	if [ -n "$FAILED" ]; then
		printf 'BOOTSTRAP-FAIL installed=[%s] failed=[%s]\n' "$INSTALLED" "$FAILED"
		exit 1
	fi
	printf 'BOOTSTRAP-OK installed=[%s]\n' "$INSTALLED"
}

main "$@"
