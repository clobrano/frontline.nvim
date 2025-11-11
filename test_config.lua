-- Minimal test configuration for frontline.nvim
-- Run with: nvim -u test_config.lua test.md

-- Add the plugin to the runtime path
vim.opt.runtimepath:prepend(vim.fn.getcwd())

-- Setup the plugin with configuration
require('frontline').setup({
  newlines_after_tasks = 2,  -- Number of blank lines after task list (default: 2)
  mappings = {
    toggle_done = "<leader>td",      -- Toggle task done/undone
    toggle_started = "<leader>ts",   -- Toggle task started/unstarted
    modify_task = "<leader>tm",      -- Modify task properties
    add_annotation = "<leader>ta",   -- Add task annotation
  },
})

-- Optional: Show a message when loaded
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    print("Frontline plugin loaded!")
    print("Create a markdown file with '# Tasks | status:pending' to test.")
    print("Use <leader>td, <leader>ts, <leader>tm, <leader>ta on task lines.")
  end,
})
