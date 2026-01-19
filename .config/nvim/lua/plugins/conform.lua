return {
  "stevearc/conform.nvim",
  opts = function(_, opts)
    opts.formatters = opts.formatters or {}
    opts.formatters.shfmt = {
      append_args = {
        "--binary-next-line",
        "--case-indent",
        "--keep-padding",
        "--space-redirects",
      }
    }
  end,
}
