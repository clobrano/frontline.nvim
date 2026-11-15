-- Link existing tasks as dependencies of the current task, or the other way
-- round, by picking them from a fuzzy list of open tasks instead of typing
-- their IDs into a 'modify depends:' command. M.unlink is the dependency list:
-- it shows the task's dependencies in both directions, and removes the ones
-- picked with <Enter>; <Esc> just closes it.
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

local function confirm(question, on_yes, cancelled_msg)
  vim.ui.select({ "Yes", "No" }, { prompt = question }, function(choice)
    if choice == "Yes" then
      on_yes()
    else
      vim.notify(cancelled_msg or "Dependency linking cancelled", vim.log.levels.INFO)
    end
  end)
end

-- Resolve the task and workspace the pickers work on. Returns current, rc, or
-- nil after telling the user what went wrong.
local function load_current(hash, workspace_rc)
  hash = hash or require("frontline.mappings").get_task_hash_under_cursor()
  if not hash then
    return nil
  end
  if workspace_rc == nil then
    workspace_rc = require("frontline").get_current_workspace_rc()
  end

  local found, err = task_client.execute_query(hash, workspace_rc)
  if not found or #found == 0 then
    vim.notify("Failed to get task information" .. (err and (": " .. err) or ""), vim.log.levels.ERROR)
    return nil
  end
  return found[1], workspace_rc
end

-- After a change: refresh even on failure, since Taskwarrior may have changed
-- some tasks before stopping and the buffer should show what actually happened.
local function finish(current, on_complete)
  if on_complete then
    on_complete()
  else
    require("frontline").refresh_current_buffer(short(current.uuid))
  end
end

local function echo_selection(header, selected)
  local chunks = { { header, "Title" } }
  for _, item in ipairs(selected) do
    table.insert(chunks, { "  " .. item.label .. "\n", "Normal" })
  end
  vim.api.nvim_echo(chunks, false, {})
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

  local current
  current, workspace_rc = load_current(hash, workspace_rc)
  if not current then
    return
  end

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
    for _, item in ipairs(selected) do
      table.insert(picked, item.task)
    end
    echo_selection(spec.header(current.description or short(current.uuid)), selected)

    confirm(spec.question(#picked, current.description or short(current.uuid)), function()
      local ok, output = task_client.run_command(M.link_command(current, picked, mode), workspace_rc)
      if not ok then
        vim.notify("Failed to link tasks:\n" .. vim.trim(output or ""), vim.log.levels.ERROR)
      else
        vim.notify(string.format("Linked %d task%s", #picked, #picked == 1 and "" or "s"), vim.log.levels.INFO)
      end

      finish(current, on_complete)
    end)
  end)
end

function M.pick_blocking_tasks(hash, workspace_rc, on_complete)
  M.pick("blocked_by", hash, workspace_rc, on_complete)
end

function M.pick_blocked_tasks(hash, workspace_rc, on_complete)
  M.pick("blocks", hash, workspace_rc, on_complete)
end

--------------------------------------------------------------------------------
-- Removing dependencies
--------------------------------------------------------------------------------

local UNLINK_TAGS = {
  blocker = "[blocks this]",
  blocked = "[blocked by this]",
}

-- Every task linked to `current`, both ways, as picker items:
--   kind "blocker": a task in current.depends (it blocks current)
--   kind "blocked": a task whose depends holds current (current blocks it)
-- blocker_tasks are the exported tasks for current.depends; a UUID with no
-- exported task (purged, or in another database) is still listed so the stale
-- link can be removed. Deleted tasks that depend on current are left out.
function M.unlink_candidates(current, blocker_tasks, blocked_tasks)
  local by_uuid = {}
  for _, task in ipairs(blocker_tasks or {}) do
    by_uuid[task.uuid] = task
  end

  local function label(kind, task)
    local text = UNLINK_TAGS[kind] .. " " .. M.format_candidate(task)
    if task.status == "completed" then
      text = text .. " (completed)"
    end
    return text
  end

  local items = {}
  for _, uuid in ipairs(current.depends or {}) do
    local task = by_uuid[uuid] or { uuid = uuid, description = "(task not found)" }
    table.insert(items, { kind = "blocker", task = task, label = label("blocker", task) })
  end
  for _, task in ipairs(blocked_tasks or {}) do
    if task.uuid ~= current.uuid and task.status ~= "deleted" then
      table.insert(items, { kind = "blocked", task = task, label = label("blocked", task) })
    end
  end
  return items
end

-- At most two Taskwarrior commands remove the picked links: one on the
-- current task for its blockers (a single undo step), one on all the picked
-- tasks it blocks (a single undo step on Taskwarrior 3, one per task on 2).
function M.unlink_commands(current, picked)
  local blockers, blocked = {}, {}
  for _, item in ipairs(picked) do
    if item.kind == "blocker" then
      table.insert(blockers, "-" .. item.task.uuid)
    else
      table.insert(blocked, item.task.uuid)
    end
  end

  local cmds = {}
  if #blockers > 0 then
    table.insert(cmds, string.format("%s modify depends:%s", current.uuid, table.concat(blockers, ",")))
  end
  if #blocked > 0 then
    table.insert(cmds, string.format("rc.bulk=0 rc.confirmation=off %s modify depends:-%s",
      table.concat(blocked, " "), current.uuid))
  end
  return cmds
end

-- Pick dependencies of the task `hash`, in either direction, and remove them.
-- Arguments as for M.pick.
function M.unlink(hash, workspace_rc, on_complete)
  local current
  current, workspace_rc = load_current(hash, workspace_rc)
  if not current then
    return
  end

  -- UUIDs separated by spaces: Taskwarrior only builds comma sets from numeric
  -- IDs. A failed lookup only costs the descriptions; the links are still listed.
  local blocker_tasks = {}
  if current.depends and #current.depends > 0 then
    blocker_tasks = task_client.execute_query(table.concat(current.depends, " "), workspace_rc) or {}
  end

  local blocked_tasks, rev_err = task_client.get_reverse_dependencies(current.uuid, workspace_rc)
  if not blocked_tasks then
    vim.notify("Failed to get blocked tasks: " .. rev_err, vim.log.levels.ERROR)
    return
  end

  local items = M.unlink_candidates(current, blocker_tasks, blocked_tasks)
  if #items == 0 then
    vim.notify("Task has no dependencies", vim.log.levels.INFO)
    return
  end

  local desc = current.description or short(current.uuid)
  M.pick_many(items, "Dependencies · <Enter> removes, <Esc> closes", function(selected)
    echo_selection(string.format("These links of \"%s\" will be removed:\n", desc), selected)

    local question = string.format("Remove %s from \"%s\"?",
      #selected == 1 and "this dependency" or (#selected .. " dependencies"), desc)
    confirm(question, function()
      local errors = {}
      for _, args in ipairs(M.unlink_commands(current, selected)) do
        local ok, output = task_client.run_command(args, workspace_rc)
        if not ok then
          table.insert(errors, vim.trim(output or ""))
        end
      end

      if #errors > 0 then
        vim.notify("Failed to remove dependencies:\n" .. table.concat(errors, "\n"), vim.log.levels.ERROR)
      else
        vim.notify(string.format("Removed %d dependenc%s", #selected, #selected == 1 and "y" or "ies"),
          vim.log.levels.INFO)
      end
      finish(current, on_complete)
    end, "Dependency removal cancelled")
  end)
end

return M
