
local M = {}

-- Mock buffer content
M.mock_buffer_content = {}
local mock_buf_option_filetype = "markdown"

function M.set_mock_buffer_content(content_lines)
  M.mock_buffer_content = content_lines
end

function M.set_mock_filetype(filetype)
  mock_buf_option_filetype = filetype
end

-- Store original Neovim functions
local original_nvim_buf_get_lines
local original_nvim_buf_get_option
local original_nvim_buf_set_lines
local original_nvim_create_autocmd
local original_nvim_create_user_command

-- Mocked autocmd and user command storage
local autocmd_callbacks = {}
local user_commands = {}

function M.trigger_autocmd(event, bufnr)
  if autocmd_callbacks[event] then
    for _, cb_info in ipairs(autocmd_callbacks[event]) do
      if cb_info.pattern == "*.md" then -- Simplified pattern matching for mock
        cb_info.callback({buf = bufnr})
      end
    end
  end
end

function M.execute_user_command(command_name)
  if user_commands[command_name] then
    user_commands[command_name].callback()
  end
end

function M.setup_mocks()
  -- Save original functions
  original_nvim_buf_get_lines = vim.api.nvim_buf_get_lines
  original_nvim_buf_get_option = vim.api.nvim_buf_get_option
  original_nvim_buf_set_lines = vim.api.nvim_buf_set_lines
  original_nvim_create_autocmd = vim.api.nvim_create_autocmd
  original_nvim_create_user_command = vim.api.nvim_create_user_command

  -- Apply mocks
  vim.api.nvim_buf_get_lines = function(bufnr, start_line, end_line, strict_indexing)
    if bufnr == 0 then -- Current buffer
      return M.mock_buffer_content
    end
    return original_nvim_buf_get_lines(bufnr, start_line, end_line, strict_indexing)
  end

  vim.api.nvim_buf_get_option = function(bufnr, option_name)
    if bufnr == 0 and option_name == "filetype" then
      return mock_buf_option_filetype
    end
    return original_nvim_buf_get_option(bufnr, option_name)
  end

  vim.api.nvim_buf_set_lines = function(bufnr, start_line, end_line, strict_indexing, replacement_lines)
    if bufnr == 0 then
      local original_mock_content_copy = {}
      for _, line in ipairs(M.mock_buffer_content) do
        table.insert(original_mock_content_copy, line)
      end

      local new_content = {}
      -- Copy lines before the start_line (0-indexed)
      for i = 1, start_line do -- Copy up to start_line (exclusive in nvim_buf_set_lines, so 0-indexed start_line means copy lines 0 to start_line-1)
        table.insert(new_content, original_mock_content_copy[i])
      end
      -- Insert replacement lines
      for _, line in ipairs(replacement_lines) do
        table.insert(new_content, line)
      end
      -- Copy lines after the end_line (0-indexed, exclusive)
      for i = end_line + 1, #original_mock_content_copy do
        table.insert(new_content, original_mock_content_copy[i])
      end
      M.mock_buffer_content = {}
      for _, line in ipairs(new_content) do
        table.insert(M.mock_buffer_content, line)
      end
    else
      original_nvim_buf_set_lines(bufnr, start_line, end_line, strict_indexing, replacement_lines)
    end
  end

  vim.api.nvim_create_autocmd = function(events, opts)
    for _, event in ipairs(events) do
      autocmd_callbacks[event] = autocmd_callbacks[event] or {}
      table.insert(autocmd_callbacks[event], opts)
    end
  end

  vim.api.nvim_create_user_command = function(name, callback, opts)
    user_commands[name] = {callback = callback, opts = opts}
  end
end

-- Restore original Neovim functions and clear mock state
function M.restore_mocks()
  if original_nvim_buf_get_lines then vim.api.nvim_buf_get_lines = original_nvim_buf_get_lines end
  if original_nvim_buf_get_option then vim.api.nvim_buf_get_option = original_nvim_buf_get_option end
  if original_nvim_buf_set_lines then vim.api.nvim_buf_set_lines = original_nvim_buf_set_lines end
  if original_nvim_create_autocmd then vim.api.nvim_create_autocmd = original_nvim_create_autocmd end
  if original_nvim_create_user_command then vim.api.nvim_create_user_command = original_nvim_create_user_command end

  -- Clear mock state
  M.mock_buffer_content = {}
  mock_buf_option_filetype = "markdown"
  autocmd_callbacks = {}
  user_commands = {}
end

return M
