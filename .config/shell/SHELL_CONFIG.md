# Shell Configuration Structure

This directory documents the shell startup files that live at the top of
the home directory (`.profile`, `.bash_profile`, `.bashrc`, `.zshenv`,
`.zprofile`, `.zshrc`) plus the shared snippets they source from
`.config/shell/`.  The design goals are:

1. **Separate login and interactive concerns** -- environment setup
   (XDG directories, `PATH`, language-tool env vars) happens once per
   login session, not on every interactive shell.
2. **Share one implementation across Bash and Zsh** -- both shells
   source the same `rc.d/*.sh` snippets for interactive setup, instead
   of maintaining parallel Bash- and Zsh-specific copies.
3. **Guard against duplicate sourcing** -- the `__PROFILE_SOURCED`
   variable ensures `.profile` only runs its setup once per session,
   however the shell was invoked.
4. **Follow the XDG Base Directory Specification** wherever practical.

## Entry points and source order

### Bash login shell

1. `.bash_profile` runs first (Bash's standard login-shell entry
   point).
2. It sources `.profile` if `__PROFILE_SOURCED` is not already set.
   `.profile`:
   - Sets a secure `umask`.
   - Defines the XDG base directories (`XDG_BIN_HOME`,
     `XDG_CACHE_HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`,
     `XDG_RUNTIME_DIR`, `XDG_STATE_HOME`), creating them if missing.
   - Exports language/tool environment variables that must exist
     before any tool runs (`CARGO_HOME`, `DENO_INSTALL`,
     `DOTNET_CLI_HOME`, `FNM_DIR`, `GOPATH`, `KUBECONFIG`,
     `LUAROCKS_CONFIG`, `LUAROCKS_TREE`, `LUAVER_DIR`, `PYENV_ROOT`,
     `RUSTUP_HOME`, `SDKMAN_DIR`, `VAGRANT_HOME`).
   - Sources `~/.profile.d/*.sh` if that directory exists.
   - Sources `.config/shell/path.sh` (the canonical
     `_ensure_path_contains()` implementation) and calls it to add
     `${XDG_DATA_HOME}/cargo/bin`, `${XDG_BIN_HOME}`, and `${HOME}/bin`
     to `PATH`.
   - Sources `~/.profile.local.d/*.sh` and `~/.profile.local` if
     present.
   - Sets `__PROFILE_SOURCED=1` and exports it as the guard variable.
3. Back in `.bash_profile`: sets up Bash-specific XDG directories
   (`BASH_CACHE_HOME`, `BASH_CONFIG_HOME`, `BASH_DATA_HOME`,
   `BASH_STATE_HOME`), sources
   `${BASH_CONFIG_HOME}/profile.d/*.sh`, and (on Apple Silicon
   Homebrew only, i.e. `/opt/homebrew`; Intel Homebrew's default
   `/usr/local` prefix is not checked) sources
   `/opt/homebrew/etc/profile.d/*.sh`.
4. If the shell is interactive and `.bashrc` is not already in the
   call stack, `.bash_profile` sources `.bashrc`.

### Bash interactive shell (`.bashrc`)

`.bashrc` returns immediately if the shell is not Bash or not
interactive.  If `__PROFILE_SOURCED` is unset (a non-login
interactive shell), it sources `.bash_profile` first to run the login
chain above.  It then sources every `*.sh` file directly under
`${XDG_CONFIG_HOME}/shell/rc.d/` in the shell's own glob order.

### Zsh login shell

1. `.zshenv` runs for **every** Zsh invocation (login, interactive,
   script, or command substitution).  It only exports the base XDG
   variables (defaulting them if unset) and the Zsh-specific
   `ZSH_CACHE_HOME` / `ZSH_CONFIG_HOME` / `ZSH_DATA_HOME` /
   `ZSH_STATE_HOME` variables.  It deliberately does **not** create
   any directories, since it also runs for non-interactive Zsh
   processes.
2. `.zprofile` runs for Zsh login shells.  It sources `.profile`
   (via `emulate sh -c`) if `__PROFILE_SOURCED` is unset, validates
   that the base XDG variables are set, creates the Zsh-specific XDG
   directories, sources `${ZSH_CONFIG_HOME}/profile.d/*.sh`, and (on
   Apple Silicon Homebrew only, i.e. `/opt/homebrew`; Intel Homebrew's
   default `/usr/local` prefix is not checked) sources
   `/opt/homebrew/etc/profile.d/*.sh`.

### Zsh interactive shell (`.zshrc`)

`.zshrc` returns immediately if the shell is not interactive.  If
`__PROFILE_SOURCED` is unset, it sources `.zprofile` first.  It then
sets Zsh key bindings (Emacs mode, Delete/Home/End,
Ctrl+Left/Right word movement, Ctrl+R/Ctrl+S history search), and
finally sources every `*.sh` file directly under
`${XDG_CONFIG_HOME}/shell/rc.d/` in the shell's own glob order --
the same directory and the same order as `.bashrc` uses.

## `.config/shell/rc.d/` -- shared interactive configuration

Both `.bashrc` and `.zshrc` source every `*.sh` file in this
directory using a plain glob (`"${XDG_CONFIG_HOME}/shell/rc.d/"*.sh`),
so the load order is whatever order the shell's own glob expansion
produces for these filenames.  In practice that is the ascending
numeric-looking order below, which is the same for both Bash
and Zsh:

| File | Purpose |
| --- | --- |
| `05-regex-patterns.sh` | Exports POSIX ERE fragments (`REGEX_IPv4_ADDRESS`, `REGEX_IPv4_SUBNET`, `REGEX_HOSTNAME_LABEL`, `REGEX_FQDN`) for use in scripts. |
| `10-shell-settings.sh` | History size/file settings and interactive shell options for Bash (`shopt`) and Zsh (`setopt`), including history file locations under `BASH_CACHE_HOME`/`ZSH_CACHE_HOME`. |
| `20-path.sh` | Re-defines `_ensure_path_contains()` only if it is missing (covers shells that inherited the `__PROFILE_SOURCED` guard as an exported variable but never actually ran `.profile`), enables Zsh's built-in `PATH` deduplication (`typeset -U PATH path`), and, when `/opt/homebrew/bin/brew` is executable, adds `/opt/homebrew/bin` and `/opt/homebrew/sbin` to `PATH` -- the brew binary itself is checked rather than `/opt/homebrew/etc/paths`, which only the less-common `.pkg` installer creates and the standard curl-based installer used on virtually every fresh Apple Silicon Mac does not. Intel Homebrew's default `/usr/local` prefix is not checked. |
| `30-tools.sh` | Tool integrations: eagerly runs `mise activate`, `fnox activate`, and `pitchfork activate`.  All three are eager for the same reason: each activation installs prompt and/or directory-change hooks that real usage depends on, and a lazy wrapper would silently skip those hooks in any shell where the tool is never invoked directly.  This eagerness has a measured warm-shell startup-time cost; run `bin/bench-shell-startup` for current numbers.  Completions for fnox/pitchfork live in `70-completions.sh`, not here. |
| `35-gpg-ssh.sh` | Sets `GPG_TTY` and (on non-macOS) `SSH_AUTH_SOCK` from `gpgconf`, when `gpg-agent` is available. |
| `40-terminal-colors.sh` | Detects terminal color support via `tput colors` and evaluates `dircolors`/`gdircolors` (using `.config/coreutils/dir_colors` if readable) to set `LS_COLORS`.  When `tinty` is installed, also exports `BASE16_SHELL_PATH`, `TINTED_SHELL_ENABLE_BASE16_VARS`, and `TINTED_SHELL_ENABLE_BASE24_VARS` for tinted-shell/Tinty consumers. |
| `50-aliases.sh` | Common aliases: editor (`vi` -> `nvim`/`vim`), interactive-safety aliases (`rm -i`, `cp -i`, `mv -i`), `sdiff` width, `screen`, `gpg-kill-scdaemon`, `puppet-lint`, clipboard (`pbcopy`/`pbpaste` via `xsel`), and color-aware `grep`/`ls` family aliases. |
| `60-prompt.sh` | Initializes the Starship prompt via `eval "$(starship init bash)"` or `eval "$(starship init zsh)"`, if `starship` is installed. |
| `70-completions.sh` | Native completion frameworks plus lazy per-tool completions driven by the shared table in `.config/shell/completion-tools.conf` (see below).  Bash: loads `bash-completion` from the first available system location, then registers one lazy `complete -F` dispatcher stub per listed tool.  Zsh: materializes fpath-strategy completion files into `$ZSH_CACHE_HOME`, adds `$ZSH_CACHE_HOME` to `fpath`, runs `compinit` (cached `zcompdump` only when the cache directory and dump pass ownership/mode checks), then registers one lazy `compdef` dispatcher stub per compdef-strategy tool.  Also hand-writes the `aws` (via `aws_completer`), `pkl` (Zsh), and `fzf` (eager shell integration) special cases. |
| `90-local.sh` | Sources shell-specific local extension points, in order: `~/.bashrc.d/*.sh` or `~/.zshrc.d/*.sh` (Zsh uses `find` instead of a glob so a missing directory or empty match set is not an error); `~/.bashrc.local` or `~/.zshrc.local`; then `~/.bashrc.local.d/*.sh` or `~/.zshrc.local.d/*.sh`. |

All `rc.d/` files use the two-digit `NN-name.sh` scheme, leaving gaps
between the existing numbers for future insertions without a
renumbering pass.  `05-regex-patterns.sh` loads first because it only
exports POSIX ERE data with no dependency on anything else in the
chain.  `35-gpg-ssh.sh` sits between tool activation (`30-tools.sh`)
and terminal setup (`40-terminal-colors.sh`) since GPG/SSH agent
configuration is tool-adjacent setup; nothing later in the chain
currently reads `GPG_TTY` or `SSH_AUTH_SOCK`, so its exact position
is not load-bearing.

Note that `.zshrc.d/*.sh` (and `.bashrc.d/*.sh`) are **not** sourced
directly by `.zshrc`/`.bashrc`.  They are sourced indirectly, as the
last step of the `rc.d` chain, by `.config/shell/rc.d/90-local.sh`.

### Tinty and tinted-shell

Tinty (see `.config/tinted-theming/tinty/config.toml`) owns applying
the terminal and editor theme: it writes Ghostty's theme file directly
and drives `tinted-nvim` and `tinted-delta` through its own hooks, none
of which read shell environment variables.  `40-terminal-colors.sh`
exports `BASE16_SHELL_PATH`, `TINTED_SHELL_ENABLE_BASE16_VARS`, and
`TINTED_SHELL_ENABLE_BASE24_VARS` (guarded by `command -v tinty`) as
cheap, side-effect-free variables for any tool that expects them, but
it deliberately does **not** source tinted-shell's `profile_helper.sh`
on every shell startup, and does not duplicate its base16/base24
palette into shell associative arrays.  No consumer in this tree reads
`profile_helper.sh`'s exported `base16-*`/`chbg` aliases or otherwise
requires it to run at startup; if a future consumer needs them, restore
the sourcing then, guarded the same way.  Tinty's own completion
(`tinty generate-completion zsh`, Zsh-only) is handled by the lazy
completion mechanism (see `completion-tools.conf` below), not here.

## `.config/shell/path.sh`

The single canonical implementation of `_ensure_path_contains()`, a
POSIX-compatible function for adding a directory to `PATH`:

- Removes every existing occurrence of the directory first, so the
  result never contains duplicates.
- Adds the directory at the front of `PATH` by default, or at the end
  when called as `_ensure_path_contains DIR after`.
- Silently drops the directory (instead of adding it) if it does not
  exist, so stale entries never make it into `PATH`.

This file is sourced once by `.profile`; `rc.d/20-path.sh` only
re-sources it defensively if the function is not already defined in
the current shell.

## `.config/shell/completion-tools.conf`

A pure data table (never sourced for side effects) that drives the
lazy per-tool completion loading in `rc.d/70-completions.sh`.  One
line per tool:

```text
name|template|shells|zsh-strategy
```

`template` is the command that prints the tool's completion script
(the literal word `SHELL` is substituted with `bash` or `zsh`),
`shells` says which shells the row applies to, and `zsh-strategy`
picks one of the two Zsh loading paths.  **Adding a tool means adding
one line here** -- both consumers pick it up automatically, and a
`command -v` guard keeps rows for uninstalled tools inert.

How the loading works, per shell:

- **Bash (one strategy for every row):** `70-completions.sh` registers
  a shared dispatcher function via `complete -F` for each listed
  tool.  On the first completion attempt, the dispatcher deregisters
  itself, evals the tool's generated completion script (every listed
  tool's Bash script self-registers its real completer), and returns
  124 -- the programmable-completion retry protocol that makes
  readline re-run completion with the real completer.  Startup cost
  is one `complete -F` per tool; no generator runs until first use.
- **Zsh, `compdef` strategy:** for generators whose output is safe to
  eval directly and defines a real `_<name>` function (the clap,
  Cobra, and usage-cli families).  A shared
  dispatcher stub is registered via `compdef`; the first completion
  attempt evals the generator output, re-registers the real
  `_<name>` function, and runs it for the in-flight attempt.
- **Zsh, `fpath` strategy:** for generators whose output is a classic
  `#compdef` autoload file whose body runs top-level completion code
  (`just`, `doggo`, `gum`, `bat`) -- direct eval breaks these.  The
  file is written to `$ZSH_CACHE_HOME/_<name>` **before** `compinit`
  runs, regenerated only when the tool binary is newer than the
  cached file, and any regeneration invalidates the `zcompdump` so
  compinit rediscovers it.  Loading is then Zsh's native fpath
  autoload.  This path is gated on the same cache-directory safety
  check as the dump itself.

Special cases hand-written in `70-completions.sh` (not table rows):

- **`aws`**: completion comes from the separate `aws_completer`
  binary, registered via `complete -C` -- directly in Bash, through
  `bashcompinit` in Zsh.
- **`pkl` (Zsh side)**: `pkl shell-completion zsh` emits a bash-style
  script that runs its own bare `compinit` and registers through
  `bashcompinit`; a dedicated lazy stub strips its
  compinit/bashcompinit bootstrap lines and lets its `complete -F`
  registration go through the bridge.  (Its Bash side is a normal
  table row.)
- **`fzf`**: `fzf --bash` / `fzf --zsh` emit whole-shell integration
  (key bindings plus the `**` trigger completion), not a per-command
  completer, so they are eval'd eagerly at startup rather than
  deferred.

Coverage summary:

- **Free via native discovery (no rows needed):** `kubectl`, `rg`,
  `deno`, `rustup` (both shells); `node` and `npm` in Zsh only (their
  Bash sides are table rows).
- **Table rows:** starship, uv, gh, fnox, pitchfork, tinty (Zsh only),
  git-lfs, yq, hk, hwatch, tree-sitter, ast-grep, delta, openspec,
  just, doggo, gum, bat, node/npm/pkl (Bash only), plus inert
  placeholder rows for ruff and hugo (not currently installed).
- **Explicitly out of scope:** `dotnet` (only a low-level
  `complete <partial>` primitive; needs custom wrapper code) and
  `usage-cli` (unclear self-completion mechanism).
- **No completion support on this host:**
  `mqttv5-cli`, `helix-db`, `playwright-cli`, `specify` (spec-kit),
  `graphify` (graphifyy), and the `bat-extras` scripts (a collection
  of wrapper scripts, not a CLI with completion generation).

## Modular extension points

- `~/.bashrc.d/*.sh` / `~/.zshrc.d/*.sh` -- optional, shell-specific,
  sourced in sorted order by `rc.d/90-local.sh`.
- `~/.bashrc.local` / `~/.zshrc.local` -- optional, single
  machine-specific override file, not tracked by yadm.
- `~/.bashrc.local.d/*.sh` / `~/.zshrc.local.d/*.sh` -- optional,
  sourced last, also not tracked by yadm.
- `~/.profile.d/*.sh` and `~/.profile.local.d/*.sh` /
  `~/.profile.local` -- POSIX-shell equivalents sourced from
  `.profile` itself, so they apply to both Bash and Zsh login shells.

None of these directories are required to exist; every loop guards on
`[ -d ... ]` or `[ -r ... ]` before sourcing.

## Migration notes

- **`~/.bash_aliases`**: not sourced by anything in this
  configuration -- its contents live in `50-aliases.sh` instead.
  The file at `~/.bash_aliases` is untracked by yadm and is not
  removed automatically; delete it manually:
  `rm ~/.bash_aliases`.
- **Per-tool completions**: dynamic completions are loaded lazily
  and table-driven, per `.config/shell/completion-tools.conf` above:
  native discovery covers `kubectl`/`rg`/`deno`/`rustup` (plus
  `node`/`npm` in Zsh), the shared table covers every tool with a
  completion generator, and `aws`/`pkl`(Zsh)/`fzf` are
  hand-written special cases.  `pipx` and
  `register-python-argcomplete` have no table row (pipx is not
  installed via mise on this host); `ruff` and `hugo` keep inert
  placeholder rows until they are installed.
## Testing

```sh
# Syntax-check the POSIX and Bash entry points plus the shared rc.d
# scripts.
bash -n .profile
bash -n .bash_profile
bash -n .bashrc
bash -n .config/shell/path.sh
for f in .config/shell/rc.d/*.sh; do bash -n "$f"; done

# Syntax-check the Zsh entry points (if zsh is installed).
zsh -n .zshenv
zsh -n .zprofile
zsh -n .zshrc

# Inspect PATH ordering/duplicates (there is no startup-time PATH=
# print by design; do this on demand instead).
echo "$PATH" | tr ':' '\n'
```

See `bin/check-shell-config` for a fuller, automated set of checks
(syntax, isolated login/interactive probes, `PATH` invariants,
aliases, eager-activation smoke tests, and lazy-completion smoke
tests), and `bin/bench-shell-startup` for startup-time measurements.

## References

- [Bash Startup Files](https://www.gnu.org/software/bash/manual/html_node/Bash-Startup-Files.html)
- [Zsh Files](http://zsh.sourceforge.net/Intro/intro_3.html)
- [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)
