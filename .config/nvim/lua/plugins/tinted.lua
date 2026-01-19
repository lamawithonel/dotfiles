return {
  "tinted-theming/tinted-nvim",
  lazy = false,
  config = function()
    local t_Co = tonumber(vim.fn.system("tput colors || echo 8"))

    if vim.opt.termguicolors or vim.env.COLORTERM == "truecolor" or t_Co >= 256 then
      vim.opt.termguicolors = true
      vim.g.base16colorspace = 256
    elseif t_Co >= 88 then
      vim.g.base16colorspace = 88
    elseif t_Co >= 16 then
      vim.g.base16colorspace = 16
    else
      vim.g.base16colorspace = 8
    end

    require("tinted-colorscheme").setup()
  end,
}
