
local M = {}

-- Internal helper to run shell commands and get output/exit code
local function _run_shell_command(cmd)
  local stdout = vim.fn.system(cmd)
  local exit_code = vim.v.shell_error
  return stdout, exit_code
end

-- Function to execute a Taskwarrior query and return JSON output
-- workspace_rc: optional path to a taskwarrior rc file for workspace-specific queries
function M.execute_query(query_string, workspace_rc)
  -- Build command with optional rc file and query
  local cmd

  -- Handle empty query (query all tasks)
  if not query_string or query_string == "" then
    if workspace_rc and workspace_rc ~= "" then
      local escaped_rc = string.gsub(workspace_rc, "'", "'\\''")
      cmd = string.format("task rc:'%s' export", escaped_rc)
    else
      cmd = "task export"
    end
  else
    -- Escape single quotes in the query by replacing ' with '\''
    local escaped_query = string.gsub(query_string, "'", "'\\''")

    if workspace_rc and workspace_rc ~= "" then
      local escaped_rc = string.gsub(workspace_rc, "'", "'\\''")
      cmd = string.format("task rc:'%s' '%s' export", escaped_rc, escaped_query)
    else
      cmd = string.format("task '%s' export", escaped_query)
    end
  end

  local stdout, exit_code = _run_shell_command(cmd)

  if exit_code ~= 0 then
    -- Handle Taskwarrior command errors
    return nil, string.format("Taskwarrior command failed (exit code %d)\nCommand: %s\nOutput: %s",
      exit_code, cmd, stdout)
  end

  -- Filter out Taskwarrior informational messages (e.g., "TASKRC override: ...")
  -- These messages appear before the JSON output when using rc: override
  local cleaned_stdout = stdout
  if workspace_rc then
    -- Remove lines starting with "TASKRC override:"
    cleaned_stdout = string.gsub(stdout, "^TASKRC override:.-\n", "")
  end

  local ok, parsed_json = pcall(vim.fn.json_decode, cleaned_stdout)
  if not ok then
    return nil, string.format("Failed to parse Taskwarrior JSON output\nCommand: %s\nError: %s\nOutput preview: %s",
      cmd, parsed_json, string.sub(cleaned_stdout, 1, 200))
  end

  return parsed_json
end

-- Function to get reverse dependencies (tasks that depend on this task)
function M.get_reverse_dependencies(task_uuid)
  -- Query all tasks with dependencies
  -- Note: depends.any: uses substring matching, so we need to filter results
  local query = string.format("depends.any:%s", task_uuid)
  local cmd = string.format("task '%s' export", query)
  local stdout, exit_code = _run_shell_command(cmd)

  if exit_code ~= 0 then
    return nil, string.format("Failed to query reverse dependencies (exit code %d)", exit_code)
  end

  local ok, parsed_json = pcall(vim.fn.json_decode, stdout)
  if not ok then
    return nil, string.format("Failed to parse reverse dependencies JSON: %s", parsed_json)
  end

  -- Filter to only tasks that actually depend on this exact UUID
  -- (depends.any: does substring matching, which can give false positives)
  local filtered_results = {}
  for _, task in ipairs(parsed_json) do
    if task.depends then
      for _, dep_uuid in ipairs(task.depends) do
        if dep_uuid == task_uuid then
          table.insert(filtered_results, task)
          break
        end
      end
    end
  end

  return filtered_results
end

-- Expose for testing purposes
function M._set_run_shell_command_mock(mock_func)
  _run_shell_command = mock_func
end

return M
