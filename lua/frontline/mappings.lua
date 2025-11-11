local M = {}

-- Extract task hash from the current line
-- Expected format: * [status] description ... (hash)
function M.get_task_hash_under_cursor()
  local line = vim.api.nvim_get_current_line()

  -- Match the hash pattern at the end: (xxxxxxxx)
  local hash = string.match(line, "%(([a-f0-9]+)%)%s*$")

  if not hash then
    vim.notify("No task hash found on current line", vim.log.levels.WARN)
    return nil
  end

  return hash
end

-- Execute a task command and return success status
local function execute_task_command(command)
  local output = vim.fn.system(command)
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    vim.notify("Task command failed: " .. output, vim.log.levels.ERROR)
    return false
  end

  return true
end

-- Toggle task between done and undone
function M.toggle_done()
  local hash = M.get_task_hash_under_cursor()
  if not hash then
    return
  end

  -- Get current task status to determine action
  local task_json = vim.fn.system(string.format("task %s export", hash))
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    vim.notify("Failed to get task status", vim.log.levels.ERROR)
    return
  end

  -- Parse JSON to check status
  local success, tasks = pcall(vim.fn.json_decode, task_json)
  if not success or not tasks or #tasks == 0 then
    vim.notify("Failed to parse task data", vim.log.levels.ERROR)
    return
  end

  local task = tasks[1]
  local command

  if task.status == "completed" then
    -- Reopen the task
    command = string.format("task %s modify status:pending", hash)
    vim.notify("Reopening task...", vim.log.levels.INFO)
  else
    -- Mark as done
    command = string.format("task %s done", hash)
    vim.notify("Marking task as done...", vim.log.levels.INFO)
  end

  if execute_task_command(command) then
    -- Refresh the buffer
    require("frontline").refresh_current_buffer()
  end
end

-- Toggle task between started and unstarted
function M.toggle_started()
  local hash = M.get_task_hash_under_cursor()
  if not hash then
    return
  end

  -- Get current task status to determine action
  local task_json = vim.fn.system(string.format("task %s export", hash))
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    vim.notify("Failed to get task status", vim.log.levels.ERROR)
    return
  end

  -- Parse JSON to check if started
  local success, tasks = pcall(vim.fn.json_decode, task_json)
  if not success or not tasks or #tasks == 0 then
    vim.notify("Failed to parse task data", vim.log.levels.ERROR)
    return
  end

  local task = tasks[1]
  local command

  if task.start then
    -- Stop the task
    command = string.format("task %s stop", hash)
    vim.notify("Stopping task...", vim.log.levels.INFO)
  else
    -- Start the task
    command = string.format("task %s start", hash)
    vim.notify("Starting task...", vim.log.levels.INFO)
  end

  if execute_task_command(command) then
    -- Refresh the buffer
    require("frontline").refresh_current_buffer()
  end
end

-- Modify task description
function M.modify_task()
  local hash = M.get_task_hash_under_cursor()
  if not hash then
    return
  end

  -- Prompt user for modification string
  vim.ui.input({ prompt = "Modify task (e.g., 'priority:H due:tomorrow'): " }, function(input)
    if not input or input == "" then
      vim.notify("Modification cancelled", vim.log.levels.INFO)
      return
    end

    local command = string.format("task %s modify %s", hash, input)
    vim.notify("Modifying task...", vim.log.levels.INFO)

    if execute_task_command(command) then
      -- Refresh the buffer
      require("frontline").refresh_current_buffer()
    end
  end)
end

-- Add annotation to task
function M.add_annotation()
  local hash = M.get_task_hash_under_cursor()
  if not hash then
    return
  end

  -- Prompt user for annotation text
  vim.ui.input({ prompt = "Annotation text: " }, function(input)
    if not input or input == "" then
      vim.notify("Annotation cancelled", vim.log.levels.INFO)
      return
    end

    local command = string.format("task %s annotate '%s'", hash, input:gsub("'", "'\\''"))
    vim.notify("Adding annotation...", vim.log.levels.INFO)

    if execute_task_command(command) then
      -- Refresh the buffer
      require("frontline").refresh_current_buffer()
    end
  end)
end

return M
