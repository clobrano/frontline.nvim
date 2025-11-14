local M = {}

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

-- Execute a task command and return success status
local function execute_task_command(command)
  local output = vim.fn.system(command)
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    vim.notify("Task command failed: " .. output, vim.log.levels.ERROR)
    return false
  end

  return true
end

-- Helper to check if a task has incomplete dependencies
local function get_incomplete_dependencies(task)
  if not task.depends or #task.depends == 0 then
    return nil
  end

  local incomplete_deps = {}

  for _, dep_uuid in ipairs(task.depends) do
    -- Query the dependency task
    local dep_json = vim.fn.system(string.format("task %s export", dep_uuid))
    if vim.v.shell_error == 0 then
      local success, dep_tasks = pcall(vim.fn.json_decode, dep_json)
      if success and dep_tasks and #dep_tasks > 0 then
        local dep_task = dep_tasks[1]
        -- Check if dependency is not completed
        if dep_task.status ~= "completed" then
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
local function mark_tasks_done(task_uuids)
  local failed = {}

  for _, uuid in ipairs(task_uuids) do
    local command = string.format("task %s done", uuid)
    if not execute_task_command(command) then
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

  -- Get current task status to determine action
  local task_json = vim.fn.system(string.format("task %s export", hash))
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
    local command = string.format("task %s modify status:pending", hash)
    vim.notify("Reopening task...", vim.log.levels.INFO)

    if execute_task_command(command) then
      require("frontline").refresh_current_buffer()
    end
  else
    -- Check for incomplete dependencies before marking as done
    local incomplete_deps = get_incomplete_dependencies(task)

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

            local failed = mark_tasks_done(all_uuids)

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

            local command = string.format("task %s done", hash)
            if execute_task_command(command) then
              require("frontline").refresh_current_buffer()
            end
          end
        end
      )
    else
      -- No incomplete dependencies, mark as done normally
      local command = string.format("task %s done", hash)
      vim.notify("Marking task as done...", vim.log.levels.INFO)

      if execute_task_command(command) then
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

  -- Get task information
  local task_json = vim.fn.system(string.format("task %s export", hash))
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

  -- Check for dependencies
  if not task.depends or #task.depends == 0 then
    vim.notify("Task has no dependencies", vim.log.levels.INFO)
    return
  end

  -- Get all dependencies (both complete and incomplete)
  local deps_info = {}
  for _, dep_uuid in ipairs(task.depends) do
    local dep_json = vim.fn.system(string.format("task %s export", dep_uuid))
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

  if #deps_info == 0 then
    vim.notify("Could not retrieve dependency information", vim.log.levels.WARN)
    return
  end

  -- Build dependency list with status
  local dep_lines = {}
  local blocking_count = 0
  for _, dep in ipairs(deps_info) do
    local status_indicator = dep.is_blocking and "[ ]" or "[x]"
    local status_color = dep.is_blocking and "WarningMsg" or "Comment"
    table.insert(dep_lines, {
      string.format("  %s %s (%s)", status_indicator, dep.description, dep.short_hash),
      status_color
    })
    if dep.is_blocking then
      blocking_count = blocking_count + 1
    end
  end

  -- Display dependency information
  local header_text = string.format(
    "Task dependencies (%d total, %d blocking):\n",
    #deps_info,
    blocking_count
  )

  local echo_chunks = {{header_text, "Title"}}
  for _, line_info in ipairs(dep_lines) do
    table.insert(echo_chunks, {line_info[1] .. "\n", line_info[2]})
  end

  vim.api.nvim_echo(echo_chunks, true, {})
end

-- Add a new task as a dependency for the task under cursor
function M.add_task_as_dependency()
  local hash = M.get_task_hash_under_cursor()
  if not hash then
    return
  end

  -- Get current task information
  local task_json = vim.fn.system(string.format("task %s export", hash))
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
  local default_input = default_project ~= "" and string.format("project:%s ", default_project) or ""

  -- Prompt user for new task description
  vim.ui.input({
    prompt = "New dependency task (description + attributes): ",
    default = default_input
  }, function(input)
    if not input or input == "" then
      vim.notify("Task creation cancelled", vim.log.levels.INFO)
      return
    end

    -- Extract description and attributes
    -- User input format: "description project:X priority:H ..."
    -- We need to wrap the description in quotes
    local first_space = input:find("%s")
    local description, attributes

    if first_space then
      -- Find where attributes start (project:, priority:, due:, etc.)
      local attr_start = input:find("%w+:")
      if attr_start then
        description = input:sub(1, attr_start - 1):gsub("%s+$", "")
        attributes = input:sub(attr_start)
      else
        description = input
        attributes = ""
      end
    else
      description = input
      attributes = ""
    end

    -- Escape single quotes in description
    local escaped_desc = description:gsub("'", "'\\''")

    -- Create the new task
    local add_command = string.format("task add '%s' %s", escaped_desc, attributes)
    vim.notify("Creating dependency task...", vim.log.levels.INFO)

    local add_output = vim.fn.system(add_command)
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

    -- Get the UUID of the newly created task
    local new_task_json = vim.fn.system(string.format("task %s export", new_task_id))
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
    local modify_command = string.format("task %s modify depends:%s", hash, new_uuid)
    vim.notify("Adding dependency...", vim.log.levels.INFO)

    if execute_task_command(modify_command) then
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

  -- Get current task status to determine action
  local task_json = vim.fn.system(string.format("task %s export", hash))
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
  local command

  if task.start then
    -- Stop the task
    command = string.format("task %s stop", hash)
    vim.notify("Stopping task...", vim.log.levels.INFO)
  else
    -- Start the task
    command = string.format("task %s start", hash)
    vim.notify("Starting task...", vim.log.levels.INFO)
  end

  if execute_task_command(command) then
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

  -- Prompt user for modification string
  vim.ui.input({ prompt = "Modify task (e.g., 'priority:H due:tomorrow'): " }, function(input)
    if not input or input == "" then
      vim.notify("Modification cancelled", vim.log.levels.INFO)
      return
    end

    local command = string.format("task %s modify %s", hash, input)
    vim.notify("Modifying task...", vim.log.levels.INFO)

    if execute_task_command(command) then
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

  -- Prompt user for annotation text
  vim.ui.input({ prompt = "Annotation text: " }, function(input)
    if not input or input == "" then
      vim.notify("Annotation cancelled", vim.log.levels.INFO)
      return
    end

    local command = string.format("task %s annotate '%s'", hash, input:gsub("'", "'\\''"))
    vim.notify("Adding annotation...", vim.log.levels.INFO)

    if execute_task_command(command) then
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
  local term_job = vim.fn.termopen(string.format("task %s edit", hash), {
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
  local preview_output = vim.fn.system("echo 'no' | task undo")

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
      local undo_output = vim.fn.system("echo 'yes' | task undo")
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

-- Helper to extract project from a task on the current line
local function get_project_from_task_line()
  local hash = M.get_task_hash_under_cursor()
  if not hash then
    return nil
  end

  -- Get task details
  local task_json = vim.fn.system(string.format("task %s export", hash))
  if vim.v.shell_error ~= 0 then
    return nil
  end

  local success, tasks = pcall(vim.fn.json_decode, task_json)
  if not success or not tasks or #tasks == 0 then
    return nil
  end

  return tasks[1].project
end

-- Helper to extract project and tags from header filter (e.g., "# Tasks | project:myproj +tag1 +tag2")
local function get_context_from_header()
  local line = vim.api.nvim_get_current_line()

  -- Match header with filter: # Header | filter
  local filter = string.match(line, "^#+ .* | (.+)$")
  if not filter then
    return nil, nil
  end

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

  return project, (#tags > 0 and tags or nil)
end

-- Create a new task with smart pre-fill based on context
function M.create_new_task()
  -- Determine pre-fill based on cursor position
  local prefill = ""

  -- First, check if cursor is on a task line
  local project_from_task = get_project_from_task_line()
  if project_from_task then
    prefill = string.format("project:%s ", project_from_task)
  else
    -- Check if cursor is on a header with project and/or tags filter
    local project_from_header, tags_from_header = get_context_from_header()
    if project_from_header or tags_from_header then
      local parts = {}

      if project_from_header then
        table.insert(parts, string.format("project:%s", project_from_header))
      end

      if tags_from_header then
        for _, tag in ipairs(tags_from_header) do
          table.insert(parts, string.format("+%s", tag))
        end
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

      -- Create the task
      local cmd = string.format("task add %s", input)
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
