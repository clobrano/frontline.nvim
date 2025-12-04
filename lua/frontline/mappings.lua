local M = {}

-- Store reference to config (set by init.lua)
local config = { enable_reverse_dependencies = true }

-- Function to set config from init.lua
function M.set_config(new_config)
  config = new_config
end

-- Extract task hash from the current line
-- Expected format: * [status] description ... (hash)
function M.get_task_hash_under_cursor()
  local line = vim.api.nvim_get_current_line()

  -- Match the hash pattern at the end: (xxxxxxxx)
  local hash = string.match(line, "%(([a-f0-9]+)%)%s*$")

  if not hash then
    vim.notify("No task hash found on current line", vim.log.levels.WARN)
    return nil
  end

  return hash
end

-- Helper function to get workspace rc file path
local function get_workspace_rc()
  local frontline = require("frontline")
  local workspace = frontline.get_current_workspace()

  if not workspace then
    return nil
  end

  -- Access the config to get workspace rc path
  local config = frontline.get_config()
  if config and config.workspaces and config.workspaces[workspace] then
    return vim.fn.expand(config.workspaces[workspace])
  end

  return nil
end

-- Helper function to parse workspace from input string and return workspace, cleaned input
local function parse_workspace_from_input(input)
  if not input then
    return nil, input
  end

  -- Extract workspace from input (e.g., @personal, @work)
  local workspace = string.match(input, "@([%w_%-]+)")

  if not workspace then
    return nil, input
  end

  -- Remove workspace from input string
  local cleaned_input = string.gsub(input, "%s*@[%w_%-]+%s*", " ")
  cleaned_input = string.gsub(cleaned_input, "^%s+", "") -- trim leading spaces
  cleaned_input = string.gsub(cleaned_input, "%s+$", "") -- trim trailing spaces

  return workspace, cleaned_input
end

-- Helper function to get workspace rc path, with optional override
local function get_workspace_rc_with_override(workspace_override)
  local frontline = require("frontline")
  local config = frontline.get_config()

  -- Use override if provided, otherwise use current workspace
  local workspace = workspace_override or frontline.get_current_workspace()

  if not workspace then
    return nil
  end

  if config and config.workspaces and config.workspaces[workspace] then
    return vim.fn.expand(config.workspaces[workspace])
  end

  if workspace_override then
    vim.notify(string.format("Unknown workspace: %s", workspace), vim.log.levels.WARN)
  end

  return nil
end

-- Helper function to build task command with optional rc file
local function build_task_command(task_args, workspace_override)
  local workspace_rc = get_workspace_rc_with_override(workspace_override)

  if workspace_rc and workspace_rc ~= "" then
    local escaped_rc = string.gsub(workspace_rc, "'", "'\\''")
    return string.format("task rc:'%s' %s", escaped_rc, task_args)
  else
    return string.format("task %s", task_args)
  end
end

-- Helper function to filter Taskwarrior informational messages from output
local function filter_taskwarrior_messages(output, workspace_override)
  -- When using rc: override, Taskwarrior outputs "TASKRC override: ..." before JSON
  local workspace_rc = get_workspace_rc_with_override(workspace_override)
  if workspace_rc and workspace_rc ~= "" then
    -- Remove lines starting with "TASKRC override:"
    return string.gsub(output, "^TASKRC override:.-\n", "")
  end
  return output
end

-- Execute a task command and return success status
local function execute_task_command(task_args, workspace_override)
  local command = build_task_command(task_args, workspace_override)
  local output = vim.fn.system(command)
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    vim.notify("Task command failed: " .. output, vim.log.levels.ERROR)
    return false
  end

  return true
end

-- Helper to check if a task has incomplete dependencies
local function get_incomplete_dependencies(task, workspace_override)
  if not task.depends or #task.depends == 0 then
    return nil
  end

  local incomplete_deps = {}

  for _, dep_uuid in ipairs(task.depends) do
    -- Query the dependency task
    local cmd = build_task_command(string.format("%s export", dep_uuid), workspace_override)
    local dep_json = vim.fn.system(cmd)
    dep_json = filter_taskwarrior_messages(dep_json, workspace_override)
    if vim.v.shell_error == 0 then
      local success, dep_tasks = pcall(vim.fn.json_decode, dep_json)
      if success and dep_tasks and #dep_tasks > 0 then
        local dep_task = dep_tasks[1]
        -- Check if dependency is not completed or deleted
        -- Deleted tasks should not block completion
        if dep_task.status ~= "completed" and dep_task.status ~= "deleted" then
          table.insert(incomplete_deps, {
            uuid = dep_uuid,
            description = dep_task.description or "Unknown task",
            short_hash = string.sub(dep_uuid, 1, 8)
          })
        end
      end
    end
  end

  if #incomplete_deps > 0 then
    return incomplete_deps
  end
  return nil
end

-- Helper to mark multiple tasks as done
local function mark_tasks_done(task_uuids, workspace_override)
  local failed = {}

  for _, uuid in ipairs(task_uuids) do
    if not execute_task_command(string.format("%s done", uuid), workspace_override) then
      table.insert(failed, string.sub(uuid, 1, 8))
    end
  end

  return failed
end

-- Toggle task between done and undone
function M.toggle_done()
  local hash = M.get_task_hash_under_cursor()
  if not hash then
    return
  end

  -- Get current workspace for proper task operations
  local workspace = require("frontline").get_current_workspace()

  -- Get current task status to determine action
  local cmd = build_task_command(string.format("%s export", hash), workspace)
  local task_json = vim.fn.system(cmd)
  task_json = filter_taskwarrior_messages(task_json, workspace)
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    vim.notify("Failed to get task status", vim.log.levels.ERROR)
    return
  end

  -- Parse JSON to check status
  local success, tasks = pcall(vim.fn.json_decode, task_json)
  if not success or not tasks or #tasks == 0 then
    vim.notify("Failed to parse task data", vim.log.levels.ERROR)
    return
  end

  local task = tasks[1]

  if task.status == "completed" then
    -- Reopen the task
    vim.notify("Reopening task...", vim.log.levels.INFO)

    if execute_task_command(string.format("%s modify status:pending", hash), workspace) then
      require("frontline").refresh_current_buffer()
    end
  else
    -- Check for incomplete dependencies before marking as done
    local incomplete_deps = get_incomplete_dependencies(task, workspace)

    if incomplete_deps then
      -- Build dependency list for display
      local dep_list = {}
      for _, dep in ipairs(incomplete_deps) do
        table.insert(dep_list, string.format("  • %s (%s)", dep.description, dep.short_hash))
      end

      -- Print dependencies to command area
      vim.api.nvim_echo({
        {string.format("Task has %d incomplete %s:\n", #incomplete_deps, #incomplete_deps == 1 and "dependency" or "dependencies"), "WarningMsg"},
        {table.concat(dep_list, "\n") .. "\n\n", "Normal"}
      }, true, {})

      -- Show user selection prompt
      vim.ui.select(
        {
          "Do nothing (keep task pending)",
          string.format("Mark task done with all %d %s", #incomplete_deps, #incomplete_deps == 1 and "dependency" or "dependencies"),
          "Mark task done and ignore dependencies"
        },
        {
          prompt = "What do you want to do?",
          format_item = function(item)
            return item
          end
        },
        function(choice, idx)
          if not choice then
            vim.notify("Action cancelled", vim.log.levels.INFO)
            return
          end

          if idx == 1 then
            -- Do nothing
            vim.notify("Task kept as pending", vim.log.levels.INFO)
          elseif idx == 2 then
            -- Mark task done with all dependencies
            vim.notify("Marking task and dependencies as done...", vim.log.levels.INFO)

            -- Collect all UUIDs (dependencies + current task)
            local all_uuids = {}
            for _, dep in ipairs(incomplete_deps) do
              table.insert(all_uuids, dep.uuid)
            end
            table.insert(all_uuids, task.uuid)

            local failed = mark_tasks_done(all_uuids, workspace)

            if #failed > 0 then
              vim.notify(
                string.format("Failed to complete some tasks: %s", table.concat(failed, ", ")),
                vim.log.levels.ERROR
              )
            else
              vim.notify("All tasks marked as done", vim.log.levels.INFO)
            end

            require("frontline").refresh_current_buffer()
          elseif idx == 3 then
            -- Mark task done, ignore dependencies
            vim.notify("Marking task as done (ignoring dependencies)...", vim.log.levels.INFO)

            if execute_task_command(string.format("%s done", hash), workspace) then
              require("frontline").refresh_current_buffer()
            end
          end
        end
      )
    else
      -- No incomplete dependencies, mark as done normally
      vim.notify("Marking task as done...", vim.log.levels.INFO)

      if execute_task_command(string.format("%s done", hash), workspace) then
        require("frontline").refresh_current_buffer()
      end
    end
  end
end

-- Show blocking dependencies for the task under cursor
function M.show_blocking_dependencies()
  local hash = M.get_task_hash_under_cursor()
  if not hash then
    return
  end

  -- Get current workspace for proper task operations
  local workspace = require("frontline").get_current_workspace()

  -- Get task information
  local cmd = build_task_command(string.format("%s export", hash), workspace)
  local task_json = vim.fn.system(cmd)
  task_json = filter_taskwarrior_messages(task_json, workspace)
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    vim.notify("Failed to get task information", vim.log.levels.ERROR)
    return
  end

  -- Parse JSON
  local success, tasks = pcall(vim.fn.json_decode, task_json)
  if not success or not tasks or #tasks == 0 then
    vim.notify("Failed to parse task data", vim.log.levels.ERROR)
    return
  end

  local task = tasks[1]

  -- Get forward dependencies (tasks blocking this task)
  local forward_deps = {}
  local forward_blocking_count = 0

  if task.depends and #task.depends > 0 then
    for _, dep_uuid in ipairs(task.depends) do
      local dep_cmd = build_task_command(string.format("%s export", dep_uuid))
      local dep_json = vim.fn.system(dep_cmd)
      dep_json = filter_taskwarrior_messages(dep_json, nil)
      if vim.v.shell_error == 0 then
        local dep_success, dep_tasks = pcall(vim.fn.json_decode, dep_json)
        if dep_success and dep_tasks and #dep_tasks > 0 then
          local dep_task = dep_tasks[1]
          table.insert(forward_deps, {
            uuid = dep_uuid,
            description = dep_task.description or "Unknown task",
            short_hash = string.sub(dep_uuid, 1, 8),
            status = dep_task.status,
            is_blocking = dep_task.status ~= "completed"
          })
          if dep_task.status ~= "completed" then
            forward_blocking_count = forward_blocking_count + 1
          end
        end
      end
    end
  end

  -- Get all dependencies (both complete and incomplete)
  local deps_info = {}
  for _, dep_uuid in ipairs(task.depends) do
    local dep_cmd = build_task_command(string.format("%s export", dep_uuid), workspace)
    local dep_json = vim.fn.system(dep_cmd)
    dep_json = filter_taskwarrior_messages(dep_json, workspace)
    if vim.v.shell_error == 0 then
      local dep_success, dep_tasks = pcall(vim.fn.json_decode, dep_json)
      if dep_success and dep_tasks and #dep_tasks > 0 then
        local dep_task = dep_tasks[1]
        table.insert(deps_info, {
          uuid = dep_uuid,
          description = dep_task.description or "Unknown task",
          short_hash = string.sub(dep_uuid, 1, 8),
          status = dep_task.status,
          is_blocking = dep_task.status ~= "completed"
      })
      end
    end
  end
  -- Get reverse dependencies (tasks this task is blocking) - only if enabled
  local reverse_deps = {}
  if config.enable_reverse_dependencies then
    local task_client = require("frontline.task_client")
    local reverse_deps_tasks, rev_err = task_client.get_reverse_dependencies(task.uuid)

    if not rev_err and reverse_deps_tasks then
      for _, rev_task in ipairs(reverse_deps_tasks) do
        table.insert(reverse_deps, {
          uuid = rev_task.uuid,
          description = rev_task.description or "Unknown task",
          short_hash = string.sub(rev_task.uuid, 1, 8),
          status = rev_task.status,
          is_blocking = rev_task.status ~= "completed"
        })
      end
    end
  end

  -- Check if there are any dependencies to show
  if #forward_deps == 0 and #reverse_deps == 0 then
    local msg = config.enable_reverse_dependencies
      and "Task has no dependencies (forward or reverse)"
      or "Task has no dependencies"
    vim.notify(msg, vim.log.levels.INFO)
    return
  end

  -- Build display
  local echo_chunks = {}

  -- Forward dependencies section
  if #forward_deps > 0 then
    table.insert(echo_chunks, {
      string.format("Tasks blocking this task (%d total, %d incomplete):\n",
        #forward_deps, forward_blocking_count),
      "Title"
    })

    for _, dep in ipairs(forward_deps) do
      local status_indicator = dep.is_blocking and "[ ]" or "[x]"
      local status_color = dep.is_blocking and "WarningMsg" or "Comment"
      table.insert(echo_chunks, {
        string.format("  %s %s (%s)\n", status_indicator, dep.description, dep.short_hash),
        status_color
      })
    end

    -- Add blank line if we also have reverse deps
    if #reverse_deps > 0 then
      table.insert(echo_chunks, {"\n", "Normal"})
    end
  end

  -- Reverse dependencies section
  if #reverse_deps > 0 then
    table.insert(echo_chunks, {
      string.format("Tasks this task is blocking (%d total):\n", #reverse_deps),
      "Title"
    })

    for _, dep in ipairs(reverse_deps) do
      local status_indicator = dep.is_blocking and "[ ]" or "[x]"
      local status_color = dep.is_blocking and "WarningMsg" or "Comment"
      table.insert(echo_chunks, {
        string.format("  %s %s (%s)\n", status_indicator, dep.description, dep.short_hash),
        status_color
      })
    end
  end

  vim.api.nvim_echo(echo_chunks, true, {})
end

-- Add a new task as a dependency for the task under cursor
function M.add_task_as_dependency()
  local hash = M.get_task_hash_under_cursor()
  if not hash then
    return
  end

  -- Get current workspace for proper task operations
  local workspace = require("frontline").get_current_workspace()

  -- Get current task information
  local cmd = build_task_command(string.format("%s export", hash), workspace)
  local task_json = vim.fn.system(cmd)
  task_json = filter_taskwarrior_messages(task_json, workspace)
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    vim.notify("Failed to get task information", vim.log.levels.ERROR)
    return
  end

  -- Parse JSON
  local success, tasks = pcall(vim.fn.json_decode, task_json)
  if not success or not tasks or #tasks == 0 then
    vim.notify("Failed to parse task data", vim.log.levels.ERROR)
    return
  end

  local task = tasks[1]
  local default_project = task.project or ""

  -- Get current workspace to pre-fill
  local current_workspace = require("frontline").get_current_workspace()

  -- Build default input with workspace and project
  local default_input = ""
  if current_workspace then
    default_input = string.format("@%s ", current_workspace)
  end
  if default_project ~= "" then
    default_input = default_input .. string.format("project:%s ", default_project)
  end

  -- Prompt user for new task description
  vim.ui.input({
    prompt = "New dependency task (description + attributes): ",
    default = default_input
  }, function(input)
    if not input or input == "" then
      vim.notify("Task creation cancelled", vim.log.levels.INFO)
      return
    end

    -- Parse workspace from input (e.g., "@work Fix bug project:web")
    local workspace_override, cleaned_input = parse_workspace_from_input(input)

    -- Notify if workspace override is used
    if workspace_override then
      vim.notify(string.format("Creating dependency task in workspace: %s", workspace_override), vim.log.levels.INFO)
    end

    -- Extract description and attributes
    -- User input format: "description project:X priority:H ..."
    -- We need to wrap the description in quotes
    local first_space = cleaned_input:find("%s")
    local description, attributes

    if first_space then
      -- Find where attributes start (project:, priority:, due:, etc.)
      local attr_start = cleaned_input:find("%w+:")
      if attr_start then
        description = cleaned_input:sub(1, attr_start - 1):gsub("%s+$", "")
        attributes = cleaned_input:sub(attr_start)
      else
        description = cleaned_input
        attributes = ""
      end
    else
      description = cleaned_input
      attributes = ""
    end

    -- Escape single quotes in description
    local escaped_desc = description:gsub("'", "'\\''")

    -- Create the new task
    local add_cmd = build_task_command(string.format("add '%s' %s", escaped_desc, attributes), workspace_override)
    vim.notify("Creating dependency task...", vim.log.levels.INFO)

    local add_output = vim.fn.system(add_cmd)
    local add_exit_code = vim.v.shell_error

    if add_exit_code ~= 0 then
      vim.notify("Failed to create task: " .. add_output, vim.log.levels.ERROR)
      return
    end

    -- Extract the new task ID from output (format: "Created task N.")
    local new_task_id = string.match(add_output, "Created task (%d+)%.")
    if not new_task_id then
      vim.notify("Failed to extract new task ID", vim.log.levels.ERROR)
      return
    end

    -- Get the UUID of the newly created task (use same workspace)
    local new_task_cmd = build_task_command(string.format("%s export", new_task_id), workspace_override)
    local new_task_json = vim.fn.system(new_task_cmd)
    new_task_json = filter_taskwarrior_messages(new_task_json, workspace_override)
    if vim.v.shell_error ~= 0 then
      vim.notify("Failed to get new task UUID", vim.log.levels.ERROR)
      return
    end

    local new_success, new_tasks = pcall(vim.fn.json_decode, new_task_json)
    if not new_success or not new_tasks or #new_tasks == 0 then
      vim.notify("Failed to parse new task data", vim.log.levels.ERROR)
      return
    end

    local new_uuid = new_tasks[1].uuid

    -- Add the new task as a dependency to the original task
    vim.notify("Adding dependency...", vim.log.levels.INFO)

    if execute_task_command(string.format("%s modify depends:%s", hash, new_uuid), workspace) then
      vim.notify(string.format("Created task %s as dependency", new_task_id), vim.log.levels.INFO)
      require("frontline").refresh_current_buffer()
    end
  end)
end

-- Toggle task between started and unstarted
function M.toggle_started()
  local hash = M.get_task_hash_under_cursor()
  if not hash then
    return
  end

  -- Get current workspace for proper task operations
  local workspace = require("frontline").get_current_workspace()

  -- Get current task status to determine action
  local cmd = build_task_command(string.format("%s export", hash), workspace)
  local task_json = vim.fn.system(cmd)
  task_json = filter_taskwarrior_messages(task_json, workspace)
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    vim.notify("Failed to get task status", vim.log.levels.ERROR)
    return
  end

  -- Parse JSON to check if started
  local success, tasks = pcall(vim.fn.json_decode, task_json)
  if not success or not tasks or #tasks == 0 then
    vim.notify("Failed to parse task data", vim.log.levels.ERROR)
    return
  end

  local task = tasks[1]
  local task_args

  if task.start then
    -- Stop the task
    task_args = string.format("%s stop", hash)
    vim.notify("Stopping task...", vim.log.levels.INFO)
  else
    -- Start the task
    task_args = string.format("%s start", hash)
    vim.notify("Starting task...", vim.log.levels.INFO)
  end

  if execute_task_command(task_args, workspace) then
    -- Refresh the buffer
    require("frontline").refresh_current_buffer()
  end
end

-- Modify task description
function M.modify_task()
  local hash = M.get_task_hash_under_cursor()
  if not hash then
    return
  end

  -- Get current workspace for proper task operations
  local workspace = require("frontline").get_current_workspace()

  -- Prompt user for modification string
  vim.ui.input({ prompt = "Modify task (e.g., 'priority:H due:tomorrow'): " }, function(input)
    if not input or input == "" then
      vim.notify("Modification cancelled", vim.log.levels.INFO)
      return
    end

    vim.notify("Modifying task...", vim.log.levels.INFO)

    if execute_task_command(string.format("%s modify %s", hash, input), workspace) then
      -- Refresh the buffer
      require("frontline").refresh_current_buffer()
    end
  end)
end

-- Add annotation to task
function M.add_annotation()
  local hash = M.get_task_hash_under_cursor()
  if not hash then
    return
  end

  -- Get current workspace for proper task operations
  local workspace = require("frontline").get_current_workspace()

  -- Prompt user for annotation text
  vim.ui.input({ prompt = "Annotation text: " }, function(input)
    if not input or input == "" then
      vim.notify("Annotation cancelled", vim.log.levels.INFO)
      return
    end

    vim.notify("Adding annotation...", vim.log.levels.INFO)

    if execute_task_command(string.format("%s annotate '%s'", hash, input:gsub("'", "'\\'''")), workspace) then
      -- Refresh the buffer
      require("frontline").refresh_current_buffer()
    end
  end)
end

-- Edit task in Taskwarrior's interactive editor
function M.edit_task()
  local hash = M.get_task_hash_under_cursor()
  if not hash then
    return
  end

  -- Get current workspace for proper task operations
  local workspace = require("frontline").get_current_workspace()

  -- Save current Neovim state
  vim.cmd("write")

  -- Open task edit in a terminal buffer
  vim.notify("Opening task editor...", vim.log.levels.INFO)

  -- Create a new terminal buffer for task edit
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")

  -- Open in a split
  vim.cmd("split")
  vim.api.nvim_win_set_buf(0, bufnr)

  -- Start terminal with task edit command
  local edit_cmd = build_task_command(string.format("%s edit", hash), workspace)
  local term_job = vim.fn.termopen(edit_cmd, {
    on_exit = function(_, exit_code, _)
      if exit_code == 0 then
        vim.notify("Task updated", vim.log.levels.INFO)
        -- Close the terminal window
        vim.cmd("close")
        -- Refresh the buffer
        vim.schedule(function()
          require("frontline").refresh_current_buffer()
        end)
      else
        vim.notify("Task edit cancelled or failed", vim.log.levels.WARN)
        vim.cmd("close")
      end
    end
  })

  -- Enter insert mode in the terminal
  vim.cmd("startinsert")
end

-- Undo the last Taskwarrior action (global undo, not per-task)
function M.undo_task()
  -- Note: Taskwarrior's undo is global - it reverts the most recent operation
  -- across all tasks, not just the task under cursor

  -- First, get the undo preview by running task undo with 'no'
  local preview_cmd = build_task_command("undo")
  local preview_output = vim.fn.system("echo 'no' | " .. preview_cmd)

  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to get undo preview", vim.log.levels.ERROR)
    return
  end

  -- Display the undo preview
  vim.api.nvim_echo({{preview_output, "Normal"}}, true, {})

  -- Ask user for confirmation
  vim.ui.select(
    {"Yes, undo the last action", "No, cancel"},
    {
      prompt = "Confirm undo:",
      format_item = function(item)
        return item
      end
    },
    function(choice, idx)
      if not choice or idx == 2 then
        vim.notify("Undo cancelled", vim.log.levels.INFO)
        return
      end

      -- Execute the undo
      vim.notify("Undoing last action...", vim.log.levels.INFO)
      local undo_cmd = build_task_command("undo")
      local undo_output = vim.fn.system("echo 'yes' | " .. undo_cmd)
      local exit_code = vim.v.shell_error

      if exit_code ~= 0 then
        vim.notify("Undo failed: " .. undo_output, vim.log.levels.ERROR)
        return
      end

      vim.notify("Last action undone", vim.log.levels.INFO)
      require("frontline").refresh_current_buffer()
    end
  )
end

-- Helper to convert ISO date to YYYY-MM-DD format for taskwarrior input
local function format_date_for_input(iso_date)
  if not iso_date or iso_date == "" then
    return nil
  end
  -- ISO format from taskwarrior: 20251225T103000Z
  -- Extract YYYY-MM-DD
  local year = string.sub(iso_date, 1, 4)
  local month = string.sub(iso_date, 5, 6)
  local day = string.sub(iso_date, 7, 8)
  return string.format("%s-%s-%s", year, month, day)
end

-- Helper to extract context from a task on the current line
local function get_context_from_task_line()
  local hash = M.get_task_hash_under_cursor()
  if not hash then
    return nil
  end

  -- Get current workspace for proper task operations
  local workspace = require("frontline").get_current_workspace()

  -- Get task details
  local cmd = build_task_command(string.format("%s export", hash), workspace)
  local task_json = vim.fn.system(cmd)
  task_json = filter_taskwarrior_messages(task_json, workspace)
  if vim.v.shell_error ~= 0 then
    return nil
  end

  local success, tasks = pcall(vim.fn.json_decode, task_json)
  if not success or not tasks or #tasks == 0 then
    return nil
  end

  local task = tasks[1]
  return {
    project = task.project,
    due = format_date_for_input(task.due),
    scheduled = format_date_for_input(task.scheduled)
  }
end

-- Helper to extract project, tags, workspace, and dates from header filter
-- (e.g., "# Tasks | @personal project:myproj +tag1 +tag2 due:2026-01-01")
local function get_context_from_header()
  local line = vim.api.nvim_get_current_line()

  -- Match header with filter: # Header | filter
  local filter = string.match(line, "^#+ .* | (.+)$")
  if not filter then
    return nil
  end

  -- Extract workspace from filter (e.g., @personal, @work)
  local workspace = string.match(filter, "@([%w_%-]+)")

  -- Extract project from filter (project:name or proj:name)
  local project = string.match(filter, "proj[ect]*:([%w%.%-_]+)")

  -- Extract tags (words starting with +), excluding virtual tags
  -- Virtual tags are all uppercase (e.g., PENDING, COMPLETED, OVERDUE, WEEK, etc.)
  local tags = {}
  for tag in string.gmatch(filter, "%+([%w_%-]+)") do
    -- Only include non-virtual tags (not all uppercase)
    if tag ~= tag:upper() then
      table.insert(tags, tag)
    end
  end

  -- Extract due date if it's specific (not a modifier like due.before, due.after)
  -- Only match "due:VALUE" where it's not preceded by a dot (not due.something:)
  local due = nil
  if not string.match(filter, "due%.") then
    due = string.match(filter, "due:([^%s]+)")
  end

  -- Extract scheduled date if it's specific (not a modifier like scheduled.before, scheduled.after)
  -- Match both "scheduled:" and "schedule:" (taskwarrior accepts both)
  local scheduled = nil
  if not string.match(filter, "schedul[ed]*%.") then
    scheduled = string.match(filter, "schedul[ed]*:([^%s]+)")
  end

  return {
    project = project,
    tags = (#tags > 0 and tags or nil),
    workspace = workspace,
    due = due,
    scheduled = scheduled
  }
end

-- Create a new task with smart pre-fill based on context
function M.create_new_task()
  -- Determine pre-fill based on cursor position
  local prefill = ""

  -- First, check if cursor is on a task line
  local context_from_task = get_context_from_task_line()
  if context_from_task then
    local parts = {}

    -- Get current workspace when creating from a task line
    local current_workspace = require("frontline").get_current_workspace()
    if current_workspace then
      table.insert(parts, string.format("@%s", current_workspace))
    end

    if context_from_task.project then
      table.insert(parts, string.format("project:%s", context_from_task.project))
    end

    if context_from_task.due then
      table.insert(parts, string.format("due:%s", context_from_task.due))
    end

    if context_from_task.scheduled then
      table.insert(parts, string.format("scheduled:%s", context_from_task.scheduled))
    end

    prefill = table.concat(parts, " ") .. " "
  else
    -- Check if cursor is on a header with project, tags, workspace, and/or date filters
    local context_from_header = get_context_from_header()
    if context_from_header then
      local parts = {}

      if context_from_header.workspace then
        table.insert(parts, string.format("@%s", context_from_header.workspace))
      end

      if context_from_header.project then
        table.insert(parts, string.format("project:%s", context_from_header.project))
      end

      if context_from_header.tags then
        for _, tag in ipairs(context_from_header.tags) do
          table.insert(parts, string.format("+%s", tag))
        end
      end

      if context_from_header.due then
        table.insert(parts, string.format("due:%s", context_from_header.due))
      end

      if context_from_header.scheduled then
        table.insert(parts, string.format("scheduled:%s", context_from_header.scheduled))
      end

      prefill = table.concat(parts, " ") .. " "
    end
  end

  -- Prompt user for task input
  vim.ui.input(
    {
      prompt = "New task: ",
      default = prefill,
    },
    function(input)
      if not input or input == "" then
        vim.notify("Task creation cancelled", vim.log.levels.INFO)
        return
      end

      -- Parse workspace from input (e.g., "@work Fix bug project:web")
      local workspace_override, cleaned_input = parse_workspace_from_input(input)

      -- Notify if workspace override is used
      if workspace_override then
        vim.notify(string.format("Creating task in workspace: %s", workspace_override), vim.log.levels.INFO)
      end

      -- Create the task
      local cmd = build_task_command(string.format("add %s", cleaned_input), workspace_override)
      local output = vim.fn.system(cmd)
      local exit_code = vim.v.shell_error

      if exit_code ~= 0 then
        vim.notify("Failed to create task: " .. output, vim.log.levels.ERROR)
        return
      end

      vim.notify("Task created successfully", vim.log.levels.INFO)
      require("frontline").refresh_current_buffer()
    end
  )
end

return M
