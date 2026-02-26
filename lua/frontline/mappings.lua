local M = {}

-- Store reference to config (set by init.lua)
local config = { enable_reverse_dependencies = true }

-- Store parent task info for dependency creation
local dependency_parent_task = nil

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

  local cfg = frontline.get_config()
  if cfg and cfg.workspaces and cfg.workspaces[workspace] then
    return frontline.resolve_workspace_rc(cfg.workspaces[workspace])
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
  local cfg = frontline.get_config()

  -- Use override if provided, otherwise use current workspace
  local workspace = workspace_override or frontline.get_current_workspace()

  if not workspace then
    return nil
  end

  if cfg and cfg.workspaces and cfg.workspaces[workspace] then
    return frontline.resolve_workspace_rc(cfg.workspaces[workspace])
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

-- Helper to check if an annotation is an incomplete TODO.
-- Matches annotations starting with "TODO:" (case-insensitive) or markdown
-- checkboxes "[ ]". The done equivalents are "DONE:" and "[x]"/"[X]".
local function is_todo_annotation(description)
  if string.match(description:upper(), "^TODO:") then
    return true
  end
  -- Match markdown checkbox: "[ ] ..." (unchecked)
  if string.match(description, "^%[ %]") then
    return true
  end
  return false
end

local function get_todo_annotations(task)
  if not task.annotations or #task.annotations == 0 then
    return nil
  end

  local todo_annotations = {}

  for _, annotation in ipairs(task.annotations) do
    local description = annotation.description or ""
    if is_todo_annotation(description) then
      table.insert(todo_annotations, {
        description = description,
        entry = annotation.entry
      })
    end
  end

  if #todo_annotations > 0 then
    return todo_annotations
  end
  return nil
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
    -- Check for TODO annotations if feature is enabled
    local todo_annotations = nil
    if config.require_todo_annotations_done then
      todo_annotations = get_todo_annotations(task)
    end

    -- Check for incomplete dependencies before marking as done
    local incomplete_deps = get_incomplete_dependencies(task, workspace)

    -- If TODO annotations exist, block completion (showing dependencies too if present)
    if todo_annotations then
      -- Build TODO list for display
      local todo_list = {}
      for _, todo in ipairs(todo_annotations) do
        table.insert(todo_list, string.format("  • %s", todo.description))
      end

      -- Build echo chunks
      local echo_chunks = {
        {string.format("Cannot complete task: %d outstanding TODO %s:\n",
          #todo_annotations, #todo_annotations == 1 and "annotation" or "annotations"), "ErrorMsg"},
        {table.concat(todo_list, "\n") .. "\n\n", "Normal"},
      }

      -- Also show incomplete dependencies if present
      if incomplete_deps then
        local dep_list = {}
        for _, dep in ipairs(incomplete_deps) do
          table.insert(dep_list, string.format("  • %s (%s)", dep.description, dep.short_hash))
        end

        table.insert(echo_chunks, {string.format("Task also has %d incomplete %s:\n",
          #incomplete_deps, #incomplete_deps == 1 and "dependency" or "dependencies"), "WarningMsg"})
        table.insert(echo_chunks, {table.concat(dep_list, "\n") .. "\n\n", "Normal"})
      end

      -- Add hint for TODOs
      table.insert(echo_chunks, {"Hint: Change 'TODO:' to 'DONE:' (or '[ ]' to '[x]') in annotations to enable task completion.\n", "WarningMsg"})
      table.insert(echo_chunks, {"Use " .. (config.mappings.show_annotations or "<leader>ta") .. " to view annotations, then 'task <hash> denotate' and 'task <hash> annotate' to update them.", "Comment"})

      vim.api.nvim_echo(echo_chunks, true, {})
      return
    end

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
-- Create a dependency task with the given input string (called by command)
function M.create_dependency_with_input(input)
  if not dependency_parent_task then
    vim.notify("No parent task set for dependency creation", vim.log.levels.ERROR)
    return
  end

  if not input or input == "" then
    vim.notify("Task creation cancelled", vim.log.levels.INFO)
    dependency_parent_task = nil
    return
  end

  local hash = dependency_parent_task.hash
  local workspace = dependency_parent_task.workspace

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
    dependency_parent_task = nil
    return
  end

  -- Extract the new task ID from output (format: "Created task N.")
  local new_task_id = string.match(add_output, "Created task (%d+)%.")
  if not new_task_id then
    vim.notify("Failed to extract new task ID", vim.log.levels.ERROR)
    dependency_parent_task = nil
    return
  end

  -- Get the UUID of the newly created task (use same workspace)
  local new_task_cmd = build_task_command(string.format("%s export", new_task_id), workspace_override)
  local new_task_json = vim.fn.system(new_task_cmd)
  new_task_json = filter_taskwarrior_messages(new_task_json, workspace_override)
  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to get new task UUID", vim.log.levels.ERROR)
    dependency_parent_task = nil
    return
  end

  local new_success, new_tasks = pcall(vim.fn.json_decode, new_task_json)
  if not new_success or not new_tasks or #new_tasks == 0 then
    vim.notify("Failed to parse new task data", vim.log.levels.ERROR)
    dependency_parent_task = nil
    return
  end

  local new_uuid = new_tasks[1].uuid

  -- Add the new task as a dependency to the original task
  vim.notify("Adding dependency...", vim.log.levels.INFO)

  if execute_task_command(string.format("%s modify depends:%s", hash, new_uuid), workspace) then
    vim.notify(string.format("Created task %s as dependency", new_task_id), vim.log.levels.INFO)
    require("frontline").refresh_current_buffer()
  end

  -- Clear the parent task info
  dependency_parent_task = nil
end

-- Add a new task as a dependency of the current task (triggered by keybinding)
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
    default_input = string.format("@%s", current_workspace)
  end
  if default_project ~= "" then
    if default_input ~= "" then
      default_input = default_input .. " "
    end
    default_input = default_input .. string.format("project:%s", default_project)
  end

  -- Store parent task info for the command to access
  dependency_parent_task = {
    hash = hash,
    workspace = workspace,
  }

  -- Open command line with FrontlineCreateDependency command and pre-filled text
  if default_input ~= "" then
    vim.fn.feedkeys(":FrontlineCreateDependency " .. default_input .. " ", "n")
  else
    vim.fn.feedkeys(":FrontlineCreateDependency ", "n")
  end
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
-- Show all annotations for a task
function M.show_annotations()
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

  -- Check if there are any annotations
  if not task.annotations or #task.annotations == 0 then
    vim.notify("Task has no annotations", vim.log.levels.INFO)
    return
  end

  -- Build display
  local echo_chunks = {}

  table.insert(echo_chunks, {
    string.format("Annotations (%d total):\n", #task.annotations),
    "Title"
  })

  for i, annotation in ipairs(task.annotations) do
    -- Format the timestamp if available
    local timestamp = ""
    if annotation.entry then
      -- Convert ISO timestamp to readable format
      local iso_time = annotation.entry
      -- Extract date parts (format: YYYYMMDDTHHmmssZ)
      local year = string.sub(iso_time, 1, 4)
      local month = string.sub(iso_time, 5, 6)
      local day = string.sub(iso_time, 7, 8)
      local hour = string.sub(iso_time, 10, 11)
      local min = string.sub(iso_time, 12, 13)
      timestamp = string.format("[%s-%s-%s %s:%s] ", year, month, day, hour, min)
    end

    local description = annotation.description or "No description"
    table.insert(echo_chunks, {
      string.format("  %d. %s%s\n", i, timestamp, description),
      "Normal"
    })
  end

  vim.api.nvim_echo(echo_chunks, true, {})
end

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

-- Copy task description and short UUID to clipboard
function M.copy_task()
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
  local description = task.description or "Unknown task"
  local short_uuid = string.sub(task.uuid, 1, 8)

  -- Format as "description (short_uuid)"
  local text_to_copy = string.format("%s (%s)", description, short_uuid)

  -- Copy to system clipboard (+ register)
  vim.fn.setreg('+', text_to_copy)

  vim.notify(string.format("Copied: %s", text_to_copy), vim.log.levels.INFO)
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

-- Helper function to get smart pre-fill based on context
local function get_task_creation_prefill()
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

    prefill = table.concat(parts, " ")
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

      prefill = table.concat(parts, " ")
    end
  end

  return prefill
end

-- Create a task with the given input string (called by command)
function M.create_task_with_input(input)
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

-- Create a new task with smart pre-fill based on context (triggered by keybinding)
function M.create_new_task()
  -- Get context-aware pre-fill
  local prefill = get_task_creation_prefill()

  -- Open command line with FrontlineCreateTask command and pre-filled text
  -- This allows Tab completion to work properly
  if prefill and prefill ~= "" then
    vim.fn.feedkeys(":FrontlineCreateTask " .. prefill .. " ", "n")
  else
    vim.fn.feedkeys(":FrontlineCreateTask ", "n")
  end
end

-- Helper function to clean up URL by removing unbalanced trailing parentheses
-- This handles markdown link syntax like [text](url) where the trailing ) is not part of the URL
local function clean_url(url)
  -- Count opening and closing parentheses in the URL
  local open_count = 0
  local close_count = 0
  for c in url:gmatch(".") do
    if c == "(" then open_count = open_count + 1 end
    if c == ")" then close_count = close_count + 1 end
  end

  -- Strip trailing ) if there are more closing than opening parens
  while close_count > open_count and url:sub(-1) == ")" do
    url = url:sub(1, -2)
    close_count = close_count - 1
  end

  return url
end

-- Helper function to extract URLs from text
local function extract_urls(text)
  local urls = {}
  -- Match common URL patterns (http, https, ftp)
  for url in string.gmatch(text, "https?://[%w%-%.]+[%w%-]+%.[%w]+[%w%-%._~:/?#%[%]@!$&'%(%)%*%+,;=%%]*") do
    table.insert(urls, clean_url(url))
  end
  -- Also match ftp URLs
  for url in string.gmatch(text, "ftp://[%w%-%.]+[%w%-]+%.[%w]+[%w%-%._~:/?#%[%]@!$&'%(%)%*%+,;=%%]*") do
    table.insert(urls, clean_url(url))
  end
  return urls
end

-- Helper function to clean file path by removing trailing punctuation
local function clean_file_path(path)
  -- Remove trailing punctuation that's likely not part of the path
  path = path:gsub("[,;:!?]+$", "")
  -- Handle markdown link syntax - remove unbalanced trailing parentheses
  local open_count = 0
  local close_count = 0
  for c in path:gmatch(".") do
    if c == "(" then open_count = open_count + 1 end
    if c == ")" then close_count = close_count + 1 end
  end
  while close_count > open_count and path:sub(-1) == ")" do
    path = path:sub(1, -2)
    close_count = close_count - 1
  end
  return path
end

-- Helper function to extract file paths from text
local function extract_file_paths(text)
  local paths = {}
  local seen = {}

  -- Helper to check if a path looks like it's part of a URL
  local function is_url_fragment(path)
    -- Skip paths starting with // (likely from URLs like https://)
    if path:match("^//") then return true end
    -- Skip paths containing :// (URL scheme)
    if path:match("://") then return true end
    -- Skip if the path contains typical URL-only characters in suspicious positions
    if path:match("^/[^/]+%.[^/]+/") and path:match("%.com/") then return true end
    if path:match("%.com/") or path:match("%.org/") or path:match("%.net/") or path:match("%.io/") then return true end
    return false
  end

  -- Helper to check if path is a prefix of an already-seen path
  local function is_prefix_of_existing(path)
    for existing, _ in pairs(seen) do
      -- If the existing path starts with this path and is longer, skip this one
      if existing ~= path and existing:sub(1, #path) == path then
        return true
      end
    end
    return false
  end

  local function add_path(path, is_quoted)
    local cleaned = clean_file_path(path)
    if cleaned and cleaned ~= "" and not seen[cleaned] then
      -- Skip URL fragments for non-quoted paths
      if not is_quoted and is_url_fragment(cleaned) then
        return
      end
      seen[cleaned] = true
      table.insert(paths, cleaned)
    end
  end

  -- First, match quoted paths (supports spaces) - these are trusted
  -- Double-quoted paths: "/path/to/my file.txt"
  for path in string.gmatch(text, '"(/[^"]+)"') do
    add_path(path, true)
  end
  for path in string.gmatch(text, '"(~/[^"]+)"') do
    add_path(path, true)
  end
  for path in string.gmatch(text, '"(%.[%./][^"]+)"') do
    add_path(path, true)
  end
  for path in string.gmatch(text, '"([A-Za-z]:[^"]+)"') do
    add_path(path, true)
  end

  -- Single-quoted paths: '/path/to/my file.txt'
  for path in string.gmatch(text, "'(/[^']+)'") do
    add_path(path, true)
  end
  for path in string.gmatch(text, "'(~/[^']+)'") do
    add_path(path, true)
  end
  for path in string.gmatch(text, "'(%.[%./][^']+)'") do
    add_path(path, true)
  end
  for path in string.gmatch(text, "'([A-Za-z]:[^']+)'") do
    add_path(path, true)
  end

  -- Match Unix absolute paths without spaces: /path/to/file
  for path in string.gmatch(text, "/[%w%-%._/]+") do
    -- Must have at least one path separator after the initial / or have an extension
    if path:match("/.+/") or path:match("/[^/]+%.[^/]+$") then
      -- Skip if this is a prefix of an already-added quoted path
      if not is_prefix_of_existing(path) then
        add_path(path, false)
      end
    end
  end

  -- Match home-relative paths without spaces: ~/path/to/file
  for path in string.gmatch(text, "~/[%w%-%._/]+") do
    if not is_prefix_of_existing(path) then
      add_path(path, false)
    end
  end

  -- Match Windows absolute paths without spaces: C:\path or C:/path
  -- Use word boundary to avoid matching URL schemes like "https:"
  for path in string.gmatch(text, "%f[%w][A-Za-z]:[/\\][%w%-%._/\\]+") do
    if not is_prefix_of_existing(path) then
      add_path(path, false)
    end
  end

  -- Match relative paths without spaces: ./path or ../path
  for path in string.gmatch(text, "%.%.?/[%w%-%._/]+") do
    if not is_prefix_of_existing(path) then
      add_path(path, false)
    end
  end

  return paths
end

-- File extensions that should be opened in Neovim instead of external apps
local text_file_extensions = {
  -- Markdown and text
  md = true, markdown = true, txt = true, text = true,
  -- Org mode and other markup
  org = true, rst = true, tex = true, adoc = true,
  -- Code files
  lua = true, vim = true, py = true, js = true, ts = true, jsx = true, tsx = true,
  c = true, cpp = true, h = true, hpp = true, cc = true, cxx = true,
  rs = true, go = true, java = true, kt = true, scala = true,
  rb = true, pl = true, pm = true, php = true,
  sh = true, bash = true, zsh = true, fish = true,
  -- Config and data files
  json = true, yaml = true, yml = true, toml = true, xml = true,
  ini = true, conf = true, cfg = true, config = true,
  -- Web files
  html = true, htm = true, css = true, scss = true, less = true, sass = true,
  -- Other text formats
  csv = true, tsv = true, log = true,
}

-- Helper function to check if a file should be opened in Neovim
local function should_open_in_neovim(path)
  -- URLs should never be opened in Neovim
  if path:match("^https?://") or path:match("^ftp://") then
    return false
  end
  -- Check file extension
  local ext = path:match("%.([^%.]+)$")
  if ext then
    return text_file_extensions[ext:lower()] == true
  end
  return false
end

-- Helper function to open a resource (URL or file path) with platform-specific command
local function open_resource(resource)
  -- Expand ~ to home directory for file paths
  if resource:match("^~") then
    resource = resource:gsub("^~", os.getenv("HOME") or "~")
  end

  -- Open text files in Neovim
  if should_open_in_neovim(resource) then
    -- Check if file exists before trying to open
    local stat = vim.loop.fs_stat(resource)
    if stat then
      vim.cmd("edit " .. vim.fn.fnameescape(resource))
      vim.notify(string.format("Opened in Neovim: %s", resource), vim.log.levels.INFO)
    else
      vim.notify(string.format("File not found: %s", resource), vim.log.levels.WARN)
    end
    return
  end

  -- Open URLs and non-text files with external application
  local cmd
  local uname = vim.loop.os_uname().sysname

  if uname == "Darwin" then
    -- macOS
    cmd = string.format("open '%s'", resource:gsub("'", "'\\''"))
  elseif uname == "Windows_NT" or uname:match("^MINGW") or uname:match("^MSYS") or uname:match("^CYGWIN") then
    -- Windows (native or via MINGW/MSYS/Cygwin)
    -- Use cmd.exe's start command
    cmd = string.format('cmd.exe /c start "" "%s"', resource:gsub('"', '\\"'))
  else
    -- Linux and other Unix-like systems
    cmd = string.format("xdg-open '%s'", resource:gsub("'", "'\\''"))
  end

  -- Run asynchronously to not block Neovim
  vim.fn.jobstart(cmd, { detach = true })
  vim.notify(string.format("Opening: %s", resource), vim.log.levels.INFO)
end

-- Helper function to check if a plugin/module is available
local function is_module_available(name)
  local ok, _ = pcall(require, name)
  return ok
end

-- Helper function to check if fzf.vim is available
local function is_fzf_vim_available()
  return vim.fn.exists(':FZF') == 2
end

-- Select and open a resource (URL or file path) using the best available picker
local function select_and_open_resource(resources, annotations_map)
  -- Build display items with full annotation context
  local display_items = {}
  for i, resource in ipairs(resources) do
    local annotation_text = annotations_map[resource] or resource
    table.insert(display_items, {
      resource = resource,
      annotation = annotation_text,
      index = i,
    })
  end

  -- Try Telescope first
  if is_module_available("telescope") then
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    pickers.new({}, {
      prompt_title = "Select resource to open",
      finder = finders.new_table({
        results = display_items,
        entry_maker = function(entry)
          return {
            value = entry.resource,
            display = entry.annotation,
            ordinal = entry.annotation,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            open_resource(selection.value)
          end
        end)
        return true
      end,
    }):find()
    return
  end

  -- Try fzf.vim
  if is_fzf_vim_available() then
    -- Create temp table to store resources for callback
    _G._frontline_resource_list = resources

    -- Build source list for fzf (show full annotation)
    local source = {}
    for i, item in ipairs(display_items) do
      table.insert(source, string.format("%d. %s", i, item.annotation))
    end

    -- Use fzf#run with sink function
    vim.fn["fzf#run"](vim.fn["fzf#wrap"]({
      source = source,
      options = "--prompt='Select resource> '",
      sink = function(selected)
        -- Extract index from selection (format: "N. annotation text")
        local idx = tonumber(string.match(selected, "^(%d+)%."))
        if idx and _G._frontline_resource_list[idx] then
          open_resource(_G._frontline_resource_list[idx])
        end
        _G._frontline_resource_list = nil
      end
    }))
    return
  end

  -- Fallback to vim.ui.select (works everywhere)
  local choices = {}
  for i, item in ipairs(display_items) do
    table.insert(choices, string.format("%d. %s", i, item.annotation))
  end

  vim.ui.select(choices, {
    prompt = "Select resource to open:",
    format_item = function(item)
      return item
    end
  }, function(choice, idx)
    if choice and resources[idx] then
      open_resource(resources[idx])
    end
  end)
end

-- Helper function to sanitize a string for use as a filename
local function sanitize_filename(str)
  -- Replace spaces and special characters with hyphens
  local sanitized = str:gsub("[^%w%-_%.]+", "-")
  -- Remove leading/trailing hyphens
  sanitized = sanitized:gsub("^%-+", ""):gsub("%-+$", "")
  -- Collapse multiple consecutive hyphens
  sanitized = sanitized:gsub("%-%-+", "-")
  -- Lowercase for consistency
  sanitized = sanitized:lower()
  return sanitized
end

-- Create a markdown note from the task under cursor
function M.create_note()
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
  local description = task.description or "untitled"
  local short_uuid = string.sub(task.uuid, 1, 8)

  -- Check if a NOTE annotation already exists
  if task.annotations then
    for _, annotation in ipairs(task.annotations) do
      if annotation.description and annotation.description:match("^NOTE:%s+") then
        -- Extract the file path from the annotation (format: NOTE: "path")
        local note_path = annotation.description:match('^NOTE:%s+"(.+)"')
        if note_path and vim.fn.filereadable(note_path) == 1 then
          vim.cmd("edit " .. vim.fn.fnameescape(note_path))
          vim.notify(string.format("Opened existing note: %s", note_path), vim.log.levels.INFO)
        else
          vim.notify(
            string.format("Task already has a note annotation: %s", annotation.description),
            vim.log.levels.WARN
          )
        end
        return
      end
    end
  end

  -- Determine the notes directory: per-workspace > global > cwd
  local notes_dir = nil

  -- Check per-workspace notes_directory first
  local ws_name = require("frontline").get_current_workspace()
  if ws_name then
    local ws_entry = config.workspaces and config.workspaces[ws_name]
    if type(ws_entry) == "table" and ws_entry.notes_directory then
      notes_dir = vim.fn.expand(ws_entry.notes_directory)
    end
  end

  -- Fall back to global notes_directory, then cwd
  if not notes_dir then
    if config.notes_directory then
      notes_dir = vim.fn.expand(config.notes_directory)
    else
      notes_dir = vim.fn.getcwd()
    end
  end

  -- Build the proposed filepath from the description
  local filename = sanitize_filename(description) .. ".md"
  local proposed_path = notes_dir .. "/" .. filename

  -- Prompt user to confirm or modify the filepath
  vim.ui.input({ prompt = "Create note: ", default = proposed_path }, function(full_path)
    if not full_path or full_path == "" then
      vim.notify("Note creation cancelled", vim.log.levels.INFO)
      return
    end

    -- Ensure parent directory exists
    local parent_dir = vim.fn.fnamemodify(full_path, ":h")
    if vim.fn.isdirectory(parent_dir) == 0 then
      vim.fn.mkdir(parent_dir, "p")
    end

    -- Check if file already exists
    if vim.fn.filereadable(full_path) == 1 then
      vim.notify(string.format("File already exists: %s", full_path), vim.log.levels.WARN)
      return
    end

    -- Build note content with title and frontmatter below
    local today = os.date("%Y-%m-%d")
    local content = string.format(
      "# %s\n\n---\nCreated: %s\nTask: (%s)\n---\n",
      description,
      today,
      short_uuid
    )

    -- Write the file
    local file = io.open(full_path, "w")
    if not file then
      vim.notify(string.format("Failed to create file: %s", full_path), vim.log.levels.ERROR)
      return
    end
    file:write(content)
    file:close()

    -- Add NOTE annotation to the task
    local annotation_text = string.format("NOTE: \"%s\"", full_path)
    local escaped_annotation = annotation_text:gsub("'", "'\\''")

    if not execute_task_command(string.format("%s annotate '%s'", hash, escaped_annotation), workspace) then
      vim.notify("Note file created but failed to add annotation to task", vim.log.levels.WARN)
    end

    -- Refresh the buffer to show the annotation icon
    require("frontline").refresh_current_buffer()

    -- Open the note in Neovim
    vim.cmd("edit " .. vim.fn.fnameescape(full_path))
    vim.notify(string.format("Created note: %s", full_path), vim.log.levels.INFO)
  end)
end

-- Open URL or file path from task annotations
function M.open_url()
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

  -- Check if there are any annotations
  if not task.annotations or #task.annotations == 0 then
    vim.notify("Task has no annotations", vim.log.levels.INFO)
    return
  end

  -- Extract all URLs and file paths from all annotations
  local all_resources = {}
  local resource_seen = {}  -- To avoid duplicates
  local annotations_map = {}  -- Map resource to its annotation text

  for _, annotation in ipairs(task.annotations) do
    local description = annotation.description or ""

    -- Extract URLs
    local urls = extract_urls(description)
    for _, url in ipairs(urls) do
      if not resource_seen[url] then
        resource_seen[url] = true
        table.insert(all_resources, url)
        annotations_map[url] = description
      end
    end

    -- Extract file paths
    local paths = extract_file_paths(description)
    for _, path in ipairs(paths) do
      if not resource_seen[path] then
        resource_seen[path] = true
        table.insert(all_resources, path)
        annotations_map[path] = description
      end
    end
  end

  -- Handle based on number of resources found
  if #all_resources == 0 then
    vim.notify("No URLs or file paths found in task annotations", vim.log.levels.INFO)
    return
  elseif #all_resources == 1 then
    -- Single resource - open directly
    open_resource(all_resources[1])
  else
    -- Multiple resources - use picker
    select_and_open_resource(all_resources, annotations_map)
  end
end

return M
