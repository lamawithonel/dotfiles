return {
  {
    "chriskempson/base16-vim",
    lazy = false,
    config = function()
      local t_Co = tonumber(vim.fn.system("tput colors || echo 8"))

      if vim.opt.termguicolors or vim.env.COLORTERM == "truecolor" or t_Co >= 256 then
        vim.g.base16colorspace = 256
      elseif t_Co >= 88 then
        vim.g.base16colorspace = 88
      elseif t_Co >= 16 then
        vim.g.base16colorspace = 16
      else
        vim.g.base16colorspace = 8
      end

      if
        vim.env.BASE16_THEME and ((not vim.g.colors_name) or (vim.g.colors_name ~= "base16-" .. vim.env.BASE16_THEME))
      then
        vim.cmd("colorscheme base16-" .. vim.env.BASE16_THEME)
      else
        vim.cmd("colorscheme base16-solarized-dark")
      end
    end,
  },
}
