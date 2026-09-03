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
-- a date falling today shows its local time instead ("2pm"). Whole-day events
-- (midnight) have no time to show and keep saying "today", and the absolute
-- format already shows the time it has.
local function format_list_date(iso_date, convert_to_local, use_relative)
  if use_relative then
    local parts = local_date_parts(iso_date)
    local diff_days = diff_days_from_parts(parts)
    local relative = relative_from_diff(diff_days)
    if relative then
      local time_str = diff_days == 0 and format_time_from_parts(parts)
      return time_str or relative
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

-- Helper to format end date for completed tasks. Unlike due and scheduled,
-- completion is a fact to look up rather than something to plan around, so it
-- always shows the ISO day: never a relative form, never a time.
local function format_end_date(task, convert_to_local)
  local iso_date = task["end"]
  if not iso_date then
    return ""
  end

  local date_str = parse_iso_date(iso_date, convert_to_local)
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

-- Markers shown next to a task. Their placeholder names are part of the
-- documented task_format vocabulary: blocked, blocking, recurring.
local ICON_BLOCKED = "🔒"   -- the task depends on tasks that are not done yet
local ICON_BLOCKING = "⚓"  -- other tasks depend on this one
local ICON_RECURRING = "🔁" -- the task is an instance of a recurring task

-- Helper to get the text shown for a task's priority.
-- Priority values are a Taskwarrior UDA the user can redefine, so the value
-- itself is shown rather than a fixed icon that would only fit H/M/L.
-- priority_labels: optional map from a Taskwarrior priority value to the text
-- shown for it, for users who would rather see a glyph than the bare value
local function format_priority(task, priority_labels)
  if not task.priority or task.priority == "" then
    return ""
  end

  local label = priority_labels and priority_labels[task.priority] or task.priority
  return label or ""
end

-- Helper to get the bracketed group of priority, dependency, and recurrence
-- markers, e.g. "[H🔒⚓]"
local function get_extra_icons(task, priority_labels)
  local icons = {}

  local priority = format_priority(task, priority_labels)
  if priority ~= "" then
    table.insert(icons, priority)
  end

  -- For dependencies, Taskwarrior 'export' includes a 'depends' field as a table of UUIDs
  if task.depends and #task.depends > 0 then
    table.insert(icons, ICON_BLOCKED)
  end

  -- For reverse dependencies, check if this task is blocking others
  if task._reverse_deps and #task._reverse_deps > 0 then
    table.insert(icons, ICON_BLOCKING)
  end

  -- Recurring child instances carry a 'recur' field (templates are already filtered out)
  if task.recur then
    table.insert(icons, ICON_RECURRING)
  end

  if #icons > 0 then
    return string.format("[%s]", table.concat(icons))
  end
  return ""
end

-- Placeholder rendering for the configurable task format
--------------------------------------------------------------------------------
-- The task line is built as:
--
--   <bullet> <status> <rendered task_format> `<short uuid>`
--
-- The bullet is configurable (task_bullet), the status checkbox and the short
-- uuid are not: the checkbox carries the task status and every keybinding finds
-- its task by the backticked uuid, so both are always rendered.

local PLACEHOLDER_PATTERN = "{{%s*([%w_]+)%.?([%w_]*)%s*}}"

-- Placeholders the user can put in task_format. Each entry has a `value`
-- function returning the decorated form and, where the two differ, a `raw`
-- function returning the undecorated one ({{due}} vs {{due.raw}}).
-- ctx carries the rendering options: convert_to_local, relative_dates,
-- priority_labels.
local PLACEHOLDERS = {}

PLACEHOLDERS.description = {
  value = function(task)
    return task.description or ""
  end,
}

PLACEHOLDERS.project = {
  value = function(task)
    return task.project or ""
  end,
}

PLACEHOLDERS.tags = {
  value = function(task)
    if not task.tags or #task.tags == 0 then
      return ""
    end
    return "+" .. table.concat(task.tags, " +")
  end,
  raw = function(task)
    if not task.tags or #task.tags == 0 then
      return ""
    end
    return table.concat(task.tags, " ")
  end,
}

PLACEHOLDERS.urgency = {
  value = function(task)
    return task.urgency and tostring(task.urgency) or ""
  end,
}

PLACEHOLDERS.due = {
  value = function(task, ctx)
    return format_due_date(task, ctx.convert_to_local, ctx.relative_dates)
  end,
  raw = function(task, ctx)
    if not task.due then
      return ""
    end
    return format_list_date(task.due, ctx.convert_to_local, ctx.relative_dates)
  end,
}

PLACEHOLDERS.scheduled = {
  value = function(task, ctx)
    return format_scheduled_date(task, ctx.convert_to_local, ctx.relative_dates)
  end,
  raw = function(task, ctx)
    if not task.scheduled then
      return ""
    end
    return format_list_date(task.scheduled, ctx.convert_to_local, ctx.relative_dates)
  end,
}

-- Completion is only shown for completed tasks: a deleted task also carries an
-- 'end' date, but it did not complete.
PLACEHOLDERS.completed = {
  value = function(task, ctx)
    if task.status ~= "completed" then
      return ""
    end
    local date_str = format_end_date(task, ctx.convert_to_local)
    if date_str == "" then
      return ""
    end
    return string.format("{✅%s}", date_str)
  end,
  raw = function(task, ctx)
    if task.status ~= "completed" then
      return ""
    end
    return format_end_date(task, ctx.convert_to_local)
  end,
}

PLACEHOLDERS.priority = {
  value = function(task, ctx)
    return format_priority(task, ctx.priority_labels)
  end,
  raw = function(task)
    return task.priority or ""
  end,
}

PLACEHOLDERS.blocked = {
  value = function(task)
    if task.depends and #task.depends > 0 then
      return ICON_BLOCKED
    end
    return ""
  end,
}

PLACEHOLDERS.blocking = {
  value = function(task)
    if task._reverse_deps and #task._reverse_deps > 0 then
      return ICON_BLOCKING
    end
    return ""
  end,
}

PLACEHOLDERS.recurring = {
  value = function(task)
    if task.recur then
      return ICON_RECURRING
    end
    return ""
  end,
}

-- The bracketed group of markers: [<priority><blocked><blocking><recurring>]
PLACEHOLDERS.markers = {
  value = function(task, ctx)
    return get_extra_icons(task, ctx.priority_labels)
  end,
}

-- Everything the default format shows besides the description: the completion
-- date, the scheduled and due dates, and the marker group. Scheduled is left
-- out for completed tasks, where what was planned no longer matters.
PLACEHOLDERS.icons = {
  value = function(task, ctx)
    local parts = {}

    local function add(str)
      if str and str ~= "" then
        table.insert(parts, str)
      end
    end

    add(PLACEHOLDERS.completed.value(task, ctx))
    if task.status ~= "completed" then
      add(PLACEHOLDERS.scheduled.value(task, ctx))
    end
    add(PLACEHOLDERS.due.value(task, ctx))
    add(PLACEHOLDERS.markers.value(task, ctx))

    return table.concat(parts, " ")
  end,
}

-- 'end' is Taskwarrior's own name for the completion date, kept as an alias
PLACEHOLDERS["end"] = PLACEHOLDERS.completed

-- Placeholders that are part of the line but not of the format string. Naming
-- one is a mistake worth explaining rather than silently dropping.
local FIXED_PLACEHOLDERS = {
  uid = "the short uuid is always appended at the end of the line",
  uuid = "the short uuid is always appended at the end of the line",
  short_uuid = "the short uuid is always appended at the end of the line",
  hash = "the short uuid is always appended at the end of the line",
  status = "the status checkbox is always rendered before the format",
  bullet = "the bullet is configured with task_bullet, not in task_format",
}

M.DEFAULT_TASK_FORMAT = "{{description}} {{icons}}"
M.DEFAULT_TASK_BULLET = "*"

-- Check a task_format string and return a list of problems, each { name, reason }.
-- Used by setup() to warn about typos instead of quietly rendering nothing.
function M.validate_task_format(format)
  local problems = {}

  if type(format) ~= "string" then
    table.insert(problems, { name = tostring(format), reason = "task_format must be a string" })
    return problems
  end

  for name, suffix in string.gmatch(format, PLACEHOLDER_PATTERN) do
    local entry = PLACEHOLDERS[name]
    if not entry then
      local fixed = FIXED_PLACEHOLDERS[name]
      table.insert(problems, {
        name = name,
        reason = fixed or "unknown placeholder",
      })
    elseif suffix ~= "" and suffix ~= "raw" then
      table.insert(problems, {
        name = name .. "." .. suffix,
        reason = string.format("unknown modifier '%s' (only '.raw' is supported)", suffix),
      })
    end
  end

  return problems
end

-- Render a task_format string for one task. Unknown placeholders render empty,
-- and the runs of whitespace their absence leaves behind are collapsed so a
-- task without dates does not trail spaces.
local function render_task_format(format, task, ctx)
  local rendered = string.gsub(format, PLACEHOLDER_PATTERN, function(name, suffix)
    local entry = PLACEHOLDERS[name]
    if not entry then
      return ""
    end
    -- '.raw' is accepted on every placeholder; on one that has no decoration
    -- to strip (e.g. {{project}}) it renders the same text.
    if suffix == "raw" then
      return (entry.raw or entry.value)(task, ctx) or ""
    end
    return entry.value(task, ctx) or ""
  end)

  rendered = string.gsub(rendered, "  +", " ")
  return vim.trim(rendered)
end

-- Function to format a single Taskwarrior task
-- opts is a table of rendering options:
--   convert_to_local: if true, converts UTC to local time using system date command (default true)
--   relative_dates: if true, formats due/scheduled dates as relative (e.g. "tomorrow", "2 days"),
--     and today's dates as their time (e.g. "2pm"); the end date is always an ISO day
--   priority_labels: optional map from priority value to the text shown for it
--   format: task_format template (default M.DEFAULT_TASK_FORMAT)
--   bullet: list bullet (default M.DEFAULT_TASK_BULLET)
-- The legacy positional form format_task(task, convert_to_local, use_relative,
-- priority_labels) is still accepted.
function M.format_task(task, opts, use_relative, priority_labels)
  local ctx
  if type(opts) == "table" then
    ctx = {
      convert_to_local = opts.convert_to_local,
      relative_dates = opts.relative_dates,
      priority_labels = opts.priority_labels,
      format = opts.format,
      bullet = opts.bullet,
    }
  else
    ctx = {
      convert_to_local = opts,
      relative_dates = use_relative,
      priority_labels = priority_labels,
    }
  end

  -- Default to true (convert to local time by default)
  if ctx.convert_to_local == nil then
    ctx.convert_to_local = true
  end

  local format = ctx.format
  if type(format) ~= "string" then
    format = M.DEFAULT_TASK_FORMAT
  end

  local bullet = ctx.bullet
  if type(bullet) ~= "string" then
    bullet = M.DEFAULT_TASK_BULLET
  end

  local parts = {}
  if bullet ~= "" then
    table.insert(parts, bullet)
  end
  table.insert(parts, get_status_indicator(task))

  local body = render_task_format(format, task, ctx)
  if body ~= "" then
    table.insert(parts, body)
  end

  table.insert(parts, string.format("`%s`", string.sub(task.uuid or "", 1, 8)))

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