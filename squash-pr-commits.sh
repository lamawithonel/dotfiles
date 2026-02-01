#!/usr/bin/env bash
#
# squash-pr-commits.sh
#
# Reorganizes the commits in the copilot/restructure-shell-config-files branch
# into logical, atomic commits following Linux kernel contribution guidelines.
#
# Usage:
#   ./squash-pr-commits.sh
#
# Prerequisites:
#   - Clean working directory (no uncommitted changes)
#   - Remote 'origin' points to lamawithonel/dotfiles
#   - yadm installed and configured
#

set -euo pipefail

BRANCH="copilot/restructure-shell-config-files"
BASE="master"

# Use yadm instead of git
GIT="git"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}==>${NC} $*"; }
warn() { echo -e "${YELLOW}==> WARNING:${NC} $*"; }
error() {
	echo        -e "${RED}==> ERROR:${NC} $*" >&2
	exit                                                1
}

# Commit messages for the squashed commits
read -r -d '' MSG_1 << 'EOF' || true
shell: add shared configuration foundation in .config/shell/

Create a shared shell configuration directory that can be sourced by
both Bash and Zsh. This establishes the foundation for multi-shell
support while reducing duplication.

New files:
  - .config/shell/path.sh: POSIX-compatible PATH management
  - .config/shell/environment.sh: Shared environment variables
  - .config/shell/colors.sh: Color definitions for Bash 4+ and Zsh
  - .config/shell/colors_null.sh: Null colors for dumb terminals

The _ensure_path_contains() function provides safe PATH manipulation
with automatic deduplication and removal of non-existent directories.
EOF

read -r -d '' MSG_2 << 'EOF' || true
bash: separate login and interactive shell concerns

Restructure Bash configuration to properly separate environment setup
(login shell) from interactive features (interactive shell).

Changes to .profile:
  - Add __PROFILE_SOURCED guard to prevent duplicate sourcing
  - Source shared configuration from .config/shell/

Changes to .bash_profile:
  - Source .profile for POSIX-compatible environment setup
  - Only source .bashrc for interactive shells

Changes to .bashrc:
  - Check __PROFILE_SOURCED and source .bash_profile if needed
  - Remove environment setup (now in .profile)
  - Focus on interactive features only

This ensures environment variables and PATH are set once at login,
not on every interactive shell, improving startup time and consistency
across terminal emulators that spawn login vs non-login shells.

Update .gitignore to exclude generated/cache files.
EOF

read -r -d '' MSG_3 << 'EOF' || true
zsh: add Zsh configuration with Bash-compatible settings

Add Zsh configuration files that parallel the Bash structure while
sharing common functionality through .config/shell/.

New files:
  - .zshenv: Minimal environment, sets XDG directories
  - .zprofile: Sources .profile for shared environment setup
  - .zshrc: Interactive configuration with Bash-compatibility settings
  - .zshrc.d/README.md: Documentation for modular configs

Zsh is configured to feel familiar to Bash users:
  - BASH_AUTO_LIST: Show completions on first tab without menu
  - NO_AUTO_MENU: Don't steal cursor with menu selection
  - NO_BANG_HIST: Disable ! history expansion
  - INTERACTIVE_COMMENTS: Allow # comments
  - Emacs keybindings with standard Home/End/Delete keys

Completion system uses fpath and compinit with XDG-compliant cache
location. RVM integration uses proper Zsh completion directory.
EOF

read -r -d '' MSG_4 << 'EOF' || true
shell: extract shared interactive config into rc.d directory

Create .config/shell/rc.d/ with categorized configuration files that
are sourced by both .bashrc and .zshrc. This eliminates duplication
and ensures consistent behavior across shells.

Directory structure uses numeric prefixes for load ordering:
  010-history.sh      - Shell history configuration
  100-path-setup.sh   - PATH and environment setup
  200-colors.sh       - Color theme and dircolors
  210-prompt.sh       - Starship prompt initialization
  300-aliases.sh      - Common aliases (vi, rm, cp, mv, ls, etc.)
  310-functions.sh    - Utility functions (hadolint)
  400-fnm.sh          - Fast Node Manager
  410-pyenv.sh        - Python environment manager
  440-rvm.sh          - Ruby version manager
  500-completions.sh  - Tool completions (pipenv, rustup, probe-rs)
  600-path-print.sh   - Display final PATH for debugging
  690-local.sh        - Source local additions (.bashrc.d, .zshrc.d)

Files use Bash syntax with shell-detection for Zsh-specific behavior.
All files pass shellcheck with --shell=bash.
EOF

read -r -d '' MSG_5 << 'EOF' || true
docs: add shell configuration documentation and Starship alternates

Add comprehensive documentation explaining the shell configuration
structure, startup flow, and cross-platform support.

New files:
  - SHELL_CONFIG.md: Overview of file structure and how it works
  - .config/shell/rc.d/README.md: rc.d taxonomy and guidelines

Use yadm alternate files for Starship configuration to handle the
sudo module differently between work and personal machines:
  - .config/starship.toml##default: Standard configuration
  - .config/starship.toml##class.work: Work configuration with
    sudo module disabled

This replaces the runtime `toml set` hack which was slow and required
the toml-cli tool to be installed.
EOF

read -r -d '' MSG_6 << 'EOF' || true
perf: remove fallback prompts and optimize startup time

Remove fallback prompts and bash-preexec to improve shell startup
time. Starship is now required for the prompt.

Removed:
  - Fallback _prompt_command() function in .bashrc
  - Fallback vcs_info prompt in .zshrc
  - bash-preexec library and git clone logic
  - update_gpg_agent_startup_tty preexec hook

The GPG TTY update is now handled by a simple DEBUG trap in Bash
and native preexec in Zsh, eliminating the bash-preexec dependency.

Reorganize path setup into focused files for clarity:
  - 100-environment.sh: Environment variables and GPG setup
  - 110-path.sh: PATH management function and additions

Fix tab indentation to match vi modeline (ts=4:sw=4:noexpandtab).
EOF

# --- Pre-flight checks ---

info "Checking prerequisites..."

# Check yadm is available
if ! command -v yadm &> /dev/null; then
	error  "yadm is not installed or not in PATH"
fi

# Check for clean working directory
if ! $GIT diff --quiet || ! $GIT diff --cached --quiet; then
	error  "Working directory is not clean. Please commit or stash changes first."
fi

# Fetch latest
info "Fetching latest from origin..."
$GIT fetch origin

# Check branch exists
if ! $GIT rev-parse --verify "origin/${BRANCH}" &> /dev/null; then
	error  "Branch origin/${BRANCH} does not exist"
fi

# --- Create backup ---

BACKUP_BRANCH="${BRANCH}-backup-$(date +%Y%m%d-%H%M%S)"
info "Creating backup branch: ${BACKUP_BRANCH}"
$GIT branch "${BACKUP_BRANCH}" "origin/${BRANCH}"

# --- Checkout and reset to branch ---

info "Checking out ${BRANCH}..."
$GIT checkout "${BRANCH}" 2> /dev/null || $GIT checkout -b "${BRANCH}" "origin/${BRANCH}"
$GIT reset --hard "origin/${BRANCH}"

# --- Get the merge base ---

MERGE_BASE=$($GIT merge-base "${BASE}" "${BRANCH}")
info "Merge base: ${MERGE_BASE}"

# --- Perform the rebase ---

info "Starting reorganization..."

# Reset to merge base, keeping all changes staged
$GIT reset --soft "${MERGE_BASE}"

# Unstage everything
$GIT reset HEAD .

# --- Commit 1: Shared shell configuration foundation ---
info "Creating commit 1/6: shell: add shared configuration foundation"

$GIT add .config/shell/path.sh \
	.config/shell/environment.sh \
	.config/shell/colors.sh \
	.config/shell/colors_null.sh \
	2> /dev/null      || true

# Only commit if we have staged changes
if ! $GIT diff --cached --quiet; then
	$GIT  commit -m "$MSG_1"
else
	warn  "No changes for commit 1, skipping..."
fi

# --- Commit 2: Bash login/interactive separation ---
info "Creating commit 2/6: bash: separate login and interactive shell concerns"

$GIT add .profile \
	.bash_profile \
	.bashrc \
	.gitignore \
	2> /dev/null      || true

if ! $GIT diff --cached --quiet; then
	$GIT  commit -m "$MSG_2"
else
	warn  "No changes for commit 2, skipping..."
fi

# --- Commit 3: Zsh support ---
info "Creating commit 3/6: zsh: add Zsh configuration"

$GIT add .zshenv \
	.zprofile \
	.zshrc \
	.zshrc.d \
	.config/zsh \
	2> /dev/null      || true

if ! $GIT diff --cached --quiet; then
	$GIT  commit -m "$MSG_3"
else
	warn  "No changes for commit 3, skipping..."
fi

# --- Commit 4: rc.d directory ---
info "Creating commit 4/6: shell: extract shared interactive config into rc.d"

$GIT add .config/shell/rc.d/*.sh \
	2> /dev/null      || true

if ! $GIT diff --cached --quiet; then
	$GIT  commit -m "$MSG_4"
else
	warn  "No changes for commit 4, skipping..."
fi

# --- Commit 5: Documentation and Starship alternates ---
info "Creating commit 5/6: docs: add documentation and Starship alternates"

$GIT add SHELL_CONFIG.md \
	.config/shell/rc.d/README.md \
	'.config/starship.toml##default' \
	'.config/starship.toml##class.work' \
	.config/starship.toml \
	2> /dev/null      || true

if ! $GIT diff --cached --quiet; then
	$GIT  commit -m "$MSG_5"
else
	warn  "No changes for commit 5, skipping..."
fi

# --- Commit 6: Everything else (optimizations, fixes) ---
info "Creating commit 6/6: perf: remove fallback prompts and optimize startup"

$GIT add -A

if ! $GIT diff --cached --quiet; then
	$GIT  commit -m "$MSG_6"
else
	warn  "No changes for commit 6, skipping..."
fi

# --- Verify ---

info "Reorganization complete!"
echo ""
info "New commit history:"
$GIT log --oneline "${BASE}..${BRANCH}"

echo ""
info "Comparing to original branch (should be empty if content is identical):"
if $GIT diff "${BACKUP_BRANCH}" --stat | head -20; then
	if  ! $GIT diff "${BACKUP_BRANCH}" --quiet; then
		warn     "There are differences from the original! Review carefully."
	else
		info     "Content is identical to original branch."
	fi
fi

echo ""
info "Backup branch preserved at: ${BACKUP_BRANCH}"
echo ""
warn "To push the reorganized commits (FORCE PUSH REQUIRED):"
echo "    yadm push --force-with-lease origin ${BRANCH}"
echo ""
warn "To restore the original if something went wrong:"
echo "    yadm checkout ${BRANCH}"
echo "    yadm reset --hard ${BACKUP_BRANCH}"
echo ""

