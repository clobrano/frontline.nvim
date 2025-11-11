-- Minimal test configuration for frontline.nvim
-- Run with: nvim -u test_config.lua test.md

-- Add the plugin to the runtime path
vim.opt.runtimepath:prepend(vim.fn.getcwd())

-- Setup the plugin with configuration
require('frontline').setup({
  newlines_after_tasks = 2,  -- Number of blank lines after task list (default: 2)
})

-- Optional: Show a message when loaded
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    print("Frontline plugin loaded! Create a markdown file with '# Tasks | status:pending' to test.")
  end,
})
