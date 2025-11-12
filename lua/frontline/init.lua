
local M = {}
local parser = require("frontline.parser")
local task_client = require("frontline.task_client")
local renderer = require("frontline.renderer")
local mappings = require("frontline.mappings")

-- Default configuration
local config = {
  newlines_after_tasks = 2,
  convert_dates_to_local = false, -- Convert UTC timestamps to local time (default: false)
  mappings = {
    toggle_done = "<leader>td",
    toggle_started = "<leader>ts",
    modify_task = "<leader>tm",
    add_annotation = "<leader>ta",
    edit_task = "<leader>te",
    show_blocking_dependencies = "<leader>tb",
    add_dependency = "<leader>tB",
  },
}

-- Function to refresh tasks in the current buffer
local function refresh_tasks()
  local bufnr = vim.api.nvim_get_current_buf()
  local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")

  if filetype ~= "markdown" then
    return
  end

  -- Process queries one at a time, re-parsing after each update
  -- to keep line numbers accurate
  local processed_queries = {}

  while true do
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local queries = parser.extract_queries(lines)

    -- Find the first query we haven't processed yet
    local query_info = nil
    for _, q in ipairs(queries) do
      local query_key = q.line_num .. ":" .. q.query
      if not processed_queries[query_key] then
        query_info = q
        processed_queries[query_key] = true
        break
      end
    end

    -- If no unprocessed queries, we're done
    if not query_info then
      break
    end

    local tasks, err = task_client.execute_query(query_info.query)
    if err then
      -- TODO: Display error message at the bottom of the Neovim buffer (Task 7.1)
      print("Taskwarrior Error: " .. err)
      return
    end

    local formatted_tasks = {}
    for _, task in ipairs(tasks) do
      table.insert(formatted_tasks, renderer.format_task(task, config.convert_dates_to_local))
    end

    -- Add configured number of newlines after tasks
    for i = 1, config.newlines_after_tasks do
      table.insert(formatted_tasks, "")
    end

    local header_line_idx = query_info.line_num - 1 -- 0-indexed header line
    local start_replace_idx = header_line_idx + 1 -- 0-indexed, line immediately after header

    local end_replace_idx = start_replace_idx
    -- Find the end of the section - either the next header or end of file
    -- We replace everything in the section (task lines, empty lines, and other content)
    while end_replace_idx < #lines do
      local current_line_content = lines[end_replace_idx + 1] -- Lua tables are 1-indexed
      -- Stop if we encounter another markdown header (but only if it's truly a header with #)
      if string.match(current_line_content, "^#+ ") then
        break
      end
      -- Otherwise, include this line in the replacement range
      end_replace_idx = end_replace_idx + 1
    end

    -- Get fresh lines before making changes
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- nvim_buf_set_lines expects start_row (inclusive) and end_row (exclusive)
    vim.api.nvim_buf_set_lines(bufnr, start_replace_idx, end_replace_idx, false, formatted_tasks)
  end
end

-- Expose refresh function for mappings to use
function M.refresh_current_buffer()
  refresh_tasks()
end

function M.setup(opts)
  opts = opts or {}

  -- Merge user config with defaults
  config = vim.tbl_deep_extend("force", config, opts)

  -- Autocommands for refreshing task lists
  vim.api.nvim_create_autocmd({"BufReadPost", "BufWritePost"}, {
    pattern = "*.md", -- Only apply to Markdown files for now
    callback = refresh_tasks,
    group = vim.api.nvim_create_augroup("FrontlineRefresh", { clear = true }),
  })

  -- Placeholder command for manual refresh
  vim.api.nvim_create_user_command("FrontlineRefresh", function()
    refresh_tasks()
    print("Frontline: Manual refresh triggered for " .. vim.fn.bufname())
  end, {
    desc = "Manually refresh Frontline tasks in the current buffer",
  })

  -- Setup keybindings for task interactions (only in markdown files)
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "markdown",
    callback = function(args)
      local bufnr = args.buf
      local opts_mapping = { noremap = true, silent = true, buffer = bufnr }

      -- Toggle task done/undone
      if config.mappings.toggle_done then
        vim.keymap.set("n", config.mappings.toggle_done, mappings.toggle_done,
          vim.tbl_extend("force", opts_mapping, { desc = "Toggle task done/undone" }))
      end

      -- Toggle task started/unstarted
      if config.mappings.toggle_started then
        vim.keymap.set("n", config.mappings.toggle_started, mappings.toggle_started,
          vim.tbl_extend("force", opts_mapping, { desc = "Toggle task started/unstarted" }))
      end

      -- Modify task
      if config.mappings.modify_task then
        vim.keymap.set("n", config.mappings.modify_task, mappings.modify_task,
          vim.tbl_extend("force", opts_mapping, { desc = "Modify task" }))
      end

      -- Add annotation
      if config.mappings.add_annotation then
        vim.keymap.set("n", config.mappings.add_annotation, mappings.add_annotation,
          vim.tbl_extend("force", opts_mapping, { desc = "Add task annotation" }))
      end

      -- Edit task
      if config.mappings.edit_task then
        vim.keymap.set("n", config.mappings.edit_task, mappings.edit_task,
          vim.tbl_extend("force", opts_mapping, { desc = "Edit task in Taskwarrior editor" }))
      end

      -- Show blocking dependencies
      if config.mappings.show_blocking_dependencies then
        vim.keymap.set("n", config.mappings.show_blocking_dependencies, mappings.show_blocking_dependencies,
          vim.tbl_extend("force", opts_mapping, { desc = "Show task blocking dependencies" }))
      end

      -- Add task as dependency
      if config.mappings.add_dependency then
        vim.keymap.set("n", config.mappings.add_dependency, mappings.add_task_as_dependency,
          vim.tbl_extend("force", opts_mapping, { desc = "Add new task as dependency" }))
      end
    end,
    group = vim.api.nvim_create_augroup("FrontlineMappings", { clear = true }),
  })
end

return M
