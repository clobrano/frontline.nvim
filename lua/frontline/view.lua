-- Task View: a compact, read-mostly summary of a single task shown in a
-- floating window. Layout is produced by the pure M.render function so it can
-- be unit tested without any UI.
local M = {}

local renderer = require("frontline.renderer")
local task_client = require("frontline.task_client")

local ICON_SCHEDULED = "⏱️"
local ICON_DUE = "⏰"
local ICON_END = "✅"

-- Hard floor, so a pathologically small screen still produces a usable window
local ABSOLUTE_MIN_WIDTH = 20

-- Default view options, merged with config.view by the caller.
-- Sizes are a fraction of the screen when <= 1, and absolute columns/rows
-- otherwise. The window is sized to its content within these bounds.
local default_view_config = {
  min_width = 0.5,
  max_width = 0.9,
  min_height = 0.7,
  max_height = 0.85,
  border = "rounded",
  show_urgency = true,
  show_dependencies = true,
  annotation_dates = true,
}

M.default_config = default_view_config

-- Highlight groups, one per role so a colorscheme or user config can restyle
-- any single element. All are defined with default = true, so an existing
-- definition always wins.
local highlight_links = {
  FrontlineViewDescription = "Title",
  FrontlineViewHash = "Comment",
  FrontlineViewSeparator = "Comment",
  FrontlineViewPriority = "Statement",
  FrontlineViewProject = "Directory",
  FrontlineViewTags = "Special",
  FrontlineViewRecur = "Special",
  FrontlineViewWaiting = "Comment",
  FrontlineViewUrgency = "Comment",
  FrontlineViewOverdue = "WarningMsg",
  FrontlineViewSection = "Title",
  FrontlineViewTodo = "WarningMsg",
  FrontlineViewDone = "Comment",
  FrontlineViewAnnotationDate = "Comment",
  FrontlineViewDepOpen = "Normal",
  FrontlineViewDepDone = "Comment",
}

function M.setup_highlights()
  for group, link in pairs(highlight_links) do
    vim.api.nvim_set_hl(0, group, { link = link, default = true })
  end
end

-- Resolve a size that may be expressed as a fraction of the available space
local function resolve_dimension(value, total)
  if not value then
    return nil
  end
  if value <= 1 then
    return math.floor(value * total)
  end
  return math.floor(value)
end

M.resolve_dimension = resolve_dimension

--------------------------------------------------------------------------------
-- Annotation helpers (pure)
--------------------------------------------------------------------------------

-- Classify an annotation as an open TODO, a completed one, or a plain note.
-- Recognises both the "TODO:"/"DONE:" prefixes and markdown checkboxes.
function M.annotation_state(description)
  description = description or ""
  if string.match(description:upper(), "^TODO:") then
    return "todo"
  end
  if string.match(description:upper(), "^DONE:") then
    return "done"
  end
  if string.match(description, "^%[ %]") then
    return "todo"
  end
  if string.match(description, "^%[[xX]%]") then
    return "done"
  end
  return "plain"
end

-- Flip a checkable annotation between its open and completed form, preserving
-- the rest of the text verbatim. Returns nil for plain annotations.
function M.toggle_annotation_text(description)
  description = description or ""

  local prefix = description:sub(1, 5)
  if prefix:upper() == "TODO:" then
    return "DONE:" .. description:sub(6)
  end
  if prefix:upper() == "DONE:" then
    return "TODO:" .. description:sub(6)
  end
  if description:match("^%[ %]") then
    return "[x]" .. description:sub(4)
  end
  if description:match("^%[[xX]%]") then
    return "[ ]" .. description:sub(4)
  end
  return nil
end

local annotation_markers = {
  todo = "☐",
  done = "☑",
  plain = "•",
}

--------------------------------------------------------------------------------
-- Rendering (pure)
--------------------------------------------------------------------------------

local function display_width(str)
  if vim and vim.fn and vim.fn.strdisplaywidth then
    return vim.fn.strdisplaywidth(str)
  end
  return #str
end

local priority_icons = { H = "🔴", M = "🟠", L = "🟡" }

-- Format a date as "<icon> <absolute> (<relative>)", omitting the relative part
-- when it cannot be computed.
local function format_date_value(iso_date, icon, convert_to_local)
  local absolute = renderer.parse_iso_date(iso_date, convert_to_local)
  local relative = renderer.format_relative_date(iso_date)
  local value = icon ~= "" and string.format("%s %s", icon, absolute) or absolute
  if relative then
    value = string.format("%s (%s)", value, relative)
  end
  return value
end

-- A line spec is { left, right, hl, meta, right_hl }. Right-hand text (task
-- hashes) is right-aligned once the final width is known, so its highlight is
-- resolved at composition time rather than here. Offsets in hl are relative to
-- the start of the line, and `to = -1` means "to the end of the left text".
local function line_spec(left, right, hl, meta, right_hl)
  return { left = left, right = right, hl = hl, meta = meta, right_hl = right_hl }
end

-- Join { text = , hl = } segments into one line, tracking the byte offset of
-- each segment so its highlight lands on the right columns.
local function join_segments(segments, separator)
  local parts = {}
  local highlights = {}
  local offset = 0

  for i, segment in ipairs(segments) do
    if i > 1 then
      -- Dim the separators so the fields themselves stand out
      table.insert(highlights,
        { group = "FrontlineViewSeparator", from = offset, to = offset + #separator })
      offset = offset + #separator
    end
    if segment.hl then
      table.insert(highlights, { group = segment.hl, from = offset, to = offset + #segment.text })
    end
    offset = offset + #segment.text
    table.insert(parts, segment.text)
  end

  return table.concat(parts, separator), highlights
end

local function dep_specs(specs, title, deps)
  if #deps == 0 then
    return
  end

  local open_count = 0
  for _, dep in ipairs(deps) do
    if dep.status ~= "completed" and dep.status ~= "deleted" then
      open_count = open_count + 1
    end
  end

  local header = #deps == open_count
    and string.format("%s (%d)", title, #deps)
    or string.format("%s (%d · %d open)", title, #deps, open_count)

  table.insert(specs, line_spec(header, nil, { { group = "FrontlineViewSection", from = 0, to = -1 } }))

  for _, dep in ipairs(deps) do
    local is_open = dep.status ~= "completed" and dep.status ~= "deleted"
    local marker = is_open and "☐" or "☑"
    local left = string.format("  %s %s", marker, dep.description or "")
    table.insert(specs, line_spec(
      left,
      string.format("`%s`", dep.short_hash),
      { { group = is_open and "FrontlineViewDepOpen" or "FrontlineViewDepDone", from = 0, to = -1 } },
      { kind = "dependency", uuid = dep.uuid },
      "FrontlineViewHash"
    ))
  end
end

-- Build the View for a task.
--   data: { task = <taskwarrior task>, forward_deps = {}, reverse_deps = {} }
--   opts: view config plus convert_dates_to_local
-- Returns lines, highlights, line_meta. Highlights are 0-indexed
-- { line, col_start, col_end, group } entries; line_meta maps a 1-indexed line
-- number to the object rendered there, for the interactive keymaps.
function M.render(data, opts)
  opts = vim.tbl_extend("force", default_view_config, opts or {})
  local task = data.task or {}
  local convert_to_local = opts.convert_dates_to_local
  if convert_to_local == nil then
    convert_to_local = true
  end

  local specs = {}

  -- Title: same status marker and hash as the buffer line, so the View reads as
  -- a zoom-in on the task you were standing on.
  local description = task.description or ""
  if task.status == "completed" and task["end"] then
    local end_date = renderer.parse_iso_date(task["end"], convert_to_local)
    end_date = string.match(end_date, "^(%d%d%d%d%-%d%d%-%d%d)") or end_date
    description = string.format("%s {%s%s}", description, ICON_END, end_date)
  end

  -- The status marker on the title line already says pending/started/completed,
  -- so the attribute line does not repeat it.
  table.insert(specs, line_spec(
    string.format("%s %s", renderer.get_status_indicator(task), description),
    string.format("`%s`", string.sub(task.uuid or "", 1, 8)),
    { { group = "FrontlineViewDescription", from = 0, to = -1 } },
    nil,
    "FrontlineViewHash"
  ))

  -- Attributes, all on one line and each present only when set
  local attrs = {}
  if task.priority and priority_icons[task.priority] then
    table.insert(attrs, {
      text = string.format("%s %s", priority_icons[task.priority], task.priority),
      hl = "FrontlineViewPriority",
    })
  end
  if task.status == "waiting" then
    table.insert(attrs, { text = "waiting", hl = "FrontlineViewWaiting" })
  end
  if task.project and task.project ~= "" then
    table.insert(attrs, { text = task.project, hl = "FrontlineViewProject" })
  end
  if task.tags and #task.tags > 0 then
    local tags = {}
    for _, tag in ipairs(task.tags) do
      table.insert(tags, "+" .. tag)
    end
    table.insert(attrs, { text = table.concat(tags, " "), hl = "FrontlineViewTags" })
  end
  if task.recur then
    table.insert(attrs, { text = string.format("🔁 %s", task.recur), hl = "FrontlineViewRecur" })
  end
  if opts.show_urgency and task.urgency then
    table.insert(attrs, {
      text = string.format("urgency %.1f", task.urgency),
      hl = "FrontlineViewUrgency",
    })
  end

  if #attrs > 0 then
    local line, hl = join_segments(attrs, " · ")
    table.insert(specs, line_spec(line, nil, hl))
  end

  -- Dates, all on one line and each present only when set
  local dates = {}
  if task.wait then
    table.insert(dates, { text = "wait " .. format_date_value(task.wait, "", convert_to_local) })
  end
  if task.scheduled then
    table.insert(dates, { text = format_date_value(task.scheduled, ICON_SCHEDULED, convert_to_local) })
  end
  if task.due then
    local diff = renderer.date_diff_days(task.due)
    local overdue = diff ~= nil and diff < 0 and task.status ~= "completed"
    table.insert(dates, {
      text = format_date_value(task.due, ICON_DUE, convert_to_local),
      hl = overdue and "FrontlineViewOverdue" or nil,
    })
  end
  if task["until"] then
    table.insert(dates, { text = "until " .. format_date_value(task["until"], "", convert_to_local) })
  end

  if #dates > 0 then
    local line, hl = join_segments(dates, " · ")
    table.insert(specs, line_spec(line, nil, hl))
  end

  -- Annotations
  local annotations = task.annotations or {}
  if #annotations > 0 then
    table.insert(specs, line_spec(""))
    table.insert(specs, line_spec(
      string.format("Annotations (%d)", #annotations),
      nil,
      { { group = "FrontlineViewSection", from = 0, to = -1 } }
    ))

    for i, annotation in ipairs(annotations) do
      local text = annotation.description or ""
      local state = M.annotation_state(text)
      local marker = annotation_markers[state]

      local date_prefix = ""
      if opts.annotation_dates and annotation.entry then
        local date_str = renderer.parse_iso_date(annotation.entry, convert_to_local)
        date_str = string.match(date_str, "^(%d%d%d%d%-%d%d%-%d%d)") or date_str
        date_prefix = date_str .. "  "
      end

      local left = string.format("  %s %s%s", marker, date_prefix, text)
      local hl = {}
      if date_prefix ~= "" then
        local from = #string.format("  %s ", marker)
        table.insert(hl, { group = "FrontlineViewAnnotationDate", from = from, to = from + #date_prefix })
      end
      if state == "todo" then
        table.insert(hl, { group = "FrontlineViewTodo", from = 2, to = 2 + #marker })
      elseif state == "done" then
        table.insert(hl, { group = "FrontlineViewDone", from = 2, to = -1 })
      end

      table.insert(specs, line_spec(left, nil, hl, {
        kind = "annotation",
        index = i,
        description = text,
        state = state,
      }))
    end
  end

  -- Dependencies: the two sections sit together as one block
  local forward_deps = data.forward_deps or {}
  local reverse_deps = data.reverse_deps or {}
  if opts.show_dependencies and (#forward_deps > 0 or #reverse_deps > 0) then
    table.insert(specs, line_spec(""))
    dep_specs(specs, "Blocked by", forward_deps)
    dep_specs(specs, "Blocking", reverse_deps)
  end

  -- Compose: right-align the trailing hashes against the widest line. The
  -- window is sized to its content, so the alignment column and the window
  -- width are the same number.
  local available = math.max(ABSOLUTE_MIN_WIDTH, (vim.o.columns or 80) - 4)
  local min_width = resolve_dimension(opts.min_width, available) or ABSOLUTE_MIN_WIDTH
  local max_width = resolve_dimension(opts.max_width, available) or available

  local width = 0
  for _, spec in ipairs(specs) do
    local w = display_width(spec.left)
    if spec.right then
      w = w + 2 + display_width(spec.right)
    end
    if w > width then
      width = w
    end
  end

  width = math.min(width, max_width)
  width = math.max(width, min_width, ABSOLUTE_MIN_WIDTH)
  width = math.min(width, available)

  local lines = {}
  local highlights = {}
  local line_meta = {}

  for _, spec in ipairs(specs) do
    local line = spec.left
    if spec.right then
      local pad = width - display_width(spec.left) - display_width(spec.right)
      line = line .. string.rep(" ", math.max(2, pad)) .. spec.right
    end
    table.insert(lines, line)

    local lnum = #lines
    for _, hl in ipairs(spec.hl or {}) do
      table.insert(highlights, {
        line = lnum - 1,
        col_start = hl.from,
        col_end = hl.to == -1 and #spec.left or math.min(hl.to, #spec.left),
        group = hl.group,
      })
    end
    if spec.right and spec.right_hl then
      table.insert(highlights, {
        line = lnum - 1,
        col_start = #line - #spec.right,
        col_end = #line,
        group = spec.right_hl,
      })
    end
    if spec.meta then
      line_meta[lnum] = spec.meta
    end
  end

  return lines, highlights, line_meta, width
end

--------------------------------------------------------------------------------
-- Data collection
--------------------------------------------------------------------------------

local function short(uuid)
  return string.sub(uuid or "", 1, 8)
end

-- Fetch a task plus the descriptions of its forward and reverse dependencies.
-- Costs at most three Taskwarrior invocations regardless of dependency count.
function M.collect(hash, workspace_rc, enable_reverse_dependencies)
  local tasks, err = task_client.execute_query(hash, workspace_rc)
  if err then
    return nil, err
  end
  if not tasks or #tasks == 0 then
    return nil, string.format("No task found for hash %s", hash)
  end

  local task = tasks[1]
  local forward_deps = {}

  if task.depends and #task.depends > 0 then
    local dep_tasks = task_client.execute_query(table.concat(task.depends, ","), workspace_rc) or {}
    local by_uuid = {}
    for _, dep_task in ipairs(dep_tasks) do
      by_uuid[dep_task.uuid] = dep_task
    end
    for _, dep_uuid in ipairs(task.depends) do
      local dep_task = by_uuid[dep_uuid]
      table.insert(forward_deps, {
        uuid = dep_uuid,
        short_hash = short(dep_uuid),
        description = dep_task and dep_task.description or "Unknown task",
        status = dep_task and dep_task.status or nil,
      })
    end
  end

  local reverse_deps = {}
  if enable_reverse_dependencies then
    local rev_tasks = task_client.get_reverse_dependencies(task.uuid, workspace_rc) or {}
    for _, rev_task in ipairs(rev_tasks) do
      table.insert(reverse_deps, {
        uuid = rev_task.uuid,
        short_hash = short(rev_task.uuid),
        description = rev_task.description or "Unknown task",
        status = rev_task.status,
      })
    end
  end

  return { task = task, forward_deps = forward_deps, reverse_deps = reverse_deps }
end

--------------------------------------------------------------------------------
-- Floating window
--------------------------------------------------------------------------------

-- Per-window state: which task is shown, where it came from, and the drill-down
-- history so <BS> can walk back out of dependencies.
local state = {}

-- Every action except q/<Esc> leaves the View open and re-renders it, so they
-- can be repeated without reopening the window. 'e' is the one that has to step
-- aside for a full window, and reopens the View once the editor is done.
local KEYMAP_HELP = {
  { "q, <Esc>", "close the view" },
  { "a", "add an annotation" },
  { "x", "toggle TODO/DONE on the annotation under the cursor" },
  { "d", "toggle done" },
  { "s", "toggle started" },
  { "e", "edit the task in Taskwarrior's editor" },
  { "<CR>", "open the annotation's URL or file, or drill into a dependency" },
  { "<BS>", "go back to the previous task" },
  { "?", "show this help" },
}

local function get_state(bufnr)
  return state[bufnr]
end

local function close_view(bufnr)
  local st = get_state(bufnr)
  state[bufnr] = nil
  if st and st.win and vim.api.nvim_win_is_valid(st.win) then
    vim.api.nvim_win_close(st.win, true)
  end
end

-- Refresh the markdown buffer the View was opened from, without stealing the
-- cursor from the floating window.
local function refresh_origin(st)
  if st.origin_win and vim.api.nvim_win_is_valid(st.origin_win) then
    -- Task lines carry the 8 character hash, so a full UUID never matches
    vim.api.nvim_win_call(st.origin_win, function()
      require("frontline").refresh_current_buffer(string.sub(st.hash, 1, 8))
    end)
  end
end

local function set_buffer_content(bufnr, st)
  local frontline = require("frontline")
  local cfg = frontline.get_config() or {}
  local opts = vim.tbl_extend("force", cfg.view or {}, {
    convert_dates_to_local = cfg.convert_dates_to_local,
  })

  local data, err = M.collect(st.hash, st.workspace_rc, cfg.enable_reverse_dependencies)
  if not data then
    vim.notify(err or "Failed to load task", vim.log.levels.ERROR)
    return false
  end

  st.data = data

  local lines, highlights, line_meta, width = M.render(data, opts)
  st.line_meta = line_meta

  vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(bufnr, st.ns, 0, -1)
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(bufnr, st.ns, hl.group, hl.line, hl.col_start, hl.col_end)
  end
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)

  return true, lines, width
end

-- Centre a window of the given content size on the editor, clamped to the
-- configured maximums.
local function geometry(line_count, width, view_cfg)
  -- render already clamped the width to the configured bounds
  local win_width = math.max(ABSOLUTE_MIN_WIDTH, math.min(width, vim.o.columns - 4))

  -- Leave two rows for the border and one for the command line
  local available_height = math.max(3, vim.o.lines - 3)
  local max_height = math.min(available_height,
    resolve_dimension(view_cfg.max_height, available_height) or available_height)
  local min_height = math.min(max_height,
    resolve_dimension(view_cfg.min_height, available_height) or 1)

  local height = math.max(min_height, math.min(line_count, max_height))

  return {
    relative = "editor",
    width = win_width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.floor((vim.o.columns - win_width) / 2),
  }
end

local function resize(st, lines, width)
  if not (st.win and vim.api.nvim_win_is_valid(st.win)) then
    return
  end

  local cfg = require("frontline").get_config() or {}
  local view_cfg = vim.tbl_extend("force", default_view_config, cfg.view or {})

  -- Re-send the full config: a partial one drops the border and title.
  vim.api.nvim_win_set_config(st.win,
    vim.tbl_extend("force", st.win_opts, geometry(#lines, width, view_cfg)))
end

local function rerender(bufnr)
  local st = get_state(bufnr)
  if not st then
    return
  end
  local ok, lines, width = set_buffer_content(bufnr, st)
  if ok then
    resize(st, lines, width)
  end
end

-- Add an annotation from inside the View, then refresh both the View and the
-- markdown buffer behind it.
local function annotate(bufnr)
  local st = get_state(bufnr)
  if not st then
    return
  end

  vim.ui.input({ prompt = "Annotation text: " }, function(input)
    if not input or input == "" then
      vim.notify("Annotation cancelled", vim.log.levels.INFO)
      return
    end

    local escaped = input:gsub("'", "'\\''")
    local ok, output = task_client.run_command(
      string.format("%s annotate '%s'", st.hash, escaped), st.workspace_rc)

    if not ok then
      vim.notify("Failed to add annotation: " .. output, vim.log.levels.ERROR)
      return
    end

    rerender(bufnr)
    refresh_origin(st)
  end)
end

-- Toggle the TODO/DONE state of the annotation under the cursor.
-- Taskwarrior has no "edit annotation" command, so this denotates the old text
-- and annotates the new one; the annotation's timestamp is reset as a result.
local function toggle_annotation(bufnr)
  local st = get_state(bufnr)
  if not st then
    return
  end

  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local meta = st.line_meta and st.line_meta[lnum]

  if not meta or meta.kind ~= "annotation" then
    vim.notify("No annotation on this line", vim.log.levels.INFO)
    return
  end

  local new_text = M.toggle_annotation_text(meta.description)
  if not new_text then
    vim.notify("This annotation is not a TODO or DONE item", vim.log.levels.INFO)
    return
  end

  local escaped_old = meta.description:gsub("'", "'\\''")
  local ok, output = task_client.run_command(
    string.format("rc.confirmation=off %s denotate '%s'", st.hash, escaped_old), st.workspace_rc)
  if not ok then
    vim.notify("Failed to remove old annotation: " .. output, vim.log.levels.ERROR)
    return
  end

  local escaped_new = new_text:gsub("'", "'\\''")
  ok, output = task_client.run_command(
    string.format("%s annotate '%s'", st.hash, escaped_new), st.workspace_rc)
  if not ok then
    vim.notify("Annotation removed but re-adding failed: " .. output, vim.log.levels.ERROR)
    return
  end

  vim.notify(string.format("Annotation updated: %s", new_text), vim.log.levels.INFO)
  rerender(bufnr)
  refresh_origin(st)
end

-- <CR>: open an annotation's resources, or drill into a dependency.
local function activate(bufnr)
  local st = get_state(bufnr)
  if not st then
    return
  end

  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local meta = st.line_meta and st.line_meta[lnum]

  if not meta then
    return
  end

  if meta.kind == "annotation" then
    -- Files open in the window the View came from; a floating window is no
    -- place to load a buffer into
    local opened = require("frontline.mappings")
      .open_resources_in_text(meta.description, st.origin_win)
    if not opened then
      vim.notify("No URL or file path in this annotation", vim.log.levels.INFO)
    end
  elseif meta.kind == "dependency" then
    table.insert(st.history, st.hash)
    st.hash = meta.uuid
    rerender(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
  end
end

local function go_back(bufnr)
  local st = get_state(bufnr)
  if not st or #st.history == 0 then
    return
  end
  st.hash = table.remove(st.history)
  rerender(bufnr)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
end

-- Toggle done/started on the task the View is showing and stay open, so several
-- actions can be chained. The callback may fire long after this returns, when
-- the user has answered a dependency prompt.
local function toggle_task(bufnr, fn_name)
  local st = get_state(bufnr)
  if not st then
    return
  end

  require("frontline.mappings")[fn_name](st.hash, function()
    -- The View may have been closed while a prompt was open
    if not (vim.api.nvim_buf_is_valid(bufnr) and state[bufnr]) then
      return
    end
    rerender(bufnr)
    refresh_origin(st)
  end)
end

-- Hand the task over to Taskwarrior's interactive editor, the same one the
-- edit_task mapping opens. The editor runs in a terminal split, which a floating
-- window cannot host, so the View closes, the editor takes over the window the
-- View was opened from, and the View comes back on the same task afterwards.
local function edit_task(bufnr)
  local st = get_state(bufnr)
  if not st then
    return
  end

  local hash = st.hash
  local workspace_rc = st.workspace_rc
  local origin_win = st.origin_win
  local history = st.history

  close_view(bufnr)

  if origin_win and vim.api.nvim_win_is_valid(origin_win) then
    vim.api.nvim_set_current_win(origin_win)
  end

  require("frontline.mappings").edit_task(hash, function(success)
    -- The editor's window has just closed, so make sure the markdown buffer is
    -- current again before it gets refreshed and the View reopened over it.
    if origin_win and vim.api.nvim_win_is_valid(origin_win) then
      vim.api.nvim_set_current_win(origin_win)
    end

    if success then
      -- Task lines carry the 8 character hash, so a full UUID never matches
      require("frontline").refresh_current_buffer(string.sub(hash, 1, 8))
    end

    M.open_hash(hash, workspace_rc, history)
  end)
end

local function show_help()
  local chunks = { { "Task View keys:\n", "Title" } }
  for _, entry in ipairs(KEYMAP_HELP) do
    table.insert(chunks, { string.format("  %-10s %s\n", entry[1], entry[2]), "Normal" })
  end
  vim.api.nvim_echo(chunks, false, {})
end

local function setup_keymaps(bufnr)
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = bufnr, nowait = true, silent = true, desc = desc })
  end

  map("q", function() close_view(bufnr) end, "Close task view")
  map("<Esc>", function() close_view(bufnr) end, "Close task view")
  map("a", function() annotate(bufnr) end, "Add annotation")
  map("x", function() toggle_annotation(bufnr) end, "Toggle TODO/DONE annotation")
  map("<CR>", function() activate(bufnr) end, "Open annotation resource or dependency")
  map("<BS>", function() go_back(bufnr) end, "Back to previous task")
  map("d", function() toggle_task(bufnr, "toggle_done") end, "Toggle task done")
  map("s", function() toggle_task(bufnr, "toggle_started") end, "Toggle task started")
  map("e", function() edit_task(bufnr) end, "Edit task in Taskwarrior's editor")
  map("?", show_help, "Show task view keys")
end

-- Open the View for a task hash. history is optional and only passed when the
-- View reopens itself, so <BS> still walks back out of the dependencies the user
-- drilled into before editing.
function M.open_hash(hash, workspace_rc, history)
  local frontline = require("frontline")
  local cfg = frontline.get_config() or {}
  local view_cfg = vim.tbl_extend("force", default_view_config, cfg.view or {})

  M.setup_highlights()

  local bufnr = vim.api.nvim_create_buf(false, true)
  local st = {
    hash = hash,
    workspace_rc = workspace_rc,
    origin_win = vim.api.nvim_get_current_win(),
    history = history or {},
    ns = vim.api.nvim_create_namespace("frontline_view"),
  }
  state[bufnr] = st

  local ok, lines, width = set_buffer_content(bufnr, st)
  if not ok then
    state[bufnr] = nil
    vim.api.nvim_buf_delete(bufnr, { force = true })
    return
  end

  local base_opts = vim.tbl_extend("force", geometry(#lines, width, view_cfg), {
    style = "minimal",
    border = view_cfg.border,
  })

  -- Titles need Neovim 0.9, footers 0.10. Try the richest window first and drop
  -- back one decoration at a time rather than losing both at once.
  local candidates = {
    vim.tbl_extend("force", base_opts, {
      title = " Task ",
      title_pos = "left",
      footer = " q close · a annotate · x toggle · e edit · ? keys ",
      footer_pos = "left",
    }),
    vim.tbl_extend("force", base_opts, { title = " Task ", title_pos = "left" }),
    base_opts,
  }

  local win
  for _, candidate in ipairs(candidates) do
    local created, result = pcall(vim.api.nvim_open_win, bufnr, true, candidate)
    if created then
      win = result
      st.win_opts = candidate
      break
    end
  end

  if not win then
    vim.notify("Frontline: failed to open the task View window", vim.log.levels.ERROR)
    state[bufnr] = nil
    vim.api.nvim_buf_delete(bufnr, { force = true })
    return
  end

  st.win = win

  vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(bufnr, "filetype", "frontline-view")
  vim.api.nvim_win_set_option(win, "wrap", true)
  vim.api.nvim_win_set_option(win, "breakindent", true)
  vim.api.nvim_win_set_option(win, "showbreak", "  ")
  vim.api.nvim_win_set_option(win, "cursorline", true)

  setup_keymaps(bufnr)

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    once = true,
    callback = function()
      state[bufnr] = nil
    end,
  })
end

-- Entry point for the keybinding: view the task on the current line.
function M.open()
  local mappings = require("frontline.mappings")
  local hash = mappings.get_task_hash_under_cursor()
  if not hash then
    return
  end
  M.open_hash(hash, require("frontline").get_current_workspace_rc())
end

return M
