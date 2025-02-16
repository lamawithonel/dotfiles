return {
    {
        'vim-airline/vim-airline',
        dependencies = {
            'vim-airline/vim-airline-themes',
            'ryanoasis/vim-devicons',
        },
        config = function()
            vim.g.airline_theme = 'base16_solarized_dark'
            vim.g.airline_powerline_fonts = 1

            if vim.fn.exists('g:airline_symbols') == 0 then
                vim.g.airline_symbols = {}
            end

            -- unicode symbols
            vim.g.airline_left_sep = '»'
            vim.g.airline_left_sep = '▶'
            vim.g.airline_right_sep = '«'
            vim.g.airline_right_sep = '◀'
            vim.g.airline_symbols.linenr = '␊'
            vim.g.airline_symbols.linenr = '␤'
            vim.g.airline_symbols.linenr = '¶'
            vim.g.airline_symbols.branch = '⎇'
            vim.g.airline_symbols.paste = 'ρ'
            vim.g.airline_symbols.paste = 'Þ'
            vim.g.airline_symbols.paste = '∥'
            vim.g.airline_symbols.whitespace = 'Ξ'

            -- airline symbols
            vim.g.airline_left_sep = ''
            vim.g.airline_left_alt_sep = ''
            vim.g.airline_right_sep = ''
            vim.g.airline_right_alt_sep = ''
            vim.g.airline_symbols.branch = ''
            vim.g.airline_symbols.readonly = ''
            vim.g.airline_symbols.linenr = ''
        end,
    }
}
