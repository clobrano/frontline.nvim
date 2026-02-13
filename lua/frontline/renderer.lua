local M = {}

-- Helper to convert ISO 8601 date from Taskwarrior (YYYYMMDDTHHmmssZ) to local time
-- Uses the system's 'date' command to handle timezone conversion and DST
local function convert_utc_to_local(iso_date)
  if not iso_date then
    return nil
  end

  -- Reformat from YYYYMMDDTHHmmssZ to YYYY-MM-DDTHH:MM:SSZ (standard ISO 8601)
  local formatted = string.gsub(iso_date, "(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)Z", "%1-%2-%3T%4:%5:%6Z")

  -- Use system date command to convert to local time
  local cmd = string.format("date -d '%s' '+%%Y-%%m-%%d %%H:%%M' 2>/dev/null", formatted)
  local result = vim.fn.system(cmd)
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    -- Fallback: display as-is if date command fails
    return parse_iso_date_raw(iso_date)
  end

  -- Trim whitespace and return
  return vim.trim(result)
end

-- Helper to parse ISO 8601 date format without conversion (raw display)
local function parse_iso_date_raw(iso_date)
  if not iso_date then
    return nil
  end
  local year = string.sub(iso_date, 1, 4)
  local month = string.sub(iso_date, 5, 6)
  local day = string.sub(iso_date, 7, 8)
  local hour = string.sub(iso_date, 10, 11)
  local minute = string.sub(iso_date, 12, 13)

  return string.format("%s-%s-%s %s:%s", year, month, day, hour, minute)
end

-- Helper to parse and optionally convert ISO 8601 date
local function parse_iso_date(iso_date, convert_to_local)
  if not iso_date then
    return nil
  end

  local date_str
  if convert_to_local then
    date_str = convert_utc_to_local(iso_date)
  else
    date_str = parse_iso_date_raw(iso_date)
  end

  -- Apply midnight detection: omit time if it's 00:00
  if string.match(date_str, " 00:00$") then
    return string.gsub(date_str, " 00:00$", "")
  end

  return date_str
end

-- Helper to format scheduled date (rounded parenthesis)
local function format_scheduled_date(task, convert_to_local)
  if task.scheduled then
    return string.format("(%s)", parse_iso_date(task.scheduled, convert_to_local))
  end
  return ""
end

-- Helper to format due date (squared brackets)
local function format_due_date(task, convert_to_local)
  if task.due then
    return string.format("[%s]", parse_iso_date(task.due, convert_to_local))
  end
  return ""
end

-- Helper to format end date for completed tasks
local function format_end_date(task, convert_to_local)
  if task["end"] then
    return parse_iso_date(task["end"], convert_to_local)
  end
  return ""
end

-- Helper to get status indicator
local function get_status_indicator(task)
  if task.status == "completed" then
    return "[x]"
  elseif task.status == "deleted" then
    return "[-]"
  elseif task.status == "pending" and task.start then
    return "[S]"
  else
    return "[ ]"
  end
end

-- Helper to get priority, dependency, and annotation icons
local function get_extra_icons(task)
  local icons = {}

  -- Priority: 🔴 for High, 🟠 for Medium, 🟡 for Low
  if task.priority then
    if task.priority == "H" then
      table.insert(icons, "🔴")
    elseif task.priority == "M" then
      table.insert(icons, "🟠")
    elseif task.priority == "L" then
      table.insert(icons, "🟡")
    end
  end

  -- For dependencies, Taskwarrior 'export' includes a 'depends' field as a table of UUIDs
  if task.depends and #task.depends > 0 then
    table.insert(icons, "🔒")
  end

  -- For reverse dependencies, check if this task is blocking others
  if task._reverse_deps and #task._reverse_deps > 0 then
    table.insert(icons, "⚓")
  end

  -- For annotations, Taskwarrior 'export' includes an 'annotations' field as a table
  if task.annotations and #task.annotations > 0 then
    table.insert(icons, "🗒️")
  end

  if #icons > 0 then
    return string.format("[%s]", table.concat(icons))
  end
  return ""
end

-- Function to format a single Taskwarrior task
-- convert_to_local: if true, converts UTC to local time using system date command
function M.format_task(task, convert_to_local)
  -- Default to true (convert to local time by default)
  if convert_to_local == nil then
    convert_to_local = true
  end

  local status = get_status_indicator(task)
  local description = task.description or ""
  local due_date_str = format_due_date(task, convert_to_local)
  local extra_icons_str = get_extra_icons(task)
  local short_hash = string.sub(task.uuid or "", 1, 8)

  -- For completed tasks, wrap description and end date in curly brackets
  -- and skip the scheduled date
  if task.status == "completed" then
    local end_date_str = format_end_date(task, convert_to_local)
    if end_date_str ~= "" then
      description = string.format("{%s %s}", description, end_date_str)
    else
      description = string.format("{%s}", description)
    end
  end

  local parts = {"*", status, description}

  -- Add scheduled date first (rounded parenthesis), but not for completed tasks
  if task.status ~= "completed" then
    local scheduled_str = format_scheduled_date(task, convert_to_local)
    if scheduled_str ~= "" then
      table.insert(parts, scheduled_str)
    end
  end

  -- Add due date (squared brackets)
  if due_date_str ~= "" then
    table.insert(parts, due_date_str)
  end

  -- Only add icons if they exist
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