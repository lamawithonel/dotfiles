# Shell Configuration Structure

This repository contains shell configuration files that follow best practices for login vs interactive shell separation, with support for both Bash and Zsh.

## Overview

The configuration is structured to:
1. **Separate login and interactive concerns**: Environment setup happens once at login, not on every shell
2. **Support multiple shells**: Bash and Zsh share common functionality while maintaining shell-specific features
3. **Use guard variables**: Prevent duplicate environment initialization
4. **Follow XDG Base Directory Specification**: Keep configuration organized and discoverable

## File Structure

### Login Shell Configuration

**`.profile`** - POSIX-compatible environment setup (sourced by login shells)
- Sets up XDG Base Directory variables
- Defines language-specific environment variables (CARGO_HOME, PYENV_ROOT, etc.)
- Sources shared configuration from `.config/shell/`
- Uses `__PROFILE_SOURCED` guard variable to prevent duplicate sourcing

### Bash Configuration

**`.bash_profile`** - Bash login shell entry point
- Sources `.profile` if not already sourced
- Sets up Bash-specific XDG directories
- Sources Bash-specific profile.d scripts

**`.bashrc`** - Bash interactive shell configuration
- Checks for `__PROFILE_SOURCED` and sources `.bash_profile` if needed
- Configures interactive features: history, prompt, aliases, completions
- Sources `.bashrc.d/*.sh` for modular configuration
- Sources `.bashrc.local` for machine-specific configuration

**`.bashrc.d/`** - Modular Bash configuration (optional)
- Place additional `.sh` files here for organization

**`.bashrc.local`** - Machine-specific Bash configuration (optional, not tracked)

### Zsh Configuration

**`.zshenv`** - Zsh environment (sourced by all Zsh instances)
- Minimal configuration, can set ZDOTDIR if desired

**`.zprofile`** - Zsh login shell entry point
- Sources `.profile` using `emulate sh` for POSIX compatibility
- Sets up Zsh-specific XDG directories
- Sources Zsh-specific profile.d scripts

**`.zshrc`** - Zsh interactive shell configuration
- Checks for `__PROFILE_SOURCED` and sources `.zprofile` if needed
- Configured with Bash-compatibility settings for familiar behavior
- Enables Zsh's built-in PATH deduplication (`typeset -U PATH`)
- Configures interactive features: history, prompt, aliases, completions
- Sources `.zshrc.d/*.sh` for modular configuration
- Sources `.zshrc.local` for machine-specific configuration

**`.zshrc.d/`** - Modular Zsh configuration (optional)
- Place additional `.sh` files here for organization

**`.zshrc.local`** - Machine-specific Zsh configuration (optional, not tracked)

### Shared Configuration

**`.config/shell/path.sh`** - POSIX-compatible PATH management
- `_ensure_path_contains()` function for safe PATH manipulation
- Works identically in Bash, Zsh, and other POSIX shells

**`.config/shell/environment.sh`** - Shared environment variables
- Defines regex patterns (IPv4_ADDRESS, HOSTNAME_REGEX)
- Sets up GPG_TTY and SSH_AUTH_SOCK

**`.config/shell/colors.sh`** - Color definitions for colorful terminals
- Defines ANSI and BASE16 color arrays
- Works in both Bash 4.0+ and Zsh
- Uses `$'...'` quoting for escape sequences

**`.config/shell/colors_null.sh`** - Null colors for dumb terminals
- Same structure as colors.sh but with empty values

### Shell-Specific Configuration Directories

**`.config/bash/`** - Bash-specific configuration
- Legacy location for Bash configs (colors have been moved to shared location)

**`.config/zsh/`** - Zsh-specific configuration
- Place Zsh-specific scripts here
- `profile.d/` - Scripts sourced during Zsh login

## How It Works

### Login Shell (e.g., SSH, macOS Terminal, WSL)

1. Shell starts as login shell
2. **Bash**: Sources `.bash_profile` → `.profile` (with guard)
3. **Zsh**: Sources `.zprofile` → `.profile` (with guard via `emulate sh`)
4. `.profile` sets `__PROFILE_SOURCED=1` and sources shared configs
5. If interactive, continues to `.bashrc` or `.zshrc`
6. Interactive config checks `__PROFILE_SOURCED` and skips login setup

### Non-Login Interactive Shell (e.g., Gnome Terminal, new Alacritty window)

1. Shell starts as interactive but not login
2. **Bash**: Sources `.bashrc` directly
3. **Zsh**: Sources `.zshrc` directly
4. Interactive config checks `__PROFILE_SOURCED`
5. If not set, sources `.bash_profile` or `.zprofile` to ensure environment is set up
6. Continues with interactive setup

## Key Features

### Guard Variable

The `__PROFILE_SOURCED` variable prevents duplicate environment initialization:

```sh
# In .profile
[ -n "$__PROFILE_SOURCED" ] && return
__PROFILE_SOURCED=1
export __PROFILE_SOURCED
```

### PATH Management

The `_ensure_path_contains` function provides safe PATH manipulation:

```sh
# Add to beginning (default)
_ensure_path_contains /usr/local/bin

# Add to end
_ensure_path_contains /opt/bin after

# Automatically removes non-existent directories
# Prevents duplicates
```

### Zsh Bash-Compatibility Settings

Zsh is configured to feel like Bash for muscle memory:

- `BASH_AUTO_LIST` - List completions on first tab
- `NO_AUTO_MENU` - Don't show menu on second tab
- `NO_BANG_HIST` - Disable ! history expansion
- `INTERACTIVE_COMMENTS` - Allow # comments
- Emacs key bindings (like Bash default)

## Cross-Platform Support

The configuration works on:
- **Linux**: Gentoo, Ubuntu, etc. (Gnome Terminal, Alacritty, Ghostty, Zellij)
- **macOS**: With iTerm2 integration and Homebrew support
- **Windows**: WSL2 (Windows Terminal, Ghostty, Alacritty)
- **Remote**: SSH to OpenBSD, FreeBSD, OpenWRT
- **Console**: Serial terminals and OS consoles

## Customization

### Machine-Specific Configuration

Create `.bashrc.local` or `.zshrc.local` for machine-specific settings that shouldn't be tracked in git.

### Modular Configuration

Place additional scripts in:
- `.bashrc.d/*.sh` for Bash
- `.zshrc.d/*.sh` for Zsh

These are sourced automatically at the end of interactive shell initialization.

## Testing

All configuration files pass syntax checks:

```sh
# Bash
bash -n .profile
bash -n .bash_profile
bash -n .bashrc
bash -n .config/shell/*.sh

# Zsh (if installed)
zsh -n .zshenv
zsh -n .zprofile
zsh -n .zshrc
```

## Troubleshooting

### PATH not updated

- Check that `.profile` is being sourced (echo `$__PROFILE_SOURCED`)
- Verify XDG directories are set correctly (echo `$XDG_CONFIG_HOME`)
- Ensure `.config/shell/path.sh` exists and is readable

### Colors not working

- Check terminal color support: `tput colors`
- Verify color file is being sourced from `.config/shell/`
- For dumb terminals, `colors_null.sh` should be loaded instead

### Duplicate initialization

- Check that `__PROFILE_SOURCED` guard is working
- Verify `.profile` is only sourced once per session
- Use `set -x` temporarily to trace sourcing order

## Migration from Old Configuration

The old Bash configuration has been refactored:
- Environment setup moved from `.bashrc` to `.profile`
- Colors moved from `.config/bash/colors.bash` to `.config/shell/colors.sh`
- PATH function moved from `.bashrc` to `.config/shell/path.sh`
- All existing functionality preserved

## References

- [Bash Startup Files](https://www.gnu.org/software/bash/manual/html_node/Bash-Startup-Files.html)
- [Zsh Files](http://zsh.sourceforge.net/Intro/intro_3.html)
- [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)
