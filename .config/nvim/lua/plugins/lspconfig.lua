return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      bashls = {
        filetypes = { "sh", "bash", "zsh" },
        settings = {
          bashIde = {
            shfmt = {
              path = "",
            },
          },
        },
      },
    },
  },
}
