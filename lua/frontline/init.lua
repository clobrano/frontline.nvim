
local M = {}
local parser = require("frontline.parser")
local task_client = require("frontline.task_client")
local renderer = require("frontline.renderer")

-- Default configuration
local config = {
  newlines_after_tasks = 2,
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
      table.insert(formatted_tasks, renderer.format_task(task))
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
end

return M
