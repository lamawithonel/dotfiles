-- Ghostty-Compatible Keybindings for Neovim
-- ============================================================================
-- This configuration complements Ghostty's keybindings with Neovim window
-- management using a consistent hand-separation design philosophy.
--
-- Ghostty Config Keybindings:
--   Alt+ESDF:         Navigate Ghostty splits
--   Ctrl+IJKL:        Create new Ghostty splits
--   Ctrl+Shift+IJKL:  Resize Ghostty splits
--   Alt+A/G:          Navigate Ghostty tabs
--   Alt+Shift+A/G:    Move Ghostty tabs
--
-- Neovim Window Keybindings (designed to NOT conflict):
--   Alt+Shift+ESDF:   Navigate Neovim windows (one modifier tier above Ghostty)
--   Ctrl+W + IJKL:    Create Neovim windows (uses Vim's standard prefix)
--   Alt+Shift+IJKL:   Resize Neovim windows (different keys from navigation)
--   Ctrl+Alt+Shift+ESDF: Move/swap Neovim windows
--
-- This hierarchy ensures no conflicts between Ghostty and Neovim operations.
-- ============================================================================

-- Window Navigation - Alt+Shift+ESDF
-- One modifier tier above Ghostty's Alt+ESDF split navigation
-- This prevents conflicts while maintaining the same directional keys
vim.keymap.set("n", "<M-S-e>", "<C-w>k", { desc = "Go to upper window", noremap = true, silent = true })
vim.keymap.set("n", "<M-S-s>", "<C-w>h", { desc = "Go to left window", noremap = true, silent = true })
vim.keymap.set("n", "<M-S-d>", "<C-w>j", { desc = "Go to lower window", noremap = true, silent = true })
vim.keymap.set("n", "<M-S-f>", "<C-w>l", { desc = "Go to right window", noremap = true, silent = true })

-- Window Navigation - Previous/Next (Alt+Shift+W/R)
-- Uses W/R to mirror Ghostty's Alt+W/R for split cycling
vim.keymap.set("n", "<M-S-w>", "<C-w>W", { desc = "Go to previous window", noremap = true, silent = true })
vim.keymap.set("n", "<M-S-r>", "<C-w>w", { desc = "Go to next window", noremap = true, silent = true })

-- Window Creation - Ctrl+W prefix + IJKL
-- Uses Vim's standard window command prefix (Ctrl+W) + IJKL directional keys
-- Does NOT conflict with Ghostty's Ctrl+IJKL (which creates Ghostty splits)
-- because Vim captures the full Ctrl+W+IJKL sequence before Ghostty sees it
vim.keymap.set("n", "<C-w>i", "<C-w>s", { desc = "Split window below", noremap = true, silent = true })
vim.keymap.set("n", "<C-w>j", "<C-w>v<C-w>h", { desc = "Split window left", noremap = true, silent = true })
vim.keymap.set("n", "<C-w>k", "<C-w>s<C-w>j", { desc = "Split window below", noremap = true, silent = true })
vim.keymap.set("n", "<C-w>l", "<C-w>v", { desc = "Split window right", noremap = true, silent = true })

-- Window Resize - Alt+Shift+IJKL
-- Uses IJKL (right hand) with same modifier as window navigation (Alt+Shift)
-- Does NOT conflict with Ghostty's Ctrl+Shift+IJKL (Ghostty split resize)
vim.keymap.set("n", "<M-S-i>", "<cmd>resize +2<cr>", { desc = "Increase window height", noremap = true, silent = true })
vim.keymap.set(
  "n",
  "<M-S-j>",
  "<cmd>vertical resize -2<cr>",
  { desc = "Decrease window width", noremap = true, silent = true }
)
vim.keymap.set("n", "<M-S-k>", "<cmd>resize -2<cr>", { desc = "Decrease window height", noremap = true, silent = true })
vim.keymap.set(
  "n",
  "<M-S-l>",
  "<cmd>vertical resize +2<cr>",
  { desc = "Increase window width", noremap = true, silent = true }
)

-- Window Move/Swap - Ctrl+Alt+Shift+ESDF
-- Three-modifier combination ensures no conflicts with any Ghostty bindings
-- Ghostty reserves Ctrl+Alt+ESDF for future split move (currently unimplemented)
vim.keymap.set("n", "<C-M-S-e>", "<C-w>K", { desc = "Move window to top", noremap = true, silent = true })
vim.keymap.set("n", "<C-M-S-s>", "<C-w>H", { desc = "Move window to left", noremap = true, silent = true })
vim.keymap.set("n", "<C-M-S-d>", "<C-w>J", { desc = "Move window to bottom", noremap = true, silent = true })
vim.keymap.set("n", "<C-M-S-f>", "<C-w>L", { desc = "Move window to right", noremap = true, silent = true })

-- Window Rotation - Keep standard Vim bindings
-- Ctrl+W, r = rotate windows downwards/rightwards
-- Ctrl+W, R = rotate windows upwards/leftwards
-- These are already available with <C-w>r and <C-w>R

-- Window Management
vim.keymap.set("n", "<C-w>=", "<C-w>=", { desc = "Equalize window sizes", noremap = true, silent = true })
vim.keymap.set(
  "n",
  "<C-w>z",
  "<cmd>tab split<cr>",
  { desc = "Zoom window (open in new tab)", noremap = true, silent = true }
)

return {}
