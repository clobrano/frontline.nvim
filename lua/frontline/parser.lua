
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
        -- Extract workspace from query (e.g., @personal, @work)
        local workspace = string.match(query_string, "@([%w_%-]+)")

        -- Remove workspace from query string (so it doesn't get passed to taskwarrior)
        local cleaned_query = string.gsub(query_string, "%s*@[%w_%-]+%s*", " ")
        cleaned_query = string.gsub(cleaned_query, "^%s+", "") -- trim leading spaces
        cleaned_query = string.gsub(cleaned_query, "%s+$", "") -- trim trailing spaces

        table.insert(queries, {
          line_num = i,
          header = header_text,
          query = cleaned_query,
          workspace = workspace,
        })
      end
    end
  end
  return queries
end

return M
