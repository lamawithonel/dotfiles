return {
  "tinted-theming/tinted-nvim",
  priority = 1000,
  lazy = false,
  config = function()
    require("tinted-nvim").setup({
      selector = {
        enabled = true,
      },
    })
  end,
}
