
local M = {}

-- Internal helper to run shell commands and get output/exit code
local function _run_shell_command(cmd)
  local stdout = vim.fn.system(cmd)
  local exit_code = vim.v.shell_error
  return stdout, exit_code
end

-- Function to execute a Taskwarrior query and return JSON output
function M.execute_query(query_string)
  local cmd = string.format("task %s export", query_string)
  local stdout, exit_code = _run_shell_command(cmd)

  if exit_code ~= 0 then
    -- Handle Taskwarrior command errors
    return nil, "Taskwarrior command failed with exit code " .. exit_code .. ": " .. stdout
  end

  local ok, parsed_json = pcall(vim.fn.json_decode, stdout)
  if not ok then
    return nil, "Failed to parse Taskwarrior JSON output: " .. parsed_json
  end

  return parsed_json
end

-- Expose for testing purposes
function M._set_run_shell_command_mock(mock_func)
  _run_shell_command = mock_func
end

return M
