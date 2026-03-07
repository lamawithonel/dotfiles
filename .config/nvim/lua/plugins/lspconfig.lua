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
      yamlls = {
        settings = {
          yaml = {
            format = {
              singleQuote = true,
            },
          },
        },
        schemas = {
          ["https://raw.githubusercontent.com/siemens/kas/refs/heads/master/kas/schema-kas.json"] = "*.kas.yml",
        },
      },
    },
  },
}
