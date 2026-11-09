local mappings = require("frontline.mappings")

local task = {
  uuid = "abcdef1234567890abcdef1234567890",
  description = "Fix the login bug",
  status = "pending",
  project = "work",
  tags = { "urgent", "backend" },
  due = "20251225T103000Z",
}

describe("custom actions", function()
  describe("validate_custom_action", function()
    it("accepts a key and a cmd", function()
      assert.is_nil(mappings.validate_custom_action({ key = "<leader>tca", cmd = "wl-copy" }))
    end)

    it("accepts an input template and a desc", function()
      assert.is_nil(mappings.validate_custom_action({
        key = "<leader>tca", cmd = "wl-copy", input = "{{description}}", desc = "Copy",
      }))
    end)

    it("rejects a non-table entry", function()
      assert.is_not_nil(mappings.validate_custom_action("wl-copy"))
    end)

    it("rejects a missing key", function()
      assert.is_not_nil(mappings.validate_custom_action({ cmd = "wl-copy" }))
    end)

    it("rejects a missing cmd", function()
      assert.is_not_nil(mappings.validate_custom_action({ key = "<leader>tca" }))
    end)

    it("rejects a non-string input", function()
      assert.is_not_nil(mappings.validate_custom_action({ key = "x", cmd = "cat", input = 42 }))
    end)
  end)

  describe("build_custom_action", function()
    it("shell-escapes placeholders in cmd", function()
      local cmd = mappings.build_custom_action({ cmd = "notify-send {{description}} {{tags}}" }, task)
      assert.are.equal("notify-send 'Fix the login bug' 'urgent backend'", cmd)
    end)

    it("leaves cmd without placeholders untouched", function()
      local cmd, input = mappings.build_custom_action({ cmd = "wl-copy" }, task)
      assert.are.equal("wl-copy", cmd)
      assert.is_nil(input)
    end)

    it("renders input like copy_task_format, unescaped", function()
      local _, input = mappings.build_custom_action(
        { cmd = "wl-copy", input = "{{description}} {{tags}} due:{{due}}" }, task)
      assert.are.equal("Fix the login bug urgent backend due:2025-12-25 10:30", input)
    end)

    it("neutralises shell metacharacters in task text", function()
      local evil = vim.tbl_extend("force", task, { description = "it's $(rm -rf ~) `x`" })
      local cmd = mappings.build_custom_action({ cmd = "echo {{description}}" }, evil)
      assert.are.equal("it's $(rm -rf ~) `x`", vim.trim(vim.fn.system(cmd)))
    end)

    it("renders unknown placeholders in cmd as an empty argument", function()
      local cmd = mappings.build_custom_action({ cmd = "echo {{nope}}" }, task)
      assert.are.equal("echo ''", cmd)
    end)
  end)

  describe("run_custom_action", function()
    local original_hash, original_system, original_notify
    local notifications

    before_each(function()
      original_hash = mappings.get_task_hash_under_cursor
      original_system = vim.fn.system
      original_notify = vim.notify
      notifications = {}

      mappings.get_task_hash_under_cursor = function() return "abcdef12" end
      vim.fn.system = function(cmd, ...)
        if type(cmd) == "string" and cmd:match("^task .*export") then
          original_system("true") -- leaves vim.v.shell_error at 0
          return vim.fn.json_encode({ task })
        end
        return original_system(cmd, ...)
      end
      vim.notify = function(msg, level) table.insert(notifications, { msg = msg, level = level }) end
    end)

    after_each(function()
      mappings.get_task_hash_under_cursor = original_hash
      vim.fn.system = original_system
      vim.notify = original_notify
    end)

    local function wait_for_notification()
      vim.wait(5000, function() return #notifications > 0 end, 10)
    end

    it("writes the rendered input to the command's stdin", function()
      local out = vim.fn.tempname()
      mappings.run_custom_action({
        key = "x", cmd = "cat > " .. vim.fn.shellescape(out), input = "{{description}} {{tags}}",
      })
      wait_for_notification()

      assert.are.same({ "Fix the login bug urgent backend" }, vim.fn.readfile(out))
      assert.are.equal(vim.log.levels.INFO, notifications[1].level)
    end)

    it("reports the command's output on success", function()
      mappings.run_custom_action({ key = "x", cmd = "echo {{short_uuid}}", desc = "Show uuid" })
      wait_for_notification()

      assert.are.equal("Show uuid: abcdef12", notifications[1].msg)
    end)

    it("reports a failing command with its stderr", function()
      mappings.run_custom_action({ key = "x", cmd = "echo boom >&2; exit 3", desc = "Broken" })
      wait_for_notification()

      assert.are.equal(vim.log.levels.ERROR, notifications[1].level)
      assert.are.equal("Broken failed (exit 3): boom", notifications[1].msg)
    end)

    it("stays quiet on success when notify = false", function()
      local out = vim.fn.tempname()
      mappings.run_custom_action({ key = "x", cmd = "touch " .. vim.fn.shellescape(out), notify = false })
      vim.wait(5000, function() return vim.fn.filereadable(out) == 1 end, 10)
      vim.wait(100)

      assert.are.equal(1, vim.fn.filereadable(out))
      assert.are.equal(0, #notifications)
    end)

    it("does nothing without a task under the cursor", function()
      mappings.get_task_hash_under_cursor = function() return nil end
      local out = vim.fn.tempname()
      mappings.run_custom_action({ key = "x", cmd = "touch " .. vim.fn.shellescape(out) })
      vim.wait(200)

      assert.are.equal(0, vim.fn.filereadable(out))
    end)
  end)

  describe("setup", function()
    it("registers valid actions as buffer mappings and drops invalid ones", function()
      local frontline = require("frontline")
      local original_notify = vim.notify
      local warnings = {}
      vim.notify = function(msg) table.insert(warnings, msg) end

      frontline.setup({
        custom_actions = {
          { key = "<leader>tca", cmd = "wl-copy", input = "{{description}}", desc = "Copy via wl-copy" },
          { key = "<leader>tcx" },
        },
      })
      vim.notify = original_notify

      assert.are.equal(1, #frontline.get_config().custom_actions)
      assert.is_true(vim.tbl_contains(warnings,
        "Frontline: custom_actions[2] needs a `cmd` string; ignoring it."))

      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = "markdown"

      local found
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
        if map.desc == "Copy via wl-copy" then found = map end
      end
      assert.is_not_nil(found)
    end)
  end)
end)
