local M = {}

-- Helper to calculate timezone offset in seconds
local function get_timezone_offset()
  local now = os.time()
  local utc_time = os.time(os.date("!*t", now))
  local local_time = os.time(os.date("*t", now))
  return os.difftime(local_time, utc_time)
end

-- Helper to parse ISO 8601 date format from Taskwarrior
-- If convert_to_local is true, converts UTC to local time
-- If convert_to_local is false, displays time as-is from Taskwarrior
local function parse_iso_date(iso_date, convert_to_local)
  if not iso_date then
    return nil
  end
  local year = tonumber(string.sub(iso_date, 1, 4))
  local month = tonumber(string.sub(iso_date, 5, 6))
  local day = tonumber(string.sub(iso_date, 7, 8))
  local hour = tonumber(string.sub(iso_date, 10, 11))
  local minute = tonumber(string.sub(iso_date, 12, 13))
  local second = tonumber(string.sub(iso_date, 14, 15))

  local final_time

  if convert_to_local then
    -- Properly convert UTC to local time
    -- First, create epoch time treating the values as UTC
    local utc_epoch = os.time({
      year = year,
      month = month,
      day = day,
      hour = hour,
      min = minute,
      sec = second,
      isdst = false
    })

    -- Adjust by timezone offset to get actual UTC epoch
    local timezone_offset = get_timezone_offset()
    local actual_utc_epoch = utc_epoch - timezone_offset

    -- Convert to local time
    final_time = os.date("*t", actual_utc_epoch)
  else
    -- Display time as-is without conversion
    final_time = {
      year = year,
      month = month,
      day = day,
      hour = hour,
      min = minute,
      sec = second
    }
  end

  -- Omit time if it's 00:00 (midnight) in the final time
  if final_time.hour == 0 and final_time.min == 0 then
    return string.format("%04d-%02d-%02d", final_time.year, final_time.month, final_time.day)
  else
    return string.format("%04d-%02d-%02d %02d:%02d", final_time.year, final_time.month, final_time.day, final_time.hour, final_time.min)
  end
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

  -- Priority: !!! for High, !! for Medium, ! for Low
  if task.priority then
    if task.priority == "H" then
      table.insert(icons, "!!!")
    elseif task.priority == "M" then
      table.insert(icons, "!!")
    elseif task.priority == "L" then
      table.insert(icons, "!")
    end
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
-- convert_to_local: if true, converts UTC timestamps to local time; if false, displays as-is
function M.format_task(task, convert_to_local)
  -- Default to true for backward compatibility
  if convert_to_local == nil then
    convert_to_local = true
  end

  local status = get_status_indicator(task)
  local description = task.description or ""
  local scheduled_str = format_scheduled_date(task, convert_to_local)
  local due_date_str = format_due_date(task, convert_to_local)
  local extra_icons_str = get_extra_icons(task)
  local short_hash = string.sub(task.uuid or "", 1, 8)

  local parts = {"*", status, description}

  -- Add scheduled date first (rounded parenthesis)
  if scheduled_str ~= "" then
    table.insert(parts, scheduled_str)
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