local mappings = require("frontline.mappings")

describe("start/stop task", function()
  local original_system, original_notify, original_refresh
  local frontline = require("frontline")
  local task, commands, notifications, refreshed

  before_each(function()
    task = { uuid = "abcdef1234567890", description = "Fix login bug", status = "pending" }
    commands, notifications, refreshed = {}, {}, 0

    original_system = vim.fn.system
    original_notify = vim.notify
    original_refresh = frontline.refresh_current_buffer

    vim.fn.system = function(cmd)
      table.insert(commands, cmd)
      original_system("true") -- leaves vim.v.shell_error at 0
      if cmd:match(" export$") then
        return vim.fn.json_encode({ task })
      end
      return ""
    end
    vim.notify = function(msg, level) table.insert(notifications, { msg = msg, level = level }) end
    frontline.refresh_current_buffer = function() refreshed = refreshed + 1 end
  end)

  after_each(function()
    vim.fn.system = original_system
    vim.notify = original_notify
    frontline.refresh_current_buffer = original_refresh
  end)

  local function ran(action)
    for _, cmd in ipairs(commands) do
      if cmd:match("abcdef12 " .. action .. "$") then
        return true
      end
    end
    return false
  end

  local function utc_stamp(epoch)
    return os.date("!%Y%m%dT%H%M%SZ", epoch)
  end

  it("starts an inactive task and names it", function()
    mappings.start_task("abcdef12")
    assert.is_true(ran("start"))
    assert.are.equal("▶ Started: Fix login bug", notifications[#notifications].msg)
    assert.are.equal(1, refreshed)
  end)

  it("does not stop an already active task when asked to start it", function()
    task.start = utc_stamp(os.time() - 600)
    mappings.start_task("abcdef12")
    assert.is_false(ran("start"))
    assert.is_false(ran("stop"))
    assert.matches("^Already active since .+: Fix login bug$", notifications[#notifications].msg)
    assert.are.equal(0, refreshed)
  end)

  it("stops an active task and reports how long it ran", function()
    task.start = utc_stamp(os.time() - 42 * 60 - 5)
    mappings.stop_task("abcdef12")
    assert.is_true(ran("stop"))
    assert.are.equal("■ Stopped: Fix login bug (active 42m)", notifications[#notifications].msg)
    assert.are.equal(1, refreshed)
  end)

  it("does not start an inactive task when asked to stop it", function()
    mappings.stop_task("abcdef12")
    assert.is_false(ran("start"))
    assert.is_false(ran("stop"))
    assert.are.equal("Not active: Fix login bug", notifications[#notifications].msg)
  end)

  it("toggle_started still flips the state", function()
    mappings.toggle_started("abcdef12")
    assert.is_true(ran("start"))

    commands = {}
    task.start = utc_stamp(os.time())
    mappings.toggle_started("abcdef12")
    assert.is_true(ran("stop"))
  end)

  it("calls on_complete instead of refreshing the buffer", function()
    local completed = false
    mappings.start_task("abcdef12", function() completed = true end)
    assert.is_true(completed)
    assert.are.equal(0, refreshed)
  end)
end)

describe("taskwarrior_time_to_epoch", function()
  it("round-trips a UTC timestamp", function()
    local epoch = 1763029800
    assert.are.equal(epoch, mappings.taskwarrior_time_to_epoch(os.date("!%Y%m%dT%H%M%SZ", epoch)))
  end)

  it("returns nil for garbage", function()
    assert.is_nil(mappings.taskwarrior_time_to_epoch("yesterday"))
    assert.is_nil(mappings.taskwarrior_time_to_epoch(nil))
  end)
end)

describe("format_elapsed", function()
  it("formats seconds, minutes, hours and days", function()
    assert.are.equal("45s", mappings.format_elapsed(45))
    assert.are.equal("42m", mappings.format_elapsed(42 * 60 + 5))
    assert.are.equal("1h 05m", mappings.format_elapsed(65 * 60))
    assert.are.equal("2d 3h", mappings.format_elapsed((51 * 60 + 10) * 60))
  end)
end)
