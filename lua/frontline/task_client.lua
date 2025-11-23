
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
  -- Escape single quotes in the query by replacing ' with '\''
  local escaped_query = string.gsub(query_string, "'", "'\\''")

  -- Build command with optional rc file
  local cmd
  if workspace_rc and workspace_rc ~= "" then
    local escaped_rc = string.gsub(workspace_rc, "'", "'\\''")
    cmd = string.format("task rc:'%s' '%s' export", escaped_rc, escaped_query)
  else
    cmd = string.format("task '%s' export", escaped_query)
  end

  local stdout, exit_code = _run_shell_command(cmd)

  if exit_code ~= 0 then
    -- Handle Taskwarrior command errors
    return nil, string.format("Taskwarrior command failed (exit code %d)\nCommand: %s\nOutput: %s",
      exit_code, cmd, stdout)
  end

  local ok, parsed_json = pcall(vim.fn.json_decode, stdout)
  if not ok then
    return nil, string.format("Failed to parse Taskwarrior JSON output\nCommand: %s\nError: %s\nOutput preview: %s",
      cmd, parsed_json, string.sub(stdout, 1, 200))
  end

  return parsed_json
end

-- Expose for testing purposes
function M._set_run_shell_command_mock(mock_func)
  _run_shell_command = mock_func
end

return M
