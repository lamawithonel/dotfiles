return {
  {
    'nvim-treesitter/nvim-treesitter',
    build = ':TSUpdate',
    config = function ()
      local configs = require('nvim-treesitter.configs')

      vim.g.python3_host_prog = vim.env.HOME .. '/.local/share/pyenv/versions/nvim/bin/python3'
      configs.setup({
        ensure_installed = 'all',
        ignore_install = {
          'blueprint',
          'earthfile',
          'fusion',
          'jsonc',
          't32',
        },
        sync_install = false,
        highlight = { enable = true },
        indent = { enable = false },
      })
    end
  }
}
