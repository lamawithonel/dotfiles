# Ghostty + Neovim Keybinding Philosophy

This configuration implements a **hand-separation design** for Ghostty terminal emulator and Neovim, optimized for the ZSA Moonlander keyboard.

## Core Principles

1. **Hand Separation**: Modifier on one hand, action keys on the other
2. **Left Hand (ESDF, W, R, numbers) = NAVIGATION**
3. **Right Hand (IJKL, T) = CREATION / ADJUSTMENT**
4. **Modifier Tiers**: Different modifier combinations for Ghostty vs Neovim to prevent conflicts
5. **Preserved Sequences**: 
   - Terminal control: Ctrl+C (SIGINT), Ctrl+Z (SIGTSTP), Ctrl+D (EOF)
   - Shell features: Ctrl+R (reverse search)
   - Text editing: Ctrl+F (find), Ctrl+G (find next) - reserved for future use
6. **Non-Character Keys**: 
   - Navigation keys (arrows, PageUp/Down, Home/End) without modifiers are passed to applications
   - Exception: Bare PageUp/PageDown are ignored to prevent escape sequence artifacts
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
Alt + ESDF                Ctrl+Shift + IJKL        Ctrl + IJKL

     [E]                       [I]                      [I]
 [S] [D] [F]               [J] [K] [L]              [J] [K] [L]

TAB NAVIGATION
Ctrl+W          Previous tab
Shift+Left      Previous tab
Shift+Right     Next tab
Ctrl+Shift+1-9  Go to tab N
Note: Ctrl+R reserved for shell history search
```

## Ghostty Keybindings

### Split Management

| Operation | Keys | Description |
|-----------|------|-------------|
| **Navigation** | | |
| Go up | `Alt+E` | Move to split above |
| Go left | `Alt+S` | Move to split on left |
| Go down | `Alt+D` | Move to split below |
| Go right | `Alt+F` | Move to split on right |
| Previous split | `Alt+W` | Cycle to previous split |
| Next split | `Alt+R` | Cycle to next split |
| **Creation** | | |
| Create up | `Ctrl+Shift+I` | New split above |
| Create left | `Ctrl+Shift+J` | New split on left |
| Create down | `Ctrl+Shift+K` | New split below |
| Create right | `Ctrl+Shift+L` | New split on right |
| Create auto | `Ctrl+Shift+Enter` | New split (auto direction) |
| **Resize** | | |
| Resize up | `Ctrl+I` | Grow upward |
| Resize left | `Ctrl+J` | Grow leftward |
| Resize down | `Ctrl+K` | Grow downward |
| Resize right | `Ctrl+L` | Grow rightward |
| **Management** | | |
| Equalize | `Ctrl+Shift+=` | Make all splits equal |
| Zoom toggle | `Ctrl+Shift+\` | Maximize/restore split |

### Tab Management

| Operation | Keys | Description |
|-----------|------|-------------|
| Previous tab | `Ctrl+W` or `Shift+Left` | Previous tab |
| Next tab | `Shift+Right` | Next tab |
| Go to tab N | `Ctrl+Shift+1-9` | Jump to specific tab |
| New tab | `Ctrl+Shift+T` | Create new tab |
| Move tab left | `Alt+Shift+A` | Move current tab left |
| Move tab right | `Alt+Shift+G` | Move current tab right |
| Close surface | `Ctrl+Shift+W` | Close current split/tab |
| Close window | `Ctrl+Shift+Q` | Quit Ghostty |

**Note:** `Ctrl+R` is intentionally not bound to preserve shell history search (reverse-i-search).

### Other Bindings

| Category | Keys | Description |
|----------|------|-------------|
| **Clipboard** | | |
| Copy | `Ctrl+Shift+C` | Copy selection |
| Paste | `Ctrl+Shift+V` | Paste from clipboard |
| Paste selection | `Ctrl+Shift+Insert` | Paste from selection |
| **Scrolling** | | |
| Page up/down | `Shift+PageUp/PageDown` | Scroll by page |
| Line up/down | `Shift+Up/Down` | Scroll by line |
| Top/bottom | `Shift+Home/End` | Scroll to top/bottom |
| Jump prompt | `Ctrl+Shift+Up/Down` | Jump between prompts |
| **Font** | | |
| Increase | `Ctrl+=` | Larger font |
| Decrease | `Ctrl+-` | Smaller font |
| Reset | `Ctrl+0` | Reset to default |
| **Window** | | |
| New window | `Ctrl+Shift+N` | New Ghostty window |
| Fullscreen | `F11` | Toggle fullscreen |
| Quick terminal | ``Ctrl+` `` | Global quick terminal |
| **UI** | | |
| Command palette | `Ctrl+Shift+P` | Open config |
| Open config | `Ctrl+Shift+,` | Open config file |
| Tab overview | `Ctrl+Shift+A` | Toggle inspector |

**Reserved Keys (Not Bound):**
- `Ctrl+R` - Reserved for shell history search (reverse-i-search)
- `Ctrl+F`, `Ctrl+Shift+F` - Reserved for "find" functionality (when implemented)
- `Ctrl+G`, `Ctrl+Shift+G` - Reserved for "find next/previous" functionality (when implemented)

**Ignored Keys (Explicitly Bound to Prevent Escape Sequences):**
- `PageUp`, `PageDown` - Ignored to prevent generating tilde (~) characters
  - These keys without modifiers were causing escape sequences to be passed to the terminal
  - Applications like vim, less, and man pages can still handle these keys directly
  - Use `Shift+PageUp`/`Shift+PageDown` for Ghostty scrollback instead

## Neovim Keybindings (within Ghostty)

Neovim uses **one tier higher modifiers** than Ghostty to prevent conflicts:

### Window Management

| Operation | Keys | Description |
|-----------|------|-------------|
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
| Ctrl | `Ctrl+IJKL` | - | Ghostty split resize |
| Ctrl+Shift | `Ctrl+Shift+IJKL` | - | Ghostty split creation |
| Alt+Shift | - | `Alt+Shift+IJKL` | Neovim window resize |
| Triple | `Ctrl+Alt+ESDF` (reserved) | `Ctrl+Alt+Shift+ESDF` | Future/window move |

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
2. **Build muscle memory**: Practice tab switching (`Ctrl+W`/`Ctrl+R`)
3. **Layer up**: Add Neovim navigation once Ghostty feels natural
4. **Use visual cues**: Remember the ASCII art above for spatial layouts
5. **Customize as needed**: These are starting points, adjust to your workflow

## Files

- **Ghostty config**: `~/.config/ghostty/config`
- **Neovim config**: `~/.config/nvim/lua/config/ghostty-compat.lua`
- **Neovim init**: `~/.config/nvim/init.lua` (loads ghostty-compat)

## Future Enhancements

- **Ghostty split moving**: When supported, use `Ctrl+Alt+ESDF`
- **Additional workspaces**: Consider Alt+Shift+W/R for workspace switching
- **Context-aware bindings**: Different bindings for different terminal modes
