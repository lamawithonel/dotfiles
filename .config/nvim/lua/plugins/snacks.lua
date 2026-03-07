return {
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      opts.indent = opts.indent or {}
      opts.scope = opts.scope or {}

      -- Nodes to completely ignore for drawing any lines
      local ignored_nodes = {
        "fenced_code_block",
        "code_fence_content",
        "code_block",
        "block_continuation",
        "fenced_code_block_delimiter",
      }

      -- 1. Disable background indent lines
      opts.indent.exclude = opts.indent.exclude or {}
      opts.indent.exclude.node_types = ignored_nodes

      -- 2. Disable active scope lines
      opts.scope.exclude = opts.scope.exclude or {}
      opts.scope.exclude.node_types = ignored_nodes

      opts.scroll = {
        animate = {
          duration = { step = 10, total = 100 },
          easing = "inCubic",
        },
        -- faster animation when repeating scroll after delay
        animate_repeat = {
          delay = 100, -- delay in ms before using the repeat animation
          duration = { step = 5, total = 50 },
          easing = "linear",
        },
        -- what buffers to animate
        filter = function(buf)
          return vim.g.snacks_scroll ~= false
            and vim.b[buf].snacks_scroll ~= false
            and vim.bo[buf].buftype ~= "terminal"
        end,
      }
    end,
  },
}
