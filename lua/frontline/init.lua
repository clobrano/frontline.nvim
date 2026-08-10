
local M = {}
local parser = require("frontline.parser")
local task_client = require("frontline.task_client")
local renderer = require("frontline.renderer")
local mappings = require("frontline.mappings")
local completion = require("frontline.completion")

-- Default configuration
local config = {
  newlines_after_tasks = 2,
  convert_dates_to_local = true, -- Convert UTC timestamps to local time using system date command (default: true)
  relative_dates = false, -- Display due/scheduled dates in relative format (e.g. "tomorrow", "2 days", "-1 week")
  workspaces = {
    -- Example configuration (string shorthand):
    -- personal = "~/.config/taskwarrior/personal/.taskrc",
    -- Example configuration (table form with per-workspace notes directory):
    -- work = { rc = "~/.config/taskwarrior/work/.taskrc", notes_directory = "~/notes/work" },
    -- Per-workspace note templates are supported too:
    -- work = { rc = "...", notes_directory = "~/notes/work", note_template = "templates/task.md" },
  },
  default_workspace = nil, -- Name of the default workspace (uses system taskwarrior if nil)
  enable_reverse_dependencies = true, -- Enable reverse dependency tracking (anchor icon and "tasks this task is blocking" view)
  require_todo_annotations_done = true, -- Prevents task completion if there are annotations starting with "TODO:" or "[ ]" (must be changed to "DONE:" or "[x]")
  notes_directory = nil, -- Fallback directory for markdown notes (nil = cwd). Overridden by per-workspace notes_directory.
  note_template = nil, -- Path to a markdown file used as the note template (nil = built-in template).
                       -- Relative paths are resolved inside notes_directory. Overridden by per-workspace note_template.
                       -- The `task:` frontmatter linking the note to Taskwarrior is always added by frontline.
  copy_task_format = "{{description}}",
  -- Text shown for each Taskwarrior priority value. Priority values are a UDA
  -- the user can redefine, so by default the value itself is displayed (e.g.
  -- "H", or "A" for uda.priority.values=A,B,C). Map any value to a symbol of
  -- the same width to show that instead, e.g. { H = "↑", M = "-", L = "↓" }.
  priority_labels = {},
  default_sort = { field = "urgency", reverse = false }, -- Default sort for all views (field: urgency|priority|due|scheduled|project)
  -- Task View window. Sizes are a fraction of the screen when <= 1 and
  -- absolute columns/rows otherwise; the window is sized to its content
  -- within these bounds.
  view = {
    min_width = 0.5,         -- narrowest the window gets
    max_width = 0.9,         -- widest the window gets
    min_height = 0.7,        -- shortest the window gets, so short tasks do not
                             -- look like they are hiding scrolled-off content
    max_height = 0.85,       -- tallest the window gets
    border = "rounded",      -- any value accepted by nvim_open_win's border
    show_urgency = true,     -- include urgency on the attribute line
    show_dependencies = true, -- include the "Blocked by" / "Blocking" sections
    annotation_dates = true, -- prefix annotations with their date
  },
  mappings = {
    toggle_done = "<leader>td",
    toggle_started = "<leader>ts",
    modify_task = "<leader>tm",
    view_task = "<leader>tv",
    add_annotation = "<leader>ta",
    -- show_annotations has no default binding: the task View (view_task) shows
    -- annotations along with the rest of the task. Set it explicitly to keep
    -- the standalone annotation list on a key of your choice.
    show_annotations = nil,
    edit_task = "<leader>te",
    show_blocking_dependencies = "<leader>tb",
    show_blocked_tasks = "<leader>tr",
    add_dependency = "<leader>tB",
    undo_task = "<leader>tu",
    create_task = "<leader>tn",
    copy_task = "<leader>tc",
    open_url = "<leader>to",
    create_note = "<leader>tj",
    add_todo_annotation = "<leader>tt",
  },
}

-- Current workspace context (tracked per buffer)
local current_workspace = nil

-- Helper: extract rc path from a workspace entry (string or table)
local function resolve_workspace_rc(entry)
  if type(entry) == "string" then
    return vim.fn.expand(entry)
  elseif type(entry) == "table" and entry.rc then
    return vim.fn.expand(entry.rc)
  end
  return nil
end

-- Helper: extract notes_directory from a workspace entry (table form only)
-- Helper function to get workspace rc file path
local function get_workspace_rc(workspace_name)
  if not workspace_name or workspace_name == "" then
    return nil
  end

  local entry = config.workspaces[workspace_name]
  if entry then
    return resolve_workspace_rc(entry)
  end

  vim.notify(string.format("Unknown workspace: %s", workspace_name), vim.log.levels.WARN)
  return nil
end

-- Helper function to set current workspace context
local function set_current_workspace(workspace_name)
  current_workspace = workspace_name
end

-- Expose function to get current workspace
function M.get_current_workspace()
  return current_workspace
end

-- Expose the resolved rc file path for the current workspace (nil for the
-- system-default Taskwarrior database)
function M.get_current_workspace_rc()
  return get_workspace_rc(current_workspace)
end

-- Expose function to get config
function M.get_config()
  return config
end

-- Expose workspace helpers for other modules
M.resolve_workspace_rc = resolve_workspace_rc

-- Expose config for completion module
M.config = config

-- Function to refresh tasks in the current buffer
local function refresh_tasks()
  local bufnr = vim.api.nvim_get_current_buf()
  local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")

  if filetype ~= "markdown" then
    return
  end

  -- Process queries one at a time, re-parsing after each update
  -- to keep line numbers accurate
  local processed_queries = {}
  local workspace_notified = false

  while true do
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local queries = parser.extract_queries(lines)

    -- Find the first query we haven't processed yet
    local query_info = nil
    for _, q in ipairs(queries) do
      local query_key = q.line_num .. ":" .. q.query
      if not processed_queries[query_key] then
        query_info = q
        processed_queries[query_key] = true
        break
      end
    end

    -- If no unprocessed queries, we're done
    if not query_info then
      break
    end

    -- Determine workspace for this query
    local workspace = query_info.workspace or config.default_workspace
    local workspace_rc = workspace and get_workspace_rc(workspace) or nil

    -- Set current workspace context
    set_current_workspace(workspace)

    -- Show workspace notification once per refresh
    if not workspace_notified then
      workspace_notified = true
      local workspace_display = workspace or "default (system)"
      vim.notify(string.format("Frontline workspace: %s", workspace_display), vim.log.levels.INFO)
    end

    local tasks, err = task_client.execute_query(query_info.query, workspace_rc)
    if err then
      -- TODO: Display error message at the bottom of the Neovim buffer (Task 7.1)
      print("Taskwarrior Error: " .. err)
      return
    end

    -- Exclude recurring task templates (status:recurring); they are internal
    -- Taskwarrior templates used to spawn child instances, not actionable items.
    local non_recurring = {}
    for _, task in ipairs(tasks) do
      if task.status ~= "recurring" then
        table.insert(non_recurring, task)
      end
    end
    tasks = non_recurring

    -- Fetch blocking tasks in a single query (if enabled)
    if config.enable_reverse_dependencies then
      local blocking_uuids, blocking_err = task_client.get_blocking_uuids(workspace_rc)
      if blocking_err then
        vim.notify("Frontline: " .. blocking_err, vim.log.levels.WARN)
      end
      for _, task in ipairs(tasks) do
        task._reverse_deps = (blocking_uuids and blocking_uuids[task.uuid]) and { true } or {}
      end
    else
      for _, task in ipairs(tasks) do
        task._reverse_deps = {}
      end
    end

    -- Determine sort config: per-view sort overrides config default
    local sort_cfg = query_info.sort or config.default_sort or { field = "urgency", reverse = false }

    -- Rank of each priority value, lowest number first. Built from Taskwarrior's
    -- own configuration rather than a hardcoded H/M/L, so renamed values sort
    -- correctly and "no priority" lands wherever the user placed it (the empty
    -- entry of uda.priority.values). Resolved on first use so views that do not
    -- sort by priority never query the config.
    local priority_rank
    local function get_priority_rank()
      if not priority_rank then
        priority_rank = {}
        for index, value in ipairs(task_client.get_priority_values(workspace_rc)) do
          if priority_rank[value] == nil then
            priority_rank[value] = index
          end
        end
      end
      return priority_rank
    end

    -- Comparator for a single sort field
    local function compare_by_field(a, b, field)
      if field == "urgency" then
        return (a.urgency or 0) > (b.urgency or 0)
      elseif field == "priority" then
        local rank = get_priority_rank()
        -- Values no longer in the configuration rank with "no priority"
        local unset = rank[""] or math.huge
        return (rank[a.priority or ""] or unset) < (rank[b.priority or ""] or unset)
      elseif field == "project" then
        return (a.project or "") < (b.project or "")
      elseif field == "due" then
        -- nil due dates sort last
        if not a.due and not b.due then return false end
        if not a.due then return false end
        if not b.due then return true end
        return a.due < b.due
      elseif field == "scheduled" then
        if not a.scheduled and not b.scheduled then return false end
        if not a.scheduled then return false end
        if not b.scheduled then return true end
        return a.scheduled < b.scheduled
      elseif field == "completed" or field == "end" then
        local a_end = a["end"]
        local b_end = b["end"]
        if not a_end and not b_end then return false end
        if not a_end then return false end
        if not b_end then return true end
        return a_end < b_end
      end
      return false
    end

    -- Sort tasks: active tasks first, then completed/deleted; within each group use sort_cfg
    table.sort(tasks, function(a, b)
      local a_done = a.status == "completed" or a.status == "deleted"
      local b_done = b.status == "completed" or b.status == "deleted"
      if a_done ~= b_done then
        return not a_done -- active tasks come first
      end
      if sort_cfg.reverse then
        return compare_by_field(b, a, sort_cfg.field)
      end
      return compare_by_field(a, b, sort_cfg.field)
    end)

    local formatted_tasks = {}
    for _, task in ipairs(tasks) do
      table.insert(formatted_tasks, renderer.format_task(task, config.convert_dates_to_local,
        config.relative_dates, config.priority_labels))
    end

    -- Add configured number of newlines after tasks
    for i = 1, config.newlines_after_tasks do
      table.insert(formatted_tasks, "")
    end

    local header_line_idx = query_info.line_num - 1 -- 0-indexed header line
    local start_replace_idx = header_line_idx + 1 -- 0-indexed, line immediately after header

    local end_replace_idx = start_replace_idx
    -- Find the end of the section - either the next header or end of file
    -- We replace everything in the section (task lines, empty lines, and other content)
    while end_replace_idx < #lines do
      local current_line_content = lines[end_replace_idx + 1] -- Lua tables are 1-indexed
      -- Stop if we encounter another markdown header (but only if it's truly a header with #)
      if string.match(current_line_content, "^#+ ") then
        break
      end
      -- Otherwise, include this line in the replacement range
      end_replace_idx = end_replace_idx + 1
    end

    -- Get fresh lines before making changes
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- nvim_buf_set_lines expects start_row (inclusive) and end_row (exclusive)
    vim.api.nvim_buf_set_lines(bufnr, start_replace_idx, end_replace_idx, false, formatted_tasks)
  end
end

-- Expose refresh function for mappings to use.
-- If task_hash is provided, the cursor is moved to the line containing that
-- hash after the refresh, so the task stays visible even if its urgency
-- changed and it was re-sorted to a different position.
-- When the task moves to a different line, the original cursor position is
-- pushed to Neovim's jumplist so the user can return with <C-o>.
function M.refresh_current_buffer(task_hash)
  -- Save position before refresh. We cannot use m' here because nvim_buf_set_lines
  -- will rewrite the section and Neovim adjusts marks within the replaced range,
  -- causing the saved line to drift. Instead we record the line explicitly and
  -- set the jumplist entry after the refresh is complete.
  local saved_pos = task_hash and vim.api.nvim_win_get_cursor(0) or nil

  refresh_tasks()

  if task_hash then
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    -- Task lines carry the hash in backticks, e.g. * [ ] Description `a2f1c3d8`
    local search_str = "`" .. task_hash .. "`"
    for lnum, line in ipairs(lines) do
      if line:find(search_str, 1, true) then
        if saved_pos and lnum ~= saved_pos[1] then
          -- Task moved: pin the original line into the jumplist by momentarily
          -- placing the cursor there and calling m'. Neovim does not render
          -- between synchronous API calls so there is no visible flicker.
          local pinned_line = math.min(saved_pos[1], #lines)
          vim.api.nvim_win_set_cursor(0, { pinned_line, saved_pos[2] })
          vim.cmd("normal! m'")
        end
        vim.api.nvim_win_set_cursor(0, { lnum, 0 })
        break
      end
    end
  end
end

function M.setup(opts)
  opts = opts or {}

  -- Merge user config with defaults
  config = vim.tbl_deep_extend("force", config, opts)

  -- <leader>ta now adds an annotation instead of listing them. Warn users whose
  -- config still binds show_annotations to the same key, where their explicit
  -- binding silently shadows add_annotation.
  if config.mappings.show_annotations
    and config.mappings.show_annotations == config.mappings.add_annotation then
    vim.notify(string.format(
      "Frontline: mappings.show_annotations and mappings.add_annotation are both %s. " ..
      "show_annotations wins; annotations are now part of the task View (%s).",
      config.mappings.show_annotations, config.mappings.view_task or "view_task"),
      vim.log.levels.WARN)
  end

  -- Update the exposed config reference so completion module gets the merged config
  M.config = config

  -- Pass config to mappings module
  mappings.set_config(config)

  -- Initialize completion module
  completion.setup()

  -- Autocommands for refreshing task lists
  vim.api.nvim_create_autocmd({"BufReadPost", "BufWritePost"}, {
    pattern = "*.md", -- Only apply to Markdown files for now
    callback = refresh_tasks,
    group = vim.api.nvim_create_augroup("FrontlineRefresh", { clear = true }),
  })

  -- Placeholder command for manual refresh
  vim.api.nvim_create_user_command("FrontlineRefresh", function()
    refresh_tasks()
    print("Frontline: Manual refresh triggered for " .. vim.fn.bufname())
  end, {
    desc = "Manually refresh Frontline tasks in the current buffer",
  })

  -- Setup keybindings for task interactions (only in markdown files)
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "markdown",
    callback = function(args)
      local bufnr = args.buf
      local opts_mapping = { noremap = true, silent = true, buffer = bufnr }

      -- Toggle task done/undone
      if config.mappings.toggle_done then
        vim.keymap.set("n", config.mappings.toggle_done, mappings.toggle_done,
          vim.tbl_extend("force", opts_mapping, { desc = "Toggle task done/undone" }))
      end

      -- Toggle task started/unstarted
      if config.mappings.toggle_started then
        vim.keymap.set("n", config.mappings.toggle_started, mappings.toggle_started,
          vim.tbl_extend("force", opts_mapping, { desc = "Toggle task started/unstarted" }))
      end

      -- Modify task
      if config.mappings.modify_task then
        vim.keymap.set("n", config.mappings.modify_task, mappings.modify_task,
          vim.tbl_extend("force", opts_mapping, { desc = "Modify task" }))
      end

      -- View task details (description, status, dates, tags, annotations, dependencies)
      if config.mappings.view_task then
        vim.keymap.set("n", config.mappings.view_task, require("frontline.view").open,
          vim.tbl_extend("force", opts_mapping, { desc = "View task details" }))
      end

      -- Add annotation
      if config.mappings.add_annotation then
        vim.keymap.set("n", config.mappings.add_annotation, mappings.add_annotation,
          vim.tbl_extend("force", opts_mapping, { desc = "Add task annotation" }))
      end

      -- Show annotations only (no default binding; registered last so an
      -- explicit user binding wins over the defaults above)
      if config.mappings.show_annotations then
        vim.keymap.set("n", config.mappings.show_annotations, mappings.show_annotations,
          vim.tbl_extend("force", opts_mapping, { desc = "Show task annotations" }))
      end

      -- Edit task
      if config.mappings.edit_task then
        vim.keymap.set("n", config.mappings.edit_task, mappings.edit_task,
          vim.tbl_extend("force", opts_mapping, { desc = "Edit task in Taskwarrior editor" }))
      end

      -- Show blocking dependencies
      if config.mappings.show_blocking_dependencies then
        vim.keymap.set("n", config.mappings.show_blocking_dependencies, mappings.show_blocking_dependencies,
          vim.tbl_extend("force", opts_mapping, { desc = "Show task blocking dependencies" }))
      end

      -- Show tasks blocked by this task (reverse dependencies, always available)
      if config.mappings.show_blocked_tasks then
        vim.keymap.set("n", config.mappings.show_blocked_tasks, mappings.show_blocked_tasks,
          vim.tbl_extend("force", opts_mapping, { desc = "Show tasks blocked by this task" }))
      end

      -- Add task as dependency
      if config.mappings.add_dependency then
        vim.keymap.set("n", config.mappings.add_dependency, mappings.add_task_as_dependency,
          vim.tbl_extend("force", opts_mapping, { desc = "Add new task as dependency" }))
      end

      -- Undo task
      if config.mappings.undo_task then
        vim.keymap.set("n", config.mappings.undo_task, mappings.undo_task,
          vim.tbl_extend("force", opts_mapping, { desc = "Undo last action on task" }))
      end

      -- Create new task
      if config.mappings.create_task then
        vim.keymap.set("n", config.mappings.create_task, mappings.create_new_task,
          vim.tbl_extend("force", opts_mapping, { desc = "Create new task with smart pre-fill" }))
      end

      -- Copy task description and short UUID
      if config.mappings.copy_task then
        vim.keymap.set("n", config.mappings.copy_task, mappings.copy_task,
          vim.tbl_extend("force", opts_mapping, { desc = "Copy task description and short UUID to clipboard" }))
      end

      -- Open URL from task annotations
      if config.mappings.open_url then
        vim.keymap.set("n", config.mappings.open_url, mappings.open_url,
          vim.tbl_extend("force", opts_mapping, { desc = "Open URL from task annotations" }))
      end

      -- Create markdown note from task
      if config.mappings.create_note then
        vim.keymap.set("n", config.mappings.create_note, mappings.create_note,
          vim.tbl_extend("force", opts_mapping, { desc = "Create markdown note from task" }))
      end

      -- Add TODO annotation
      if config.mappings.add_todo_annotation then
        vim.keymap.set("n", config.mappings.add_todo_annotation, mappings.add_todo_annotation,
          vim.tbl_extend("force", opts_mapping, { desc = "Add TODO annotation to task" }))
      end
    end,
    group = vim.api.nvim_create_augroup("FrontlineMappings", { clear = true }),
  })
end

return M
