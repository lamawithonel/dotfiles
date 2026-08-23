---
paths:
  - "**/*.sh"
  - "**/*.bash"
---

# Instructions for Writing POSIX Shell and Bash

## Safety & Script Initialization

- Prefer safety over speed or compactness; treat shell scripts as production software.
- Set strict shell options at script start, one per line:
  ```shell
  set -o errexit
  set -o nounset
  ```
  *(Add `set -o pipefail` in `#!/bin/bash` or `#!/usr/bin/env bash` scripts).*
- Prefer POSIX syntax (`#!/bin/sh`) by default; use Bash/Zsh extensions only when they provide significant safety or performance benefits.
- Quote all string literals with 'hard single quotes'; use "soft double quotes" only when variable expansion or command substitution is required.
- Enclose variables in curly braces during interpolation: `"${HOME}/path/to/file"`; standalone variables may omit braces: `"$file"`.
- Initialize standard XDG Base Directory Specification (v0.8) variables with strict absolute fallbacks at script top:
  ```shell
  # User-specific primary base directories
  readonly XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
  readonly XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
  readonly XDG_STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
  readonly XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"

  # System preference-ordered search paths (colon-delimited)
  readonly XDG_CONFIG_DIRS="${XDG_CONFIG_DIRS:-/etc/xdg}"
  readonly XDG_DATA_DIRS="${XDG_DATA_DIRS:-/usr/local/share/:/usr/share/}"

  # User executable binaries path
  readonly XDG_BIN_HOME="${HOME}/.local/bin"

  # User-specific runtime directory with 0700 fallback
  if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
  	XDG_RUNTIME_DIR="${TMPDIR:-/tmp}/runtime-$(id -u 2>/dev/null || echo "$USER")"
  	if [ ! -d "$XDG_RUNTIME_DIR" ]; then
  		mkdir -m 0700 -p "$XDG_RUNTIME_DIR"
  	fi
  fi
  readonly XDG_RUNTIME_DIR
  ```
- Adhere strictly to XDG file categorization:
  - `XDG_CONFIG_HOME`: Configuration files and settings that the user directly controls.
  - `XDG_DATA_HOME`: Persistent data files and assets essential to application functionality (e.g., databases, templates, plugins).
  - `XDG_STATE_HOME`: State data persisting between restarts that is not configuration (e.g., logs, history, recently used files, window layouts).
  - `XDG_CACHE_HOME`: Non-essential cached data that can be purged at any time without data loss.
  - `XDG_RUNTIME_DIR`: Short-lived runtime objects (sockets, named pipes, pidfiles); must have `0700` permissions.
- When creating non-existent destination directories to write files, create them with `0700` permissions (`mkdir -m 0700 -p "$dir"`).
- Identify the executable name safely for messages: `SELF_NAME="$(basename "$0")" && readonly SELF_NAME`.
- Validate required external tools at initialization:
  ```shell
  _in_search_path() { command -v "$1" >/dev/null 2>&1; }
  _in_search_path git || _err "Cannot find \`git\`. Please ensure it is installed and in \$PATH."
  ```

## Architecture, State & Lifecycles

- Emulate RAII cleanup via `trap`: always register a `_cleanup` handler at script start to remove temporary files, restore state, or unset exported environment variables:
  ```shell
  trap _cleanup EXIT INT TERM HUP

  _cleanup() {
  	rm -f "${XDG_CACHE_HOME}/temp-artifact"
  	unset GIT_DIR
  }
  ```
- Use subshells `(cd "$target_dir" && command)` when changing directories to avoid polluting the parent shell process's working directory.
- Batch `export` and `unset` calls where possible as a micro-optimization.
- Unset temporary variables and one-off helper functions after use in long-running shell environments.

## Argument Parsing & CLI Design

- Prefer portable POSIX `while [ "$#" -gt 0 ]` + `case` + `shift` over `getopt` or `getopts` to support long options uniformly across Linux, macOS, and BSD:
  ```shell
  while [ "$#" -gt 0 ]; do
  	case "$1" in
  		--ref)
  			shift
  			_version="$1"
  			;;
  		-h | --help)
  			_usage
  			exit 0
  			;;
  		*)
  			echo "ERROR: Unrecognized argument: $1" >&2
  			_usage
  			exit 1
  			;;
  	esac
  	shift
  done
  ```
- Provide a dedicated `_usage()` function using indented `cat <<- EOF` heredocs detailing usage syntax, available commands, and all supported flags.

## Logging & Error Handling

- Standardize script logging to support dual console and log-file output:
  ```shell
  _info() { echo "[INFO]    $*" >> "$LOG_FILE" 2>&1; }
  _warn() { echo "[WARNING] $*" | tee -a "$LOG_FILE" >&2; }
  _err()  { echo "[ERROR]   $*" | tee -a "$LOG_FILE" >&2 && exit 1; }
  ```
- For lightweight utility scripts without file logging, use a standard `_fail` / `_die` helper:
  ```shell
  _fail() {
  	echo "ERROR: $*" >&2
  	exit "${2:-1}"
  }
  ```
- Never ignore command exit codes; handle expected failures explicitly (`command || _status=$?`).

## Naming, Style & Formatting Conventions

- Indent with tabs, not spaces.  Spaces MAY be used after tabs inside `<<-` heredoc payloads to align formatted text.
- Split long pipelines and logical chains with the binary operator leading the continuation line (`|`, `&&`, `||`).
- Indent `case` alternatives one level from `case`/`esac`, and their actions one level further.
- Put one space after redirection operators: `> "$file"`, not `>"$file"`.
- Preserve column alignment across neighboring lines of similar structure (e.g., aligned variable assignments or trailing comments).
- Naming rules:
  - `UPPER_SNAKE_CASE` (no leading underscore) for constants, environment variables, and public exported identifiers.
  - `_underscore_lead_lower_snake_case` for local variables, private variables, and helper functions (e.g., `_cleanup`, `_prep`, `_in_search_path`).
  - `lower_snake_case` (no leading underscore) for public utility functions intended for cross-file sourcing or interactive user invocation.

## Testing

- Write automated test suites with `bats-core` (`bats test/`); follow the Arrange-Act-Assert (AAA) pattern.
- Mock destructive system commands and external network endpoints in test harnesses.
- Test success paths, failure exit codes, missing flags, and edge cases (spaces in filenames, missing directories).

## Static Checks & Quality Gates

Run the verification battery after creating or editing any shell script.

### The Battery

    sh -n FILE                     # bash -n for Bash-dialect scripts
    shellcheck FILE
    shfmt -d -bn -ci -sr -kp FILE  # diff must be empty
    checkbashisms FILE             # #!/bin/sh scripts only
    shellmetrics FILE              # CCN <= 10 / function, <= 8 file average

### Pass Criteria & Exceptions

- **`sh -n` / `bash -n`**: 0 syntax errors (zero-cost gate).
- **`shellcheck`**: 0 errors, 0 warnings (exit code 0).
- **`shfmt`**: Diff must be empty (exit code 0).
- **`checkbashisms`**: 0 bashisms in `#!/bin/sh` scripts.
- **`shellmetrics`**: Cyclomatic complexity <= 10 per function; file average <= 8.
- **Large Dispatch Table Exception**: Functions consisting of a single flat `case` dispatch table may reach CCN 16 when branches are <= 5 lines with zero nested conditionals.
- **Throwaway Script Exemption**: Ad-hoc, one-line scratchpad scripts are exempt from `shellmetrics`.

## Documentation

- Document script purpose, CLI flags, arguments, environment variables, and exit codes in a top-level header comment.
- Focus function comments on non-obvious shell quirks, subshell side effects, and boundary requirements.
