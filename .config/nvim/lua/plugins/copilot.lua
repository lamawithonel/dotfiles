return {
  {
    'github/copilot.vim',
    event = 'InsertEnter',
  },
  {
    'CopilotC-Nvim/CopilotChat.nvim',
    dependencies = {
      { 'github/copilot.vim' },
      { 'nvim-lua/plenary.nvim', branch = 'master' },
    },
    build = 'make tiktoken',
    opts = {
      -- See Configuration section for options
      --[[
      mappings = {
        send = {
          insert = '<C-CR>',
          normal = '<C-CR>',
	    },
      },
      --]]
      chat_autocomplete = true,
    },
    -- See Commands section for default commands if you want to lazy load on them
  },
}
