local M = {}

-- Cache for projects and tags to avoid repeated queries
local cache = {
  projects = nil,
  tags = nil,
  last_update = 0,
  ttl = 300, -- Cache time-to-live in seconds (5 minutes)
}

-- Function to check if cache is valid
local function is_cache_valid()
  return cache.last_update > 0 and (os.time() - cache.last_update) < cache.ttl
end

-- Function to invalidate cache
function M.invalidate_cache()
  cache.projects = nil
  cache.tags = nil
  cache.last_update = 0
end

-- Query all unique projects from taskwarrior
function M.get_projects(workspace_rc)
  if is_cache_valid() and cache.projects then
    return cache.projects
  end

  local task_client = require("frontline.task_client")
  -- Query ALL tasks to get projects (not just pending/waiting)
  local tasks, err = task_client.execute_query("", workspace_rc)

  if not tasks then
    vim.notify("Failed to query projects: " .. tostring(err), vim.log.levels.WARN)
    return {}
  end

  local projects = {}
  local seen = {}

  for _, task in ipairs(tasks) do
    if task.project and not seen[task.project] then
      table.insert(projects, task.project)
      seen[task.project] = true
    end
  end

  table.sort(projects)
  cache.projects = projects
  cache.last_update = os.time()

  return projects
end

-- Query all unique tags from taskwarrior (excluding virtual tags)
function M.get_tags(workspace_rc)
  if is_cache_valid() and cache.tags then
    return cache.tags
  end

  local task_client = require("frontline.task_client")
  -- Query ALL tasks to get tags (not just pending/waiting)
  local tasks, err = task_client.execute_query("", workspace_rc)

  if not tasks then
    vim.notify("Failed to query tags: " .. tostring(err), vim.log.levels.WARN)
    return {}
  end

  local tags = {}
  local seen = {}

  for _, task in ipairs(tasks) do
    if task.tags then
      for _, tag in ipairs(task.tags) do
        -- Exclude virtual tags (all uppercase)
        if not seen[tag] and not string.match(tag, "^[A-Z]+$") then
          table.insert(tags, tag)
          seen[tag] = true
        end
      end
    end
  end

  table.sort(tags)
  cache.tags = tags
  cache.last_update = os.time()

  return tags
end

-- Common date shortcuts for taskwarrior
local date_shortcuts = {
  "today",
  "tomorrow",
  "yesterday",
  "monday",
  "tuesday",
  "wednesday",
  "thursday",
  "friday",
  "saturday",
  "sunday",
  "eow",      -- end of week
  "eom",      -- end of month
  "eoq",      -- end of quarter
  "eoy",      -- end of year
  "sow",      -- start of week
  "som",      -- start of month
  "soq",      -- start of quarter
  "soy",      -- start of year
  "1d",       -- 1 day
  "2d",       -- 2 days
  "3d",
  "1w",       -- 1 week
  "2w",
  "1m",       -- 1 month
  "2m",
  "3m",
  "1q",       -- 1 quarter
  "1y",       -- 1 year
}

-- Get date suggestions
function M.get_date_suggestions()
  return date_shortcuts
end

-- Get workspaces from config
function M.get_workspaces()
  local frontline = require("frontline")
  local config = frontline.config or {}
  local workspaces = {}

  if config.workspaces then
    for name, _ in pairs(config.workspaces) do
      table.insert(workspaces, name)
    end
    table.sort(workspaces)
  end

  return workspaces
end

-- Priority values
local priorities = {
  "H",  -- High
  "M",  -- Medium
  "L",  -- Low
}

-- Get priority suggestions
function M.get_priority_suggestions()
  return priorities
end

-- Parse the current line to determine what kind of completion is needed
-- Returns: completion_type, prefix
local function parse_completion_context(line, col)
  -- Get the text before cursor
  local text_before = string.sub(line, 1, col)

  -- Check for workspace (@)
  local workspace_match = string.match(text_before, "@([%w_%-]*)$")
  if workspace_match ~= nil then
    return "workspace", workspace_match
  end

  -- Check for project (project:)
  local project_match = string.match(text_before, "project:([%w%.%-_]*)$")
  if project_match ~= nil then
    return "project", project_match
  end

  -- Check for tag (+)
  local tag_match = string.match(text_before, "%+([%w_%-]*)$")
  if tag_match ~= nil then
    return "tag", tag_match
  end

  -- Check for due date
  local due_match = string.match(text_before, "due:([%w%-]*)$")
  if due_match ~= nil then
    return "date", due_match
  end

  -- Check for scheduled date
  local scheduled_match = string.match(text_before, "scheduled:([%w%-]*)$")
  if scheduled_match ~= nil then
    return "date", scheduled_match
  end

  -- Check for priority
  local priority_match = string.match(text_before, "priority:([HML]*)$")
  if priority_match ~= nil then
    return "priority", priority_match
  end

  return nil, nil
end

-- Filter suggestions based on prefix
local function filter_suggestions(suggestions, prefix)
  if not prefix or prefix == "" then
    return suggestions
  end

  local filtered = {}
  local lower_prefix = string.lower(prefix)

  for _, suggestion in ipairs(suggestions) do
    if string.sub(string.lower(suggestion), 1, #prefix) == lower_prefix then
      table.insert(filtered, suggestion)
    end
  end

  return filtered
end

-- Parse workspace from the command line input
-- Returns workspace_name (string or nil) and workspace_rc (path or nil)
local function parse_workspace_from_cmdline(cmdline)
  -- Look for @workspace_name in the command line
  local workspace_name = string.match(cmdline, "@([%w_%-]+)")

  if not workspace_name then
    return nil, nil
  end

  -- Get the workspace rc file path
  local frontline = require("frontline")
  if frontline.config and frontline.config.workspaces and frontline.config.workspaces[workspace_name] then
    local workspace_rc = vim.fn.expand(frontline.config.workspaces[workspace_name])
    return workspace_name, workspace_rc
  end

  return workspace_name, nil
end

-- Main completion function for vim.fn.input
-- This is called by Neovim's completion mechanism
-- arglead: the current word being completed
-- cmdline: the entire command line
-- cursorpos: the cursor position in the command line
function M.complete_task_input(arglead, cmdline, cursorpos)
  -- Get completion context
  local comp_type, prefix = parse_completion_context(cmdline, cursorpos)

  if not comp_type then
    return {}
  end

  local suggestions = {}

  if comp_type == "workspace" then
    suggestions = M.get_workspaces()
  elseif comp_type == "project" then
    -- First check if there's a workspace in the command line being typed
    local _, workspace_rc = parse_workspace_from_cmdline(cmdline)

    -- If no workspace in cmdline, fall back to current buffer workspace
    if not workspace_rc then
      local frontline = require("frontline")
      local current_workspace = frontline.get_current_workspace()
      if current_workspace and frontline.config.workspaces and frontline.config.workspaces[current_workspace] then
        workspace_rc = vim.fn.expand(frontline.config.workspaces[current_workspace])
      end
    end

    suggestions = M.get_projects(workspace_rc)
  elseif comp_type == "tag" then
    -- First check if there's a workspace in the command line being typed
    local _, workspace_rc = parse_workspace_from_cmdline(cmdline)

    -- If no workspace in cmdline, fall back to current buffer workspace
    if not workspace_rc then
      local frontline = require("frontline")
      local current_workspace = frontline.get_current_workspace()
      if current_workspace and frontline.config.workspaces and frontline.config.workspaces[current_workspace] then
        workspace_rc = vim.fn.expand(frontline.config.workspaces[current_workspace])
      end
    end

    suggestions = M.get_tags(workspace_rc)
  elseif comp_type == "date" then
    suggestions = M.get_date_suggestions()
  elseif comp_type == "priority" then
    suggestions = M.get_priority_suggestions()
  end

  -- Filter suggestions based on what user has typed
  local filtered = filter_suggestions(suggestions, prefix)

  return filtered
end

-- Setup completion for the plugin
function M.setup()
  -- Register the completion function globally for Vim commands
  _G.FrontlineCompleteTaskInput = M.complete_task_input

  -- Create user commands with completion support
  vim.api.nvim_create_user_command("FrontlineCreateTask", function(opts)
    local mappings = require("frontline.mappings")
    mappings.create_task_with_input(opts.args)
  end, {
    nargs = "*",
    complete = function(arglead, cmdline, cursorpos)
      -- Remove command name to get just the input part
      local input_line = cmdline:match("^%s*%S+%s*(.*)$") or ""
      local input_cursor = cursorpos - (#cmdline - #input_line)
      return M.complete_task_input(arglead, input_line, input_cursor)
    end,
    desc = "Create a new task with autocomplete support",
  })

  vim.api.nvim_create_user_command("FrontlineCreateDependency", function(opts)
    local mappings = require("frontline.mappings")
    mappings.create_dependency_with_input(opts.args)
  end, {
    nargs = "*",
    complete = function(arglead, cmdline, cursorpos)
      local input_line = cmdline:match("^%s*%S+%s*(.*)$") or ""
      local input_cursor = cursorpos - (#cmdline - #input_line)
      return M.complete_task_input(arglead, input_line, input_cursor)
    end,
    desc = "Create a new task as dependency with autocomplete support",
  })
end

return M
