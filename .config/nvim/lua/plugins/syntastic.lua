return {
    {
        'vim-syntastic/syntastic',
        config = function()
            -- Specify linters for each filetype
            vim.g.syntastic_css_checkers = {'phpcs'}
            vim.g.syntastic_lua_checkers = {'luacheck'}
            vim.g.syntastic_markdown_checkers = {'mdl'}
            vim.g.syntastic_puppet_checkers = {'puppet', 'puppetlint'}
            vim.g.syntastic_python_checkers = {'flake8', 'mypy'}
            vim.g.syntastic_rst_checkers = {'rstcheck'}
            vim.g.syntastic_ruby_checkers = {'mri', 'rubocop', 'reek', 'flog'}
            vim.g.syntastic_sh_checkers = {'sh', 'shellcheck', 'checkbashims', 'bashate'}
            vim.g.syntastic_viml_checkers = {'vimlint'}
            vim.g.syntastic_yaml_checkers = {'yamllint'}

            -- Set linter options
            vim.g.syntastic_sh_bashate_args = '--max-line-length 140 --ignore E002,E003'
            vim.g.syntastic_sh_shellcheck_args = '-x'
        end
    }
}
