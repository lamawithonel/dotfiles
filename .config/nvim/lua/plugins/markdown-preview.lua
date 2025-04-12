return {
  {
    "iamcco/markdown-preview.nvim",
    ft = { "markdown" },
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    build = function()
      vim.fn.system("cd app && npx --yes yarn install")
    end,
    config = function()
      vim.g.mkdp_filetypes = { "markdown" }
      vim.g.mkdp_auto_start = 1
      vim.g.mkdp_auto_close = 1
      vim.g.mkdp_browser = "firefox"
      vim.g.mkdp_refresh_slow = 1
      vim.g.mkdp_preview_options = {
        mkit = {},
        katex = {},
        uml = {},
        maid = {},
        disable_sync_scroll = 0,
        sync_scroll_type = "middle",
        hide_yaml_meta = 1,
        sequence_diagrams = {},
        flowchart_diagrams = {},
        content_editable = false,
        disable_filename = 0,
      }
      vim.cmd([[
        function OpenMarkdownPreview (url)
          if has('win32') || has('win64') || has('win16')
            let cmd = 'start --new-window '
          elseif has('mac')
            let cmd = 'open --new -a "Google Chrome" --args --new-window '
          elseif has('unix')
            let cmd = 'firefox --new-window '
          endif
          silent call system(cmd . shellescape(a:url) . ' &')
        endfunction
      ]])
      vim.g.mkdp_browserfunc = "OpenMarkdownPreview"
    end,
  },
}
