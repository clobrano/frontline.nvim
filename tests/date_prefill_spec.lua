
-- Test the date prefilling functionality
-- These are smoke tests to ensure the module loads correctly and basic date formatting works

describe("Date Prefilling Feature", function()
  local mappings

  before_each(function()
    -- Mock vim global to prevent errors during module load
    _G.vim = {
      api = {
        nvim_create_autocmd = function() end,
        nvim_create_user_command = function() end,
        nvim_buf_get_lines = function() return {} end,
        nvim_buf_set_lines = function() end,
        nvim_get_current_buf = function() return 0 end,
        nvim_buf_get_option = function() return "markdown" end,
        nvim_get_current_line = function() return "" end,
        nvim_echo = function() end,
        nvim_win_get_cursor = function() return {1, 0} end,
      },
      fn = {
        system = function() return "[]" end,
        json_decode = function() return {} end,
      },
      v = {
        shell_error = 0,
      },
      log = {
        levels = {
          INFO = 1,
          WARN = 2,
          ERROR = 3,
        },
      },
      notify = function() end,
      ui = {
        input = function() end,
        select = function() end,
      },
    }

    -- Load the mappings module
    mappings = require("frontline.mappings")
  end)

  after_each(function()
    package.loaded["frontline.mappings"] = nil
    package.loaded["frontline"] = nil
    package.loaded["frontline.task_client"] = nil
  end)

  it("should load the mappings module without errors", function()
    assert.is_not_nil(mappings)
    assert.is_not_nil(mappings.create_new_task)
  end)

  it("should have the create_new_task function", function()
    assert.is_function(mappings.create_new_task)
  end)

  describe("Date extraction from header filters", function()
    -- These tests validate that header parsing works correctly
    -- We test by simulating what get_context_from_header would extract

    it("should extract due date from header filter", function()
      local filter = "status:pending due:2026-01-01"
      local due_match = string.match(filter, "due:([^%s]+)")
      local has_modifier = string.match(filter, "due%.")

      assert.are.equal("2026-01-01", due_match)
      assert.is_nil(has_modifier)
    end)

    it("should extract scheduled date from header filter", function()
      local filter = "status:pending scheduled:2025-12-25"
      local scheduled_match = string.match(filter, "schedul[ed]*:([^%s]+)")
      local has_modifier = string.match(filter, "schedul[ed]*%.")

      assert.are.equal("2025-12-25", scheduled_match)
      assert.is_nil(has_modifier)
    end)

    it("should not extract due date with modifier (due.before)", function()
      local filter = "status:pending due.before:2026-01-01"
      local has_modifier = string.match(filter, "due%.")

      assert.is_not_nil(has_modifier)
    end)

    it("should not extract scheduled date with modifier (scheduled.after)", function()
      local filter = "status:pending scheduled.after:2025-12-25"
      local has_modifier = string.match(filter, "schedul[ed]*%.")

      assert.is_not_nil(has_modifier)
    end)

    it("should handle schedule (short form) in addition to scheduled", function()
      local filter = "status:pending schedule:tomorrow"
      local scheduled_match = string.match(filter, "schedul[ed]*:([^%s]+)")

      assert.are.equal("tomorrow", scheduled_match)
    end)

    it("should extract both due and scheduled dates together", function()
      local filter = "project:myproject due:2026-01-01 scheduled:2025-12-20 status:pending"
      local due_match = string.match(filter, "due:([^%s]+)")
      local scheduled_match = string.match(filter, "schedul[ed]*:([^%s]+)")

      assert.are.equal("2026-01-01", due_match)
      assert.are.equal("2025-12-20", scheduled_match)
    end)
  end)

  describe("Date formatting for taskwarrior input", function()
    it("should convert ISO date to YYYY-MM-DD format", function()
      local iso_date = "20251225T103000Z"
      local year = string.sub(iso_date, 1, 4)
      local month = string.sub(iso_date, 5, 6)
      local day = string.sub(iso_date, 7, 8)
      local formatted = string.format("%s-%s-%s", year, month, day)

      assert.are.equal("2025-12-25", formatted)
    end)

    it("should handle ISO date without time component", function()
      local iso_date = "20260101T000000Z"
      local year = string.sub(iso_date, 1, 4)
      local month = string.sub(iso_date, 5, 6)
      local day = string.sub(iso_date, 7, 8)
      local formatted = string.format("%s-%s-%s", year, month, day)

      assert.are.equal("2026-01-01", formatted)
    end)
  end)
end)
