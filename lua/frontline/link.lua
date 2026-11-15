-- Link existing tasks as dependencies of the current task, or the other way
-- round, by picking them from a fuzzy list of open tasks instead of typing
-- their IDs into a 'modify depends:' command.
--
--   blocked_by: the picked tasks block the current task
--               (current depends on each picked task)
--   blocks:     the current task blocks the picked tasks
--               (each picked task depends on current)
local M = {}

local task_client = require("frontline.task_client")

local MODES = {
  blocked_by = {
    prompt = "Tasks blocking this one",
    question = function(n, desc)
      return string.format("Make %s block \"%s\"?", n == 1 and "this task" or (n .. " tasks"), desc)
    end,
    header = function(desc)
      return string.format("These tasks will block \"%s\":\n", desc)
    end,
  },
  blocks = {
    prompt = "Tasks blocked by this one",
    question = function(n, desc)
      return string.format("Make \"%s\" block %s?", desc, n == 1 and "this task" or (n .. " tasks"))
    end,
    header = function(desc)
      return string.format("\"%s\" will block these tasks:\n", desc)
    end,
  },
}

local function short(uuid)
  return string.sub(uuid or "", 1, 8)
end

local function has_value(list, value)
  for _, v in ipairs(list or {}) do
    if v == value then
      return true
    end
  end
  return false
end

-- One line per candidate: what the fuzzy finder matches on and what it shows.
function M.format_candidate(task)
  local parts = { task.description or "" }
  if task.project and task.project ~= "" then
    table.insert(parts, "[" .. task.project .. "]")
  end
  for _, tag in ipairs(task.tags or {}) do
    table.insert(parts, "+" .. tag)
  end
  table.insert(parts, "(" .. short(task.uuid) .. ")")
  return table.concat(parts, " ")
end

-- Open tasks that can be linked to `current` in the given mode. The task itself
-- and tasks already linked that way are left out, and so are tasks linked the
-- opposite way, since linking them would make a two-task cycle.
function M.candidates(current, open_tasks)
  local result = {}
  for _, task in ipairs(open_tasks or {}) do
    local skip = task.uuid == current.uuid
      or has_value(current.depends, task.uuid) -- task already blocks current
      or has_value(task.depends, current.uuid) -- current already blocks task
    if not skip then
      table.insert(result, task)
    end
  end
  table.sort(result, function(a, b)
    return (a.urgency or 0) > (b.urgency or 0)
  end)
  return result
end

-- The single Taskwarrior command that creates all the links, so 'task undo'
-- can take it back.
--   blocked_by: only the current task changes, so this is always one undo step.
--   blocks:     every picked task changes. Taskwarrior 3 undoes the whole
--               command at once; Taskwarrior 2 records one undo step per task.
-- rc.bulk=0 and rc.confirmation=off stop Taskwarrior from asking "Modify N
-- tasks?" on a pipe it cannot read an answer from.
function M.link_command(current, picked, mode)
  local uuids = {}
  for _, task in ipairs(picked) do
    table.insert(uuids, task.uuid)
  end
  if mode == "blocked_by" then
    return string.format("%s modify depends:%s", current.uuid, table.concat(uuids, ","))
  end
  return string.format("rc.bulk=0 rc.confirmation=off %s modify depends:%s",
    table.concat(uuids, " "), current.uuid)
end

--------------------------------------------------------------------------------
-- Picker
--------------------------------------------------------------------------------

local function is_module_available(name)
  local ok = pcall(require, name)
  return ok
end

-- Let the user pick one or more items. on_choice gets the list of picked items
-- (never called when the picker is dismissed). Telescope and fzf.vim allow
-- several items with <Tab>; vim.ui.select picks one.
function M.pick_many(items, prompt, on_choice)
  if is_module_available("telescope") then
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    pickers.new({}, {
      prompt_title = prompt .. " (<Tab> to select several)",
      finder = finders.new_table({
        results = items,
        entry_maker = function(item)
          return { value = item, display = item.label, ordinal = item.label }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local picker = action_state.get_current_picker(prompt_bufnr)
          local multi = picker:get_multi_selection()
          local selected = {}
          if multi and #multi > 0 then
            for _, entry in ipairs(multi) do
              table.insert(selected, entry.value)
            end
          else
            local entry = action_state.get_selected_entry()
            if entry then
              table.insert(selected, entry.value)
            end
          end
          actions.close(prompt_bufnr)
          if #selected > 0 then
            -- Let Telescope finish closing before the confirmation prompt opens
            vim.schedule(function() on_choice(selected) end)
          end
        end)
        return true
      end,
    }):find()
    return
  end

  if vim.fn.exists(":FZF") == 2 then
    local source, by_line = {}, {}
    for i, item in ipairs(items) do
      local line = string.format("%d. %s", i, item.label)
      table.insert(source, line)
      by_line[line] = item
    end
    vim.fn["fzf#run"](vim.fn["fzf#wrap"]({
      source = source,
      options = { "--multi", "--prompt", prompt .. "> " },
      ["sink*"] = function(lines)
        local selected = {}
        for _, line in ipairs(lines) do
          if by_line[line] then
            table.insert(selected, by_line[line])
          end
        end
        if #selected > 0 then
          vim.schedule(function() on_choice(selected) end)
        end
      end,
    }))
    return
  end

  vim.ui.select(items, {
    prompt = prompt .. ":",
    format_item = function(item) return item.label end,
  }, function(choice)
    if choice then
      on_choice({ choice })
    end
  end)
end

--------------------------------------------------------------------------------
-- Entry point
--------------------------------------------------------------------------------

local function confirm(question, on_yes)
  vim.ui.select({ "Yes", "No" }, { prompt = question }, function(choice)
    if choice == "Yes" then
      on_yes()
    else
      vim.notify("Dependency linking cancelled", vim.log.levels.INFO)
    end
  end)
end

-- Pick open tasks and link them to the task `hash`.
--   mode:         "blocked_by" or "blocks" (see the top of this file)
--   hash:         task hash or UUID; defaults to the task under the cursor
--   workspace_rc: defaults to the current buffer's workspace
--   on_complete:  called after linking; defaults to refreshing the buffer
function M.pick(mode, hash, workspace_rc, on_complete)
  local spec = MODES[mode]
  if not spec then
    vim.notify("Unknown dependency link mode: " .. tostring(mode), vim.log.levels.ERROR)
    return
  end

  local frontline = require("frontline")
  hash = hash or require("frontline.mappings").get_task_hash_under_cursor()
  if not hash then
    return
  end
  if workspace_rc == nil then
    workspace_rc = frontline.get_current_workspace_rc()
  end

  local found, err = task_client.execute_query(hash, workspace_rc)
  if not found or #found == 0 then
    vim.notify("Failed to get task information" .. (err and (": " .. err) or ""), vim.log.levels.ERROR)
    return
  end
  local current = found[1]

  local open_tasks, open_err = task_client.execute_query("status:pending", workspace_rc)
  if not open_tasks then
    vim.notify("Failed to list open tasks: " .. open_err, vim.log.levels.ERROR)
    return
  end

  local candidates = M.candidates(current, open_tasks)
  if #candidates == 0 then
    vim.notify("No other open tasks to link", vim.log.levels.INFO)
    return
  end

  local items = {}
  for _, task in ipairs(candidates) do
    table.insert(items, { task = task, label = M.format_candidate(task) })
  end

  M.pick_many(items, spec.prompt, function(selected)
    local picked = {}
    local chunks = { { spec.header(current.description or short(current.uuid)), "Title" } }
    for _, item in ipairs(selected) do
      table.insert(picked, item.task)
      table.insert(chunks, { "  " .. item.label .. "\n", "Normal" })
    end
    vim.api.nvim_echo(chunks, false, {})

    confirm(spec.question(#picked, current.description or short(current.uuid)), function()
      local ok, output = task_client.run_command(M.link_command(current, picked, mode), workspace_rc)
      if not ok then
        vim.notify("Failed to link tasks:\n" .. vim.trim(output or ""), vim.log.levels.ERROR)
      else
        vim.notify(string.format("Linked %d task%s", #picked, #picked == 1 and "" or "s"), vim.log.levels.INFO)
      end

      -- Refresh even on failure: Taskwarrior may have linked some tasks before
      -- stopping, and the buffer should show what actually happened.
      do
        if on_complete then
          on_complete()
        else
          frontline.refresh_current_buffer(short(current.uuid))
        end
      end
    end)
  end)
end

function M.pick_blocking_tasks(hash, workspace_rc, on_complete)
  M.pick("blocked_by", hash, workspace_rc, on_complete)
end

function M.pick_blocked_tasks(hash, workspace_rc, on_complete)
  M.pick("blocks", hash, workspace_rc, on_complete)
end

return M
