# Ghostty + Neovim Keybinding Philosophy

This configuration implements a **hand-separation design** for Ghostty terminal emulator and Neovim, optimized for the ZSA Moonlander keyboard.

## Core Principles

1. **Hand Separation**: Modifier on one hand, action keys on the other
2. **Left Hand (ESDF, W, R, A, G) = NAVIGATION** (`Alt+W`/`Alt+R`
   split-cycling and `Alt+A`/`Alt+G` tab-cycling are bound;
   `Alt+Shift+A`/`Alt+Shift+G` move tabs; numbered tab-jump bindings
   are not -- see "Not currently bound" below)
3. **Right Hand (IJKL, T) = CREATION / ADJUSTMENT**
4. **Modifier Tiers**: Different modifier combinations for Ghostty vs Neovim to prevent conflicts
5. **Preserved Sequences**: 
   - Terminal control: Ctrl+C (SIGINT), Ctrl+Z (SIGTSTP), Ctrl+D (EOF)
   - Shell features: Ctrl+R (reverse search)
   - Text editing: Ctrl+F (find), Ctrl+G (find next) - reserved for future use
6. **Non-Character Keys**: 
   - Navigation keys (arrows, Home/End) without modifiers are passed to applications
   - Bare PageUp/PageDown are passed to applications the same as arrows/Home/End, but via Ghostty's built-in default rather than an explicit `config` entry
   - Use modifier combinations (Shift, Ctrl, Alt) for terminal emulator functions

## Keyboard Layout

```
ZSA Moonlander:
- Left thumb:  Ctrl, Del, Space
- Right thumb: Alt, Enter, Space
- Layer 2:     Alt+number → F1-F10 (blocks Alt+n for tabs)
```

## Visual Layout Guide

```
SPLIT NAVIGATION          SPLIT CREATION           SPLIT RESIZE
Alt + ESDF                Ctrl + IJKL              Ctrl+Shift + IJKL
                          (also Super + IJKL)      (also Super+Shift + IJKL)

     [E]                       [I]                      [I]
 [S] [D] [F]               [J] [K] [L]              [J] [K] [L]

TAB NAVIGATION
Alt+A           Previous tab
Alt+G           Next tab
Shift+Left      Previous tab
Shift+Right     Next tab
Note: Ctrl+R reserved for shell history search
```

## Ghostty Keybindings

### Split Management

| Operation | Keys | Description |
|-----------|------|--------------|
| **Navigation** | | |
| Go up | `Alt+E` | Move to split above |
| Go left | `Alt+S` | Move to split on left |
| Go down | `Alt+D` | Move to split below |
| Go right | `Alt+F` | Move to split on right |
| **Cycling** | | |
| Previous split | `Alt+W` | Cycle to previous split |
| Next split | `Alt+R` | Cycle to next split |
| **Creation** | | |
| Create up | `Ctrl+I` / `Super+I` | New split above |
| Create left | `Ctrl+J` / `Super+J` | New split on left |
| Create down | `Ctrl+K` / `Super+K` | New split below |
| Create right | `Ctrl+L` / `Super+L` | New split on right |
| Create auto | `Ctrl+Shift+Enter` / `Super+Shift+Enter` | New split (auto direction) |
| **Resize** | | |
| Resize up | `Ctrl+Shift+I` / `Super+Shift+I` | Grow upward |
| Resize left | `Ctrl+Shift+J` / `Super+Shift+J` | Grow leftward |
| Resize down | `Ctrl+Shift+K` / `Super+Shift+K` | Grow downward |
| Resize right | `Ctrl+Shift+L` / `Super+Shift+L` | Grow rightward |
| **Management** | | |
| Equalize | `Ctrl+Shift+=` / `Super+Shift+=` | Make all splits equal |
| Zoom toggle | `Ctrl+Shift+\` / `Super+Shift+\` | Maximize/restore split |

**`Alt+W`/`Alt+R` split-cycling** (`goto_split:previous`/`goto_split:next`;
see the [keybind action reference][ghostty-keybind-ref]) is bound
above with one accepted tradeoff: this repo's `.zshrc` runs
`bindkey -e` (emacs keymap), where stock zsh binds `Alt+W` (`^[w`)
to `copy-region-as-kill` by default, and Ghostty's binding
intercepts the keypress at the terminal-emulator layer before zsh
ever sees it -- so `copy-region-as-kill` is not reachable via
`Alt+W` in this configuration.  `Alt+R` has no such conflict: the
stock zsh emacs keymap does not bind `^[r`/Meta-`r`, and Neovim has
no default, plugin-free mapping for `Alt+w`/`Alt+r` in normal or
insert mode.  This repo's own `Alt+Shift+W`/`Alt+Shift+R`
window-cycling bindings in `ghostty-compat.lua` use a different
modifier tier and are unrelated.

Split move/swap (`move_split`) is unrelated to this decision and
remains a commented-out placeholder in the config, since Ghostty
does not implement that action yet.

### Tab Management

| Operation | Keys | Description |
|-----------|------|--------------|
| Previous tab | `Alt+A` or `Shift+Left` | Previous tab |
| Next tab | `Alt+G` or `Shift+Right` | Next tab |
| Move tab left | `Alt+Shift+A` | Move current tab left |
| Move tab right | `Alt+Shift+G` | Move current tab right |
| New tab | `Ctrl+T` / `Super+T` | Create new tab |
| Close surface | `Ctrl+Shift+W` / `Super+Shift+W` | Close current split/tab |
| Close window | `Ctrl+Shift+Q` / `Super+Shift+Q` | Quit Ghostty |

**Note:** `Ctrl+R` is intentionally not bound to preserve shell history search (reverse-i-search).

**Not currently bound:** `Ctrl+Shift+1`-`9` (jump to tab N) has no
keybind in the current config; do not assume one exists.  "New tab"
is bound to plain `Ctrl+T` / `Super+T` -- there is no `Ctrl+Shift+T`
binding.

### Other Bindings

| Category | Keys | Description |
|----------|------|--------------|
| **Clipboard** | | |
| Copy | `Ctrl+Shift+C` / `Super+Shift+C` | Copy selection |
| Paste | `Ctrl+Shift+V` / `Super+Shift+V` | Paste from clipboard |
| Paste selection | `Ctrl+Shift+Insert` / `Super+Shift+Insert` | Paste from selection |
| **Scrolling** | | |
| Page up/down | `Shift+PageUp/PageDown` | Scroll by page |
| Line up/down | `Shift+Up/Down` | Scroll by line |
| Top/bottom | `Shift+Home/End` | Scroll to top/bottom |
| Jump prompt | `Ctrl+Shift+Up/Down` / `Super+Shift+Up/Down` | Jump between prompts |
| **Font** | | |
| Increase | `Ctrl+=` / `Super+=` | Larger font |
| Decrease | `Ctrl+-` / `Super+-` | Smaller font |
| Reset | `Ctrl+0` / `Super+0` | Reset to default |
| **Window** | | |
| New window | `Ctrl+Shift+N` / `Super+Shift+N` | New Ghostty window |
| Fullscreen | `F11` | Toggle fullscreen |
| **UI** | | |
| Open config | `Ctrl+Shift+P` / `Super+Shift+P` or `Ctrl+Shift+,` / `Super+Shift+,` | Open the config file |
| Inspector toggle | `Ctrl+Shift+A` / `Super+Shift+A` | Toggle the Ghostty inspector |

**Not currently bound:** a global quick terminal binding
(`` Ctrl+` ``) has no active keybind -- it is present in the config
but commented out, with a `TODO` noting it will be re-enabled once
global shortcuts are less disruptive under KDE.  `Ctrl+Shift+P` /
`Super+Shift+P` opens the config file and `Ctrl+Shift+A` /
`Super+Shift+A` toggles the inspector; neither opens a command
palette or a tab overview.

**Reserved Keys (Not Bound):**
- `Ctrl+R` - Reserved for shell history search (reverse-i-search)
- `Ctrl+F` - Commented out in the config as "unimplemented in Ghostty" (scrollback search)
- `Ctrl+G` - Commented out in the config as "unimplemented in Ghostty" (scrollback search)

**Built-in Defaults (Not Explicit `config` Entries):**
- `PageUp`, `PageDown` - No `keybind` line exists for these in `config`; the
  behavior comes from Ghostty's own defaults, not an explicit binding here
  - Applications like vim, less, and man pages can still handle these keys directly
  - Use `Shift+PageUp`/`Shift+PageDown` for Ghostty scrollback instead

### macOS Compatibility

A handful of `Super`-modified keys are remapped to send the raw
control codes that terminal applications (shell line editing, `less`,
etc.) expect from `Ctrl`, since macOS conventionally reserves `Ctrl`
combinations for the terminal emulator and uses `Cmd` (`Super`) for
application-level shortcuts:

| Key | Sends | Equivalent to |
|-----|-------|---------------|
| `Super+C` | `\x03` | `Ctrl+C` (SIGINT) |
| `Super+Z` | `\x1a` | `Ctrl+Z` (SIGTSTP) |
| `Super+V` | `\x16` | `Ctrl+V` (literal-next) |
| `Super+R` | `\x12` | `Ctrl+R` (reverse history search) |

## Neovim Keybindings (within Ghostty)

Neovim uses **one tier higher modifiers** than Ghostty to prevent conflicts:

### Window Management

| Operation | Keys | Description |
|-----------|------|--------------|
| **Navigation** | | |
| Go up | `Alt+Shift+E` | Move to window above |
| Go left | `Alt+Shift+S` | Move to window on left |
| Go down | `Alt+Shift+D` | Move to window below |
| Go right | `Alt+Shift+F` | Move to window on right |
| Previous window | `Alt+Shift+W` | Cycle to previous window |
| Next window | `Alt+Shift+R` | Cycle to next window |
| **Creation** | | |
| Split up | `Ctrl+W, I` | Split horizontally (above) |
| Split left | `Ctrl+W, J` | Split vertically (left) |
| Split down | `Ctrl+W, K` | Split horizontally (below) |
| Split right | `Ctrl+W, L` | Split vertically (right) |
| **Resize** | | |
| Grow height | `Alt+Shift+I` | Increase window height |
| Shrink width | `Alt+Shift+J` | Decrease window width |
| Shrink height | `Alt+Shift+K` | Decrease window height |
| Grow width | `Alt+Shift+L` | Increase window width |
| **Move/Swap** | | |
| Move to top | `Ctrl+Alt+Shift+E` | Move window to top |
| Move to left | `Ctrl+Alt+Shift+S` | Move window to left |
| Move to bottom | `Ctrl+Alt+Shift+D` | Move window to bottom |
| Move to right | `Ctrl+Alt+Shift+F` | Move window to right |
| **Management** | | |
| Equalize | `Ctrl+W, =` | Equalize window sizes |
| Zoom | `Ctrl+W, z` | Zoom window (new tab) |
| Rotate down | `Ctrl+W, r` | Rotate windows down/right |
| Rotate up | `Ctrl+W, R` | Rotate windows up/left |

## Design Rationale

### Why ESDF for Navigation?

- **Home row positioning**: Keeps fingers on home row
- **Better hand separation**: Clear left-hand navigation zone
- **More accessible modifiers**: Alt on right thumb + ESDF on left hand

### Why IJKL for Creation/Resize?

- **Mirrors ESDF layout**: Same spatial relationship (up/left/down/right)
- **Right hand only**: Complements left-hand navigation
- **Natural for adjustments**: Right hand for "building" and "tweaking"

### Why Different Modifier Tiers?

| Level | Ghostty | Neovim | Purpose |
|-------|---------|--------|---------|
| Base | `Alt+ESDF` | - | Ghostty split navigation |
| +Shift | - | `Alt+Shift+ESDF` | Neovim window navigation |
| Ctrl | `Ctrl+IJKL` (also `Super+IJKL`) | - | Ghostty split creation |
| Ctrl+Shift | `Ctrl+Shift+IJKL` (also `Super+Shift+IJKL`) | - | Ghostty split resize |
| Alt+Shift | - | `Alt+Shift+IJKL` | Neovim window resize |
| Triple | `Alt+Shift+ESDF` (commented-out `move_split` placeholder in config -- **collides with the Neovim `+Shift` row above**; do not enable as-is) | `Ctrl+Alt+Shift+ESDF` (live window move/swap) | Neovim: window move/swap (live). Ghostty: commented-out placeholder collides with the row above; if `move_split` is ever implemented, use `Ctrl+Alt+ESDF` (no Shift) instead -- free in both Ghostty's config and Neovim's `ghostty-compat.lua` bindings |

This tiered approach allows both tools to coexist without conflicts while maintaining consistent mental models.

## ZSA Moonlander Integration

The configuration assumes:
- **Left thumb cluster**: Ctrl (primary), Del, Space
- **Right thumb cluster**: Alt (primary), Enter, Space
- **Layer 2**: Alt+number keys produce F1-F10

This layout optimizes for:
1. **Comfort**: Most common operations use single-hand combos
2. **Speed**: Thumb modifiers + finger keys = fast navigation
3. **Learning**: Consistent patterns across both tools
4. **Ergonomics**: Minimal hand movement and stretching

## Tips

1. **Start with basics**: Learn Ghostty split navigation (`Alt+ESDF`) first
2. **Build muscle memory**: Practice tab switching (`Alt+A`/`Alt+G`)
3. **Layer up**: Add Neovim navigation once Ghostty feels natural
4. **Use visual cues**: Remember the ASCII art above for spatial layouts
5. **Customize as needed**: These are starting points, adjust to your workflow

## Files

- **Ghostty config**: `~/.config/ghostty/config`
- **Neovim config**: `~/.config/nvim/lua/config/ghostty-compat.lua`
- **Neovim init**: `~/.config/nvim/init.lua` (loads ghostty-compat)

## Future Enhancements

- **Ghostty split moving**: The config has a commented-out, unimplemented
  `move_split` placeholder bound to `Alt+Shift+ESDF`. **This collides with the
  live Neovim window-navigation binding** (see the `+Shift` row in [Why
  Different Modifier Tiers?](#why-different-modifier-tiers)) and violates the
  modifier-separation principle -- do not uncomment it as-is. If `move_split`
  is ever implemented, use `Ctrl+Alt+ESDF` (no Shift) instead -- unused by
  both Ghostty's own config and Neovim's `ghostty-compat.lua` bindings
- **Context-aware bindings**: Different bindings for different terminal modes

[ghostty-keybind-ref]: https://ghostty.org/docs/config/keybind
