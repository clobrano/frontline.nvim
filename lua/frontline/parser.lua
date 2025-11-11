
local M = {}

-- Function to read the current buffer content (placeholder)
function M.read_buffer_content()
  -- This will be implemented later to read the actual buffer content
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

-- Function to identify Markdown headers with Taskwarrior queries
function M.extract_queries(lines)
  local queries = {}
  for i, line in ipairs(lines) do
    local header_match = string.match(line, "^(#+ .*) | (.+)$")
    if header_match then
      local header_text = header_match
      local query_string = string.match(line, "|%s*(.+)")
      if query_string then
        table.insert(queries, {
          line_num = i,
          header = header_text,
          query = query_string,
        })
      end
    end
  end
  return queries
end

return M
