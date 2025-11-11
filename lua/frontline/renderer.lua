local M = {}

-- Helper to format due date
local function format_due_date(task)
  if task.due then
    -- Taskwarrior 'export' provides due date in ISO 8601 format (e.g., "20251114T170000Z")
    -- We need to parse and reformat it.
    -- A simple approach for now: extract date and time parts.
    local year = string.sub(task.due, 1, 4)
    local month = string.sub(task.due, 5, 6)
    local day = string.sub(task.due, 7, 8)
    local hour = string.sub(task.due, 10, 11)
    local minute = string.sub(task.due, 12, 13)
    return string.format("(%s-%s-%s %s:%s)", year, month, day, hour, minute)
  end
  return "()" -- Return empty parentheses if no due date
end

-- Helper to get status indicator
local function get_status_indicator(task)
  if task.status == "completed" then
    return "[x]"
  elseif task.status == "pending" and task.start then
    return "[S]"
  else
    return "[ ]"
  end
end

-- Helper to get priority, dependency, and annotation icons
local function get_extra_icons(task)
  local icons = {}
  if task.priority then
    table.insert(icons, string.sub(task.priority, 1, 1))
  end
  -- For dependencies, Taskwarrior 'export' includes a 'depends' field as a table of UUIDs
  if task.depends and #task.depends > 0 then
    table.insert(icons, "🔒")
  end
  -- For annotations, Taskwarrior 'export' includes an 'annotations' field as a table
  if task.annotations and #task.annotations > 0 then
    table.insert(icons, "A")
  end

  if #icons > 0 then
    return string.format("[%s]", table.concat(icons, ","))
  end
  return ""
end

-- Function to format a single Taskwarrior task
function M.format_task(task)
  local status = get_status_indicator(task)
  local description = task.description or ""
  local due_date_str = format_due_date(task)
  local extra_icons_str = get_extra_icons(task)
  local short_hash = string.sub(task.uuid or "", 1, 8)

  local parts = {"*", status, description, due_date_str}

  if extra_icons_str ~= "" then
    table.insert(parts, extra_icons_str)
  end

  table.insert(parts, string.format("(%s)", short_hash))

  return table.concat(parts, " ")
end

-- Placeholder for replacing content in the buffer
function M.render_tasks_in_buffer(start_line, end_line, formatted_tasks)
  -- This will be implemented later to actually replace buffer content
  print("Renderer: Would replace lines " .. start_line .. " to " .. end_line .. " with:")
  for _, task_line in ipairs(formatted_tasks) do
    print("  " .. task_line)
  end
end

return M