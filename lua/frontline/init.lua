
local M = {}
local parser = require("frontline.parser")
local task_client = require("frontline.task_client")
local renderer = require("frontline.renderer")

-- Function to refresh tasks in the current buffer
local function refresh_tasks()
  local bufnr = vim.api.nvim_get_current_buf()
  local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")

  if filetype ~= "markdown" then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local queries = parser.extract_queries(lines)

  for _, query_info in ipairs(queries) do
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

    -- Find the end of the current task list section
    local start_line = query_info.line_num
    local end_line = start_line
    while end_line < #lines and (string.match(lines[end_line + 1], "^%* ") or string.match(lines[end_line + 1], "^%s*$")) do
      end_line = end_line + 1
    end

    local header_line_idx = query_info.line_num - 1 -- 0-indexed header line
    local start_replace_idx = header_line_idx + 1 -- 0-indexed, line immediately after header

    local end_replace_idx = start_replace_idx
    -- Find the end of the existing task list (if any) or empty lines below the header
    -- The loop should continue as long as we are within bounds and the line matches a task or is empty.
    while end_replace_idx < #lines do
      local current_line_content = lines[end_replace_idx + 1] -- Lua tables are 1-indexed
      if string.match(current_line_content, "^%* ") or string.match(current_line_content, "^%s*$") then
        end_replace_idx = end_replace_idx + 1
      else
        break -- Stop if the line is not a task or empty
      end
    end

    -- nvim_buf_set_lines expects start_row (inclusive) and end_row (exclusive)
    vim.api.nvim_buf_set_lines(bufnr, start_replace_idx, end_replace_idx, false, formatted_tasks)
  end
end

function M.setup(opts)
  opts = opts or {}
  -- Plugin configuration will go here

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
