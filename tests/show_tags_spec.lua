local renderer = require("frontline.renderer")
local task_client = require("frontline.task_client")

-- show_tags selects which tags {{icons}} shows, with globs matched against the
-- whole tag. It is off by default: tags take a lot of room on a task line.
local function tagged_task(overrides)
  local task = {
    id = 1,
    description = "Fix the login bug",
    status = "pending",
    uuid = "abcdef1234567890",
    priority = "H",
    tags = { "bug", "debug", "meeting", "meeting-weekly", "review", "backend" },
    due = "20251225T000000Z",
  }
  for key, value in pairs(overrides or {}) do
    task[key] = value
  end
  return task
end

local function render(show_tags, task, format)
  return renderer.format_task(task or tagged_task(), {
    convert_to_local = false,
    show_tags = show_tags,
    format = format,
  })
end

describe("show_tags", function()
  describe("filter_tags", function()
    local tags = { "bug", "debug", "meeting", "meeting-weekly", "review", "Bug" }

    it("should match a plain name against the whole tag, case-sensitively", function()
      assert.are.same({ "bug" }, renderer.filter_tags(tags, "bug"))
    end)

    it("should match any run of characters with '*'", function()
      assert.are.same({ "meeting", "meeting-weekly" }, renderer.filter_tags(tags, "meeting*"))
      assert.are.same({ "bug", "debug" }, renderer.filter_tags(tags, "*bug"))
    end)

    it("should match every tag with a lone '*'", function()
      assert.are.same(tags, renderer.filter_tags(tags, "*"))
    end)

    it("should match exactly one character with '?'", function()
      assert.are.same({ "bug", "Bug" }, renderer.filter_tags(tags, "?ug"))
    end)

    it("should treat Lua pattern characters literally", function()
      local odd = { "c++", "cxx", "v1.0", "v100", "50%", "a-b" }
      assert.are.same({ "c++" }, renderer.filter_tags(odd, "c++"))
      assert.are.same({ "v1.0" }, renderer.filter_tags(odd, "v1.0"))
      assert.are.same({ "50%" }, renderer.filter_tags(odd, "50%"))
      assert.are.same({ "a-b" }, renderer.filter_tags(odd, "a-b"))
    end)

    it("should accept a comma-separated string, ignoring spaces and empty entries", function()
      assert.are.same({ "bug", "meeting", "meeting-weekly", "review" },
        renderer.filter_tags(tags, " bug, review ,, meeting* "))
    end)

    it("should accept a list", function()
      assert.are.same({ "bug", "meeting", "meeting-weekly", "review" },
        renderer.filter_tags(tags, { "bug", "review", "meeting*" }))
    end)

    it("should keep the task's own tag order and list each tag once", function()
      assert.are.same({ "bug", "debug", "review" },
        renderer.filter_tags(tags, "review,*bug,bug"))
    end)

    it("should show nothing when unset or empty", function()
      assert.are.same({}, renderer.filter_tags(tags, nil))
      assert.are.same({}, renderer.filter_tags(tags, ""))
      assert.are.same({}, renderer.filter_tags(tags, {}))
      assert.are.same({}, renderer.filter_tags(nil, "*"))
    end)
  end)

  describe("in {{icons}}", function()
    it("should show no tags by default", function()
      assert.are.same("* [ ] Fix the login bug [⏰2025-12-25] [H] `abcdef12`", render(nil))
    end)

    it("should show the selected tags before the other icons", function()
      assert.are.same(
        "* [ ] Fix the login bug +bug +meeting +meeting-weekly +review [⏰2025-12-25] [H] `abcdef12`",
        render("bug,review,meeting*"))
    end)

    it("should show every tag with '*'", function()
      assert.are.same(
        "* [ ] Fix the login bug +bug +debug +meeting +meeting-weekly +review +backend [⏰2025-12-25] [H] `abcdef12`",
        render("*"))
    end)

    it("should show the tags before the completion date of a completed task", function()
      local task = tagged_task({ status = "completed", ["end"] = "20251201T000000Z" })
      task.due = nil
      assert.are.same("* [x] Fix the login bug +review {✅2025-12-01} [H] `abcdef12`", render("review", task))
    end)

    it("should leave no extra space when no tag matches", function()
      assert.are.same("* [ ] Fix the login bug [⏰2025-12-25] [H] `abcdef12`", render("nope*"))
      assert.are.same("* [ ] Fix the login bug [⏰2025-12-25] [H] `abcdef12`", render("*", tagged_task({ tags = {} })))
    end)

    it("should not filter the {{tags}} placeholder", function()
      assert.are.same("* [ ] Fix the login bug +bug +debug +meeting +meeting-weekly +review +backend `abcdef12`",
        render("bug", nil, "{{description}} {{tags}}"))
    end)
  end)

  describe("per workspace", function()
    local test_utils
    local plugin
    local original_run_shell_command

    before_each(function()
      test_utils = require("frontline.test_utils")
      test_utils.setup_mocks()
      original_run_shell_command = task_client._run_shell_command
      task_client._set_run_shell_command_mock(function(cmd)
        if string.find(cmd, "+BLOCKING", 1, true) or string.find(cmd, "depends.any:", 1, true) then
          return "[]", 0
        end
        return '[{"id":1,"description":"Write the docs","status":"pending",' ..
          '"tags":["docs","bug","meeting-weekly"],"uuid":"aaaa1111bbbb2222"}]', 0
      end)
    end)

    after_each(function()
      task_client._set_run_shell_command_mock(original_run_shell_command)
      test_utils.restore_mocks()
      package.loaded["frontline"] = nil
      package.loaded["frontline.test_utils"] = nil
    end)

    it("should use the workspace's own show_tags, falling back to the global one", function()
      plugin = require("frontline")
      plugin.setup({
        show_tags = "bug",
        workspaces = {
          work = { rc = "~/.taskrc-work", show_tags = { "meeting*", "docs" } },
          quiet = { rc = "~/.taskrc-quiet", show_tags = "" },
          personal = { rc = "~/.taskrc-personal" },
        },
      })

      test_utils.set_mock_buffer_content({
        "# Work | @work status:pending",
        "# Quiet | @quiet status:pending",
        "# Personal | @personal status:pending",
      })

      test_utils.execute_user_command("FrontlineRefresh")

      assert.are.same({
        "# Work | @work status:pending",
        "* [ ] Write the docs +docs +meeting-weekly `aaaa1111`",
        "",
        "",
        "# Quiet | @quiet status:pending",
        "* [ ] Write the docs `aaaa1111`",
        "",
        "",
        "# Personal | @personal status:pending",
        "* [ ] Write the docs +bug `aaaa1111`",
        "",
        "",
      }, test_utils.mock_buffer_content)
    end)
  end)
end)
