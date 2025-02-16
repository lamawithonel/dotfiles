return {
    {
        'ntpeters/vim-better-whitespace',
        config = function()
            vim.g.show_spaces_that_precede_tabs = 1
            vim.g.strip_whitelines_at_eof = 1

            vim.g.strip_whitespace_on_save = 1
            vim.g.strip_whitespace_confirm = 1
        end,
    }
}
