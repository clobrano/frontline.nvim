local M = {}

-- Forward declaration: convert_utc_to_local falls back to the raw parser when
-- the system 'date' command is unavailable or fails.
local parse_iso_date_raw

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
function parse_iso_date_raw(iso_date)
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

-- Helper to resolve an ISO 8601 UTC date (YYYYMMDDTHHmmssZ) to its local
-- calendar parts. Uses the system 'date' command so timezone and DST are
-- handled, and returns nil when it is unavailable or the date is unparseable.
local function local_date_parts(iso_date)
  if not iso_date then return nil end

  -- Reformat from YYYYMMDDTHHmmssZ to YYYY-MM-DDTHH:MM:SSZ
  local formatted = string.gsub(iso_date, "(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)Z", "%1-%2-%3T%4:%5:%6Z")

  local cmd = string.format("date -d '%s' '+%%Y %%m %%d %%H %%M' 2>/dev/null", formatted)
  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then return nil end

  local year, month, day, hour, minute = vim.trim(result):match("^(%d+) (%d+) (%d+) (%d+) (%d+)$")
  if not year then return nil end

  return {
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = tonumber(hour),
    min = tonumber(minute),
  }
end

-- Helper to compute the number of whole days between today and a resolved
-- local date, both taken at local midnight. Negative for past dates.
local function diff_days_from_parts(parts)
  if not parts then return nil end

  -- Task date at midnight local time
  local task_ts = os.time({
    year = parts.year, month = parts.month, day = parts.day,
    hour = 0, min = 0, sec = 0,
  })

  -- Today at midnight local time
  local now = os.date("*t")
  local today_ts = os.time({
    year = now.year, month = now.month, day = now.day,
    hour = 0, min = 0, sec = 0,
  })

  return math.floor((task_ts - today_ts) / 86400)
end

-- Helper to compute the number of whole days between today and an ISO 8601 UTC
-- date, both taken at local midnight. Negative for past dates, nil on failure.
local function date_diff_days(iso_date)
  return diff_days_from_parts(local_date_parts(iso_date))
end

-- Helper to format a resolved local time of day as a compact 12-hour string:
-- "2pm", "10am", "11:35am". Returns nil at midnight, which is what Taskwarrior
-- stores for a whole-day event, so those keep showing the day alone.
local function format_time_from_parts(parts)
  if not parts then return nil end

  local hour, minute = parts.hour, parts.min
  if hour == 0 and minute == 0 then return nil end

  local suffix = hour < 12 and "am" or "pm"
  local hour12 = hour % 12
  if hour12 == 0 then hour12 = 12 end

  if minute == 0 then
    return string.format("%d%s", hour12, suffix)
  end
  return string.format("%d:%02d%s", hour12, minute, suffix)
end

-- Helper to turn a day difference into a relative string
-- Returns strings like "today", "tomorrow", "yesterday", "2 days", "3 weeks",
-- "1 month", or "-2 days", "-3 weeks", "-1 month" for past dates
local function relative_from_diff(diff_days)
  if not diff_days then return nil end

  if diff_days == 0 then
    return "today"
  elseif diff_days == 1 then
    return "tomorrow"
  elseif diff_days == -1 then
    return "yesterday"
  elseif diff_days > 0 then
    if diff_days < 7 then
      return string.format("+%d days", diff_days)
    elseif diff_days < 30 then
      local weeks = math.floor(diff_days / 7)
      return string.format("+%d %s", weeks, weeks == 1 and "week" or "weeks")
    else
      local months = math.floor(diff_days / 30)
      return string.format("+%d %s", months, months == 1 and "month" or "months")
    end
  else
    local abs_days = -diff_days
    if abs_days < 7 then
      return string.format("%d days ago", abs_days)
    elseif abs_days < 30 then
      local weeks = math.floor(abs_days / 7)
      return string.format("%d %s ago", weeks, weeks == 1 and "week" or "weeks")
    else
      local months = math.floor(abs_days / 30)
      return string.format("%d %s ago", months, months == 1 and "month" or "months")
    end
  end
end

-- Helper to compute a relative date string from an ISO 8601 UTC date
local function format_relative_date(iso_date)
  return relative_from_diff(date_diff_days(iso_date))
end

-- Helper to format a due/scheduled date for a task list line.
-- "today" on its own hides the hour of something happening in a few hours, so
-- dates falling today carry their local time ("today 2pm"). Whole-day events
-- (midnight) keep the day alone, and the absolute format already shows the
-- time it has.
local function format_list_date(iso_date, convert_to_local, use_relative)
  if use_relative then
    local parts = local_date_parts(iso_date)
    local diff_days = diff_days_from_parts(parts)
    local relative = relative_from_diff(diff_days)
    if relative then
      local time_str = diff_days == 0 and format_time_from_parts(parts)
      if time_str then
        return string.format("%s %s", relative, time_str)
      end
      return relative
    end
  end

  return parse_iso_date(iso_date, convert_to_local)
end

-- Helper to format scheduled date (rounded parenthesis)
local function format_scheduled_date(task, convert_to_local, use_relative)
  if task.scheduled then
    local date_str = format_list_date(task.scheduled, convert_to_local, use_relative)
    return string.format("(⏱️%s)", date_str)
  end
  return ""
end

-- Helper to format due date (squared brackets)
local function format_due_date(task, convert_to_local, use_relative)
  if task.due then
    local date_str = format_list_date(task.due, convert_to_local, use_relative)
    return string.format("[⏰%s]", date_str)
  end
  return ""
end

-- Helper to format end date for completed tasks (date only, except for tasks
-- completed today, where the time of day is what tells them apart)
local function format_end_date(task, convert_to_local, use_relative)
  local iso_date = task["end"]
  if not iso_date then
    return ""
  end

  local parts = local_date_parts(iso_date)
  local diff_days = diff_days_from_parts(parts)
  local is_today = diff_days == 0

  if use_relative then
    local date_str = relative_from_diff(diff_days)
    if date_str then
      local time_str = is_today and format_time_from_parts(parts)
      if time_str then
        return string.format("%s %s", date_str, time_str)
      end
      return date_str
    end
  end

  local date_str = parse_iso_date(iso_date, convert_to_local)
  if is_today then
    -- parse_iso_date has already dropped the time for a midnight value
    return date_str
  end
  -- Strip time portion, keep only the date (YYYY-MM-DD)
  return string.match(date_str, "^(%d%d%d%d%-%d%d%-%d%d)") or date_str
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

-- Helper to get priority, dependency, and recurrence icons
-- priority_labels: optional map from a Taskwarrior priority value to the text
-- shown for it, for users who would rather see a glyph than the bare value
local function get_extra_icons(task, priority_labels)
  local icons = {}

  -- Priority values are a Taskwarrior UDA the user can redefine, so the value
  -- itself is shown rather than a fixed icon that would only fit H/M/L
  if task.priority and task.priority ~= "" then
    local label = priority_labels and priority_labels[task.priority] or task.priority
    if label ~= "" then
      table.insert(icons, label)
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

  -- Recurring child instances carry a 'recur' field (templates are already filtered out)
  if task.recur then
    table.insert(icons, "🔁")
  end

  if #icons > 0 then
    return string.format("[%s]", table.concat(icons))
  end
  return ""
end

-- Function to format a single Taskwarrior task
-- convert_to_local: if true, converts UTC to local time using system date command
-- use_relative: if true, formats due/scheduled dates as relative (e.g. "tomorrow", "2 days")
-- priority_labels: optional map from priority value to the text shown for it
function M.format_task(task, convert_to_local, use_relative, priority_labels)
  -- Default to true (convert to local time by default)
  if convert_to_local == nil then
    convert_to_local = true
  end

  local status = get_status_indicator(task)
  local description = task.description or ""
  local due_date_str = format_due_date(task, convert_to_local, use_relative)
  local extra_icons_str = get_extra_icons(task, priority_labels)
  local short_hash = string.sub(task.uuid or "", 1, 8)

  -- For completed tasks, append end date in curly brackets after the description
  -- and skip the scheduled date
  if task.status == "completed" then
    local end_date_str = format_end_date(task, convert_to_local, use_relative)
    if end_date_str ~= "" then
      description = string.format("%s {✅%s}", description, end_date_str)
    end
  end

  local parts = {"*", status, description}

  -- Add scheduled date first (rounded parenthesis), but not for completed tasks
  if task.status ~= "completed" then
    local scheduled_str = format_scheduled_date(task, convert_to_local, use_relative)
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

  table.insert(parts, string.format("`%s`", short_hash))

  return table.concat(parts, " ")
end

-- Exposed for the task View, which formats the same dates and status markers
-- in a multi-line layout.
M.parse_iso_date = parse_iso_date
M.format_relative_date = format_relative_date
M.date_diff_days = date_diff_days
M.get_status_indicator = get_status_indicator

-- Placeholder for replacing content in the buffer
function M.render_tasks_in_buffer(start_line, end_line, formatted_tasks)
  -- This will be implemented later to actually replace buffer content
  print("Renderer: Would replace lines " .. start_line .. " to " .. end_line .. " with:")
  for _, task_line in ipairs(formatted_tasks) do
    print("  " .. task_line)
  end
end

return M