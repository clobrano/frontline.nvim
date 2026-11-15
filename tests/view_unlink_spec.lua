-- 'x' on dependency lines of the task View removes the link, after a
-- confirmation that starts on "No". Taskwarrior is faked at the shell level.
local view = require("frontline.view")
local task_client = require("frontline.task_client")
local frontline = require("frontline")

local CUR = "cccccccc-0000-0000-0000-000000000000"
local A = "aaaaaaaa-0000-0000-0000-000000000000"
local B = "bbbbbbbb-0000-0000-0000-000000000000"
local X = "dddddddd-0000-0000-0000-000000000000"

describe("view x on dependencies", function()
  local original_select, original_notify, original_refresh, original_echo
  local commands, prompts, answer, notifications

  local tasks = {
    current = { uuid = CUR, description = "Ship release", status = "pending", depends = { A, B },
      annotations = { { entry = "20260101T000000Z", description = "TODO: write notes" } } },
    a = { uuid = A, description = "Alpha", status = "pending" },
    b = { uuid = B, description = "Bravo", status = "completed" },
    x = { uuid = X, description = "Xray", status = "pending", depends = { CUR } },
  }

  before_each(function()
    commands, prompts, answer, notifications = {}, {}, "Yes", {}
    task_client._set_run_shell_command_mock(function(cmd)
      table.insert(commands, cmd)
      if cmd:match("depends%.any:") then
        return vim.fn.json_encode({ tasks.x }), 0
      elseif cmd:match("'cccccccc' export$") or cmd:match("'" .. CUR .. "' export$") then
        return vim.fn.json_encode({ tasks.current }), 0
      elseif cmd:match(" export$") then
        return vim.fn.json_encode({ tasks.a, tasks.b }), 0
      end
      return "", 0
    end)

    original_select = vim.ui.select
    vim.ui.select = function(choices, opts, cb)
      table.insert(prompts, { choices = choices, prompt = opts.prompt })
      cb(answer)
    end
    original_notify = vim.notify
    vim.notify = function(msg) table.insert(notifications, msg) end
    original_echo = vim.api.nvim_echo
    vim.api.nvim_echo = function() end
    original_refresh = frontline.refresh_current_buffer
    frontline.refresh_current_buffer = function() end

    view.open_hash("cccccccc", nil)
  end)

  after_each(function()
    vim.cmd("silent! close!")
    task_client._set_run_shell_command_mock(function(cmd)
      local out = vim.fn.system(cmd)
      return out, vim.v.shell_error
    end)
    vim.ui.select = original_select
    vim.notify = original_notify
    vim.api.nvim_echo = original_echo
    frontline.refresh_current_buffer = original_refresh
  end)

  local function line_of(text)
    for lnum, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      if line:find(text, 1, true) then
        return lnum
      end
    end
    error("no line containing " .. text)
  end

  local function press(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
  end

  local function modifies()
    local result = {}
    for _, cmd in ipairs(commands) do
      local args = cmd:match("^task (.* modify .*)$")
      if args then table.insert(result, args) end
    end
    return result
  end

  it("removes a blocker of this task from its own depends", function()
    vim.api.nvim_win_set_cursor(0, { line_of("Alpha"), 0 })
    press("x")
    assert.are.same({ "No", "Yes" }, prompts[1].choices)
    assert.are.equal('Remove link: "Alpha" blocks "Ship release"?', prompts[1].prompt)
    assert.are.same({ CUR .. " modify depends:-" .. A }, modifies())
  end)

  it("removes this task from the depends of a task it blocks", function()
    vim.api.nvim_win_set_cursor(0, { line_of("Xray"), 0 })
    press("x")
    assert.are.equal('Remove link: "Ship release" blocks "Xray"?', prompts[1].prompt)
    assert.are.same({ "rc.bulk=0 rc.confirmation=off " .. X .. " modify depends:-" .. CUR }, modifies())
  end)

  it("changes nothing when the confirmation is declined", function()
    answer = "No"
    vim.api.nvim_win_set_cursor(0, { line_of("Alpha"), 0 })
    press("x")
    assert.are.same({}, modifies())
  end)

  it("still toggles TODO annotations", function()
    vim.api.nvim_win_set_cursor(0, { line_of("write notes"), 0 })
    press("x")
    assert.are.same({}, prompts)
    local denotated = false
    for _, cmd in ipairs(commands) do
      if cmd:match("denotate 'TODO: write notes'") then denotated = true end
    end
    assert.is_true(denotated)
  end)

  it("removes every link in a visual selection, one command per direction", function()
    vim.api.nvim_win_set_cursor(0, { line_of("Alpha"), 0 })
    press("V" .. line_of("Xray") .. "Gx")
    assert.are.equal(1, #prompts)
    assert.are.equal("Remove 3 dependency links?", prompts[1].prompt)
    assert.are.same({
      CUR .. " modify depends:-" .. A .. ",-" .. B,
      "rc.bulk=0 rc.confirmation=off " .. X .. " modify depends:-" .. CUR,
    }, modifies())
  end)

  it("ignores a visual selection without dependency lines", function()
    local title = line_of("Ship release")
    vim.api.nvim_win_set_cursor(0, { title, 0 })
    press("Vx")
    assert.are.same({}, prompts)
    assert.are.equal("No dependency links in the selection", notifications[#notifications])
  end)
end)
