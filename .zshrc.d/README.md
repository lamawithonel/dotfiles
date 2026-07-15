# .zshrc.d

This directory contains modular Zsh configuration files.  They are
sourced in alphabetical order, but not directly by `.zshrc`: the
last step of the shared `.config/shell/rc.d/` chain,
`.config/shell/rc.d/90-local.sh`, sources every `*.sh` file here
(via `find ... -maxdepth 1 -name "*.sh" -type f | sort`) after
`.zshrc` has already sourced the rest of `rc.d/`.

Files in this directory should be named with a `.sh` extension and
will be sourced in alphabetical order.

Example:
- `10-aliases.sh` - Additional aliases
- `20-functions.sh` - Custom functions
- `30-completions.sh` - Custom completions
