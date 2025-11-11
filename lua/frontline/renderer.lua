local M = {}

-- Helper to parse ISO 8601 date format from Taskwarrior and convert to local time
local function parse_iso_date(iso_date)
  if not iso_date then
    return nil
  end
  local year = tonumber(string.sub(iso_date, 1, 4))
  local month = tonumber(string.sub(iso_date, 5, 6))
  local day = tonumber(string.sub(iso_date, 7, 8))
  local hour = tonumber(string.sub(iso_date, 10, 11))
  local minute = tonumber(string.sub(iso_date, 12, 13))
  local second = tonumber(string.sub(iso_date, 14, 15))

  -- Convert UTC timestamp to epoch time
  local utc_time = os.time({
    year = year,
    month = month,
    day = day,
    hour = hour,
    min = minute,
    sec = second,
    isdst = false
  })

  -- Convert to local time
  local local_time = os.date("*t", utc_time)

  -- Omit time if it's 00:00 (midnight) in local time
  if local_time.hour == 0 and local_time.min == 0 then
    return string.format("%04d-%02d-%02d", local_time.year, local_time.month, local_time.day)
  else
    return string.format("%04d-%02d-%02d %02d:%02d", local_time.year, local_time.month, local_time.day, local_time.hour, local_time.min)
  end
end

-- Helper to format scheduled date (rounded parenthesis)
local function format_scheduled_date(task)
  if task.scheduled then
    return string.format("(%s)", parse_iso_date(task.scheduled))
  end
  return ""
end

-- Helper to format due date (squared brackets)
local function format_due_date(task)
  if task.due then
    return string.format("[%s]", parse_iso_date(task.due))
  end
  return ""
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
function M.format_task(task)
  local status = get_status_indicator(task)
  local description = task.description or ""
  local scheduled_str = format_scheduled_date(task)
  local due_date_str = format_due_date(task)
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