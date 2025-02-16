return {
    {
        'chriskempson/base16-vim',
        config = function()
            local t_Co = nil

            local function get_terminal_colors()
                if not t_Co then
                    tonumber(vim.fn.system('tput colors || echo 2'))
                end
                return t_Co
            end

            if vim.opt.termguicolors or vim.env.COLORTERM == 'truecolor' or get_terminal_colors() >= 256  then
               vim.g.base16colorspace = 256
            elseif get_terminal_colors() >= 88 then
               vim.g.base16colorspace = 88
            elseif get_terminal_colors() >= 16 then
               vim.g.base16colorspace = 16
            elseif get_terminal_colors() >= 8 then
                vim.g.base16colorspace = 8
            end

            if vim.fn.filereadable(vim.fn.expand("~/.vimrc_background")) then
                vim.cmd('source ~/.vimrc_background')
            else
                vim.cmd('colorscheme base16-solarized-dark')
            end
        end,
    }
}
