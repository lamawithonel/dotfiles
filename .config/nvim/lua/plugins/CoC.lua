return {
    {
        "neoclide/coc.nvim",
        branch = "release",
        event = "BufEnter",
        config = function()
            vim.g.coc_global_extensions = {
                'coc-eslint',
                'coc-go',
                'coc-json',
                'coc-lua',
                'coc-markdownlint',
                'coc-pairs',
                'coc-powershell',
                'coc-prettier',
                'coc-pyright',
                'coc-rust-analyzer',
                'coc-sh',
                'coc-solargraph',
                'coc-swagger',
                'coc-toml',
                'coc-tsserver',
                'coc-vimlsp',
                'coc-yaml'
            }
            --[[
            " CoC autocompletion
            inoremap <silent><expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"
            " vim.api.nvim_set_keymap('i', '<S-Tab>', '<C-p>', {silent= true, expr = true})
            inoremap <expr> <C-j> pumvisible() ? "\<C-n>" : "\<C-j>"
            " vim.api.nvim_set_keymap('i', '<C-j>', '<C-n>', {expr = true})"
            --]]
            vim.api.nvim_set_keymap('i', '<S-Tab>', '<C-p>', {silent= true, expr = true})
            vim.api.nvim_set_keymap('i', '<C-j>', '<C-n>', {expr = true})
        end,
    }
}
