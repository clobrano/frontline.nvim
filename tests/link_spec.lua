local link = require("frontline.link")

describe("link dependencies", function()
  local original_system, original_notify, original_select, original_echo, original_pick, original_refresh
  local frontline = require("frontline")
  local current, others, commands, notifications, refreshed, offered, answer

  before_each(function()
    current = { uuid = "cccccccc-0000", description = "Ship release", status = "pending", depends = { "aaaaaaaa-0000" } }
    others = {
      current,
      { uuid = "aaaaaaaa-0000", description = "Already a blocker", status = "pending", urgency = 9 },
      { uuid = "bbbbbbbb-0000", description = "Blocked by current", status = "pending", depends = { "cccccccc-0000" } },
      { uuid = "dddddddd-0000", description = "Write docs", project = "web", tags = { "doc" }, urgency = 1 },
      { uuid = "eeeeeeee-0000", description = "Fix CI", urgency = 5 },
    }
    commands, notifications, refreshed, offered, answer = {}, {}, {}, nil, "Yes"

    original_system = vim.fn.system
    original_notify = vim.notify
    original_select = vim.ui.select
    original_echo = vim.api.nvim_echo
    original_pick = link.pick_many
    original_refresh = frontline.refresh_current_buffer

    vim.fn.system = function(cmd)
      table.insert(commands, cmd)
      original_system("true")
      if cmd:match("'cccccccc' export$") then
        return vim.fn.json_encode({ current })
      elseif cmd:match("'status:pending' export$") then
        return vim.fn.json_encode(others)
      end
      return ""
    end
    vim.notify = function(msg, level) table.insert(notifications, { msg = msg, level = level }) end
    vim.api.nvim_echo = function() end
    vim.ui.select = function(_, _, cb) cb(answer) end
    -- Pick the last two candidates offered
    link.pick_many = function(items, _, on_choice)
      offered = items
      on_choice({ items[#items - 1], items[#items] })
    end
    frontline.refresh_current_buffer = function(hash) table.insert(refreshed, hash) end
  end)

  after_each(function()
    vim.fn.system = original_system
    vim.notify = original_notify
    vim.ui.select = original_select
    vim.api.nvim_echo = original_echo
    link.pick_many = original_pick
    frontline.refresh_current_buffer = original_refresh
  end)

  local function modify_commands()
    local result = {}
    for _, cmd in ipairs(commands) do
      local args = cmd:match("^task (.* modify depends:%S+)$")
      if args then table.insert(result, args) end
    end
    return result
  end

  it("offers only unrelated open tasks, most urgent first", function()
    link.pick_blocking_tasks("cccccccc", false)
    local labels = vim.tbl_map(function(i) return i.label end, offered)
    assert.are.same({ "Fix CI (eeeeeeee)", "Write docs [web] +doc (dddddddd)" }, labels)
  end)

  it("makes the picked tasks block the current task in one command", function()
    link.pick_blocking_tasks("cccccccc", false)
    assert.are.same({
      "cccccccc-0000 modify depends:eeeeeeee-0000,dddddddd-0000",
    }, modify_commands())
    assert.are.equal("Linked 2 tasks", notifications[#notifications].msg)
    assert.are.same({ "cccccccc" }, refreshed)
  end)

  it("makes the current task block the picked tasks in one command", function()
    link.pick_blocked_tasks("cccccccc", false)
    assert.are.same({
      "rc.bulk=0 rc.confirmation=off eeeeeeee-0000 dddddddd-0000 modify depends:cccccccc-0000",
    }, modify_commands())
  end)

  it("changes nothing when the confirmation is declined", function()
    answer = "No"
    link.pick_blocking_tasks("cccccccc", false)
    assert.are.same({}, modify_commands())
    assert.are.same({}, refreshed)
  end)

  it("calls on_complete instead of refreshing the buffer", function()
    local done = false
    link.pick_blocked_tasks("cccccccc", false, function() done = true end)
    assert.is_true(done)
    assert.are.same({}, refreshed)
  end)

  it("reports when there is nothing to link", function()
    others = { current }
    link.pick_blocking_tasks("cccccccc", false)
    assert.is_nil(offered)
    assert.are.equal("No other open tasks to link", notifications[#notifications].msg)
  end)

  describe("unlink_commands", function()
    it("removes blockers from the task in one command", function()
      assert.are.same({ "cur modify depends:-a,-b" }, link.unlink_commands("cur", { "a", "b" }, {}))
    end)

    it("removes the task from the tasks it blocks in one command", function()
      assert.are.same({ "rc.bulk=0 rc.confirmation=off x y modify depends:-cur" },
        link.unlink_commands("cur", nil, { "x", "y" }))
    end)

    it("uses one command per direction when both are given", function()
      assert.are.equal(2, #link.unlink_commands("cur", { "a" }, { "x" }))
    end)
  end)
end)
