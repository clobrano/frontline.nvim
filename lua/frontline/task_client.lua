
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

-- Get the set of UUIDs for all tasks currently blocking other tasks (single query)
function M.get_blocking_uuids(workspace_rc)
  local cmd
  if workspace_rc and workspace_rc ~= "" then
    local escaped_rc = string.gsub(workspace_rc, "'", "'\\''")
    cmd = string.format("task rc:'%s' +BLOCKING export", escaped_rc)
  else
    cmd = "task +BLOCKING export"
  end

  local stdout, exit_code = _run_shell_command(cmd)
  if exit_code ~= 0 then
    return nil, string.format("Failed to query blocking tasks (exit code %d)", exit_code)
  end

  -- Strip TASKRC override messages (same as execute_query)
  local cleaned_stdout = stdout
  if workspace_rc then
    cleaned_stdout = string.gsub(stdout, "^TASKRC override:.-\n", "")
  end

  local ok, parsed_json = pcall(vim.fn.json_decode, cleaned_stdout)
  if not ok then
    return nil, string.format("Failed to parse blocking tasks JSON: %s", parsed_json)
  end

  local uuid_set = {}
  for _, task in ipairs(parsed_json) do
    if task.uuid then
      uuid_set[task.uuid] = true
    end
  end

  return uuid_set
end

-- Function to get reverse dependencies (tasks that depend on this task)
function M.get_reverse_dependencies(task_uuid, workspace_rc)
  -- Query all tasks with dependencies
  -- Note: depends.any: uses substring matching, so we need to filter results
  local query = string.format("depends.any:%s", task_uuid)
  local cmd
  if workspace_rc and workspace_rc ~= "" then
    local escaped_rc = string.gsub(workspace_rc, "'", "'\\''")
    cmd = string.format("task rc:'%s' '%s' export", escaped_rc, query)
  else
    cmd = string.format("task '%s' export", query)
  end

  local stdout, exit_code = _run_shell_command(cmd)

  if exit_code ~= 0 then
    return nil, string.format("Failed to query reverse dependencies (exit code %d)", exit_code)
  end

  -- Strip TASKRC override messages (same as execute_query)
  if workspace_rc then
    stdout = string.gsub(stdout, "^TASKRC override:.-\n", "")
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

-- Run an arbitrary Taskwarrior command (e.g. "<hash> annotate 'text'") against
-- an optional workspace rc file. Returns success, output.
function M.run_command(task_args, workspace_rc)
  local cmd
  if workspace_rc and workspace_rc ~= "" then
    local escaped_rc = string.gsub(workspace_rc, "'", "'\\''")
    cmd = string.format("task rc:'%s' %s", escaped_rc, task_args)
  else
    cmd = string.format("task %s", task_args)
  end

  local stdout, exit_code = _run_shell_command(cmd)
  if exit_code ~= 0 then
    return false, stdout
  end
  return true, stdout
end

-- Priority is a Taskwarrior UDA, so the set of values and their order is up to
-- the user: 'uda.priority.values' lists them highest first, and the empty entry
-- marks where tasks with no priority rank. "H,M,L," is only the default, and
-- something like "A,B,,C" (where C ranks below no priority at all) is valid.
local DEFAULT_PRIORITY_VALUES = { "H", "M", "L", "" }

-- Cached per rc file, since each workspace has its own Taskwarrior config
local priority_values_cache = {}

-- Split a 'uda.priority.values' setting, keeping empty entries: they carry the
-- rank of tasks with no priority and cannot be dropped.
function M.parse_priority_values(raw)
  local values = {}
  local pos = 1
  while true do
    local start_idx, end_idx = string.find(raw, ",", pos, true)
    if not start_idx then
      table.insert(values, string.sub(raw, pos))
      break
    end
    table.insert(values, string.sub(raw, pos, start_idx - 1))
    pos = end_idx + 1
  end

  -- A list with no real values tells us nothing; let the caller fall back
  local has_value = false
  for _, value in ipairs(values) do
    if value ~= "" then has_value = true end
  end
  if not has_value then
    return nil
  end

  -- Without an empty entry Taskwarrior has no rank for unset priorities, so
  -- put them last, which is where the default configuration places them.
  local has_unset = false
  for _, value in ipairs(values) do
    if value == "" then has_unset = true end
  end
  if not has_unset then
    table.insert(values, "")
  end

  return values
end

-- Ordered priority values configured in Taskwarrior, highest first.
-- Falls back to the H/M/L default when the config cannot be read.
function M.get_priority_values(workspace_rc)
  local cache_key = workspace_rc or ""
  if priority_values_cache[cache_key] then
    return priority_values_cache[cache_key]
  end

  local cmd
  if workspace_rc and workspace_rc ~= "" then
    local escaped_rc = string.gsub(workspace_rc, "'", "'\\''")
    cmd = string.format("task rc:'%s' _show", escaped_rc)
  else
    cmd = "task _show"
  end

  local values
  local stdout, exit_code = _run_shell_command(cmd)
  if exit_code == 0 and stdout then
    -- '_show' prints one 'name=value' per line
    local raw = string.match("\n" .. stdout, "\nuda%.priority%.values=([^\n]*)")
    if raw then
      values = M.parse_priority_values(vim.trim(raw))
    end
  end

  values = values or DEFAULT_PRIORITY_VALUES
  priority_values_cache[cache_key] = values
  return values
end

-- Drop the cached priority values, so a Taskwarrior config change is picked up
function M.invalidate_priority_values()
  priority_values_cache = {}
end

-- Expose for testing purposes
function M._set_run_shell_command_mock(mock_func)
  _run_shell_command = mock_func
  M.invalidate_priority_values()
end

return M
