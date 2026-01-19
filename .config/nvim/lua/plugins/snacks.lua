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
        "block_continuation", -- This is the one appearing in your tree
        "fenced_code_block_delimiter",
      }

      -- 1. Disable background indent lines
      opts.indent.exclude = opts.indent.exclude or {}
      opts.indent.exclude.node_types = ignored_nodes

      -- 2. Disable active scope lines
      opts.scope.exclude = opts.scope.exclude or {}
      opts.scope.exclude.node_types = ignored_nodes
    end,
  },
}
