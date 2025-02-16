-- This is a ~/.config/nvim/init.lua file.

local opts = vim.o

opts.ruler  = true
opts.number = true
opts.colorcolumn = '72,80,100,120,140'

-- Column highlighting test pattern
--       10........20        30........40        50........60          72......80        90........100       110.......120       130...... 140
--       |         |         |         |         |         |           |       |         |         |         |         |         |         |

opts.shada = "!,%,h,'1000,s50"
--            | | | |     |
--            | | | |     +--- (KiB) maximum size of each saved item
--            | | | +--------- (int) Max number of previously edited files for which marks are remembered
--            | | +----------- (bool) Don't save/restore 'hlsearch' patterns
--            | +------------- (bool) Save and restore buffers
--            +--------------- (bool) Save and restore global variables that start with a capital leter
--                                    and container only capital letters and underscores.  For example,
--                                    it will save 'FOO' and 'FOO_BAR', but not '_FOO' or 'FooBar'.
--
-- Other options are available, but most are controled with `history`.
-- See: `:help 'shada'` (with quotes) for more information.
--

opts.history = 1000
opts.mouse = 'a'

opts.tabstop    = 4
opts.shiftwidth = 4
opts.expandtab  = true

-- Per file type indentation
vim.filetype.javascript = { sw = 2, sts = 2, et = true }
vim.filetype.typescript = { sw = 2, sts = 2, et = true }
vim.filetype.python     = { sw = 4, sts = 4, et = true }
vim.filetype.sh         = { sw = 4, sts = 4, et = false }
vim.filetype.ruby       = { sw = 2, sts = 2, et = true }
vim.filetype.vim        = { sw = 4, sts = 4, et = true }

require('config.lazy')
