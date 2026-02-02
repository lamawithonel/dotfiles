# Shell RC Directory

This directory contains shared shell configuration snippets that are sourced by both Bash and Zsh.

## File Format

All files use `#!/usr/bin/env bash` shebang and `# shellcheck shell=bash` directive. While they use Bash syntax for performance and convenience, they are written to be compatible with both Bash and Zsh through conditional logic.

## Organization

Files are numbered with three-digit prefixes to control load order. The taxonomy is:

### Category Ranges

- **000-099**: Core shell configuration (history, completion basics)
- **100-199**: PATH and environment setup
- **200-299**: Visual configuration (colors, prompts)
- **300-399**: Aliases and utility functions
- **400-499**: Language/tool environment managers
- **500-599**: Tool completions
- **600-699**: Final setup and local overrides

### Current Files

- `010-history.sh` - History configuration for both Bash and Zsh
- `050-environment.sh` - General environment variables and regex patterns (IPv4_ADDRESS, IPv4_SUBNET, HOSTNAME_REGEX)
- `100-path-setup.sh` - PATH management with _ensure_path_contains function and PATH setup
- `110-gpg-ssh.sh` - GPG_TTY and SSH_AUTH_SOCK configuration
- `200-colors.sh` - Color and dircolors setup, tinty/base16 initialization
- `210-prompt.sh` - Starship prompt initialization
- `300-aliases.sh` - Common aliases (vi, rm, cp, mv, ls, etc.)
- `310-functions.sh` - Utility functions (hadolint, etc.)
- `400-mise.sh` - Mise polyglot runtime manager (includes Rust via rustup)
- `500-completions.sh` - Tool completions (pipenv)
- `600-path-print.sh` - Display final PATH with colored highlighting
- `690-local.sh` - Source local additions (.rc.d, .rc.local files)

## Shell-Specific Handling

Files in this directory use Bash syntax but work with both Bash and Zsh. When shell-specific logic is needed, use:

```bash
if [ -n "$BASH_VERSION" ]; then
    # Bash-specific code
elif [ -n "$ZSH_VERSION" ]; then
    # Zsh-specific code
fi
```

## Shellcheck Compliance

All files pass `shellcheck` without errors when checked with `--shell=bash`. The only warnings are:
- SC1091 (info): "Not following" warnings for external files that may not exist
- These are expected and suppressed with appropriate shellcheck directives

## Adding New Files

1. Choose the appropriate category range (e.g., 400-499 for a new language manager)
2. Pick a number within that range
3. Name the file with format: `NNN-description.sh`
4. Use shebang: `#!/usr/bin/env bash` and directive: `# shellcheck shell=bash`
5. Add a header comment explaining the purpose and category
6. Ensure the file works with both Bash and Zsh (or handle differences explicitly)
7. Test with `bash -n filename.sh` and `shellcheck filename.sh`

## Consolidated Files

The following standalone files were consolidated into rc.d files:
- `.config/shell/path.sh` → Split and merged into `050-environment.sh`, `100-path-setup.sh`, and `110-gpg-ssh.sh`
- `.config/shell/environment.sh` → Split and merged into `050-environment.sh`, `100-path-setup.sh`, and `110-gpg-ssh.sh`

The files `.config/shell/colors.sh` and `.config/shell/colors_null.sh` remain standalone as they contain large data structures (associative arrays) that are sourced by `200-colors.sh`.
