return {
  "stevearc/conform.nvim",
  opts = {
    -- shfmt will mess up scripts like no other
    formatters_by_ft = {
      sh = {},
      bash = {},
      zsh = {},
    },
  },
}
