return {
    {
        "neoclide/coc.nvim",
        branch = "release",
        event = "BufEnter",
        config = function()
            vim.g.coc_global_extensions = {
                '@yaegassy/coc-ansible',
                'coc-copilot',
                'coc-diagnostic',
                'coc-docker',
                'coc-eslint',
                'coc-git',
                'coc-go',
                'coc-golines',
                'coc-json',
                'coc-lua',
                'coc-markdownlint',
                'coc-markdown-preview-enhanced',
                'coc-pairs',
                'coc-powershell',
                'coc-prettier',
                'coc-pyright',
                'coc-rls',
                'coc-rust-analyzer',
                'coc-sh',
                'coc-solargraph',
                'coc-spell-checker',
                'coc-sql',
                'coc-swagger',
                'coc-toml',
                'coc-tsserver',
                'coc-vimlsp',
                'coc-xml',
                'coc-yaml',
            }
            function vim.fn.check_back_space()
                local col = vim.fn.col('.') - 1
                return col == 0 or vim.fn.getline('.')[col]:match('%s')
            end

            vim.api.nvim_set_keymap(
                'i',
                '<S-Tab>',
                'pumvisible() ? "\\<C-n>" : v:lua.vim.fn.check_back_space() ? "\\<Tab>" : "\\<C-p>"',
                { noremap = true, expr = true, silent = true }
            )
        end,
    }
}
