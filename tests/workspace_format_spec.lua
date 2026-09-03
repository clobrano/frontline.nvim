local task_client = require("frontline.task_client")

-- The task line format is a per-workspace option: a workspace entry can set
-- task_format and task_bullet, and anything it leaves out falls back to the
-- global value. Views resolve it per query, from the @workspace in the header.
describe("Per-workspace task format", function()
  local test_utils
  local plugin
  local original_run_shell_command

  local function setup_plugin(opts)
    plugin = require("frontline")
    plugin.setup(opts)
  end

  before_each(function()
    test_utils = require("frontline.test_utils")
    test_utils.setup_mocks()
    original_run_shell_command = task_client._run_shell_command
    -- Every query returns the same single task, so the difference between the
    -- rendered lines is only ever the format that was used
    task_client._set_run_shell_command_mock(function(cmd)
      -- No task is blocking another, so no ⚓ creeps into the rendered lines
      if string.find(cmd, "+BLOCKING", 1, true) or string.find(cmd, "depends.any:", 1, true) then
        return "[]", 0
      end
      return '[{"id":1,"description":"Write the docs","status":"pending",' ..
        '"project":"frontline","priority":"H","uuid":"aaaa1111bbbb2222"}]', 0
    end)
  end)

  after_each(function()
    task_client._set_run_shell_command_mock(original_run_shell_command)
    test_utils.restore_mocks()
    package.loaded["frontline"] = nil
    package.loaded["frontline.test_utils"] = nil
  end)

  describe("option resolution", function()
    before_each(function()
      setup_plugin({
        task_format = "{{description}} {{icons}}",
        task_bullet = "*",
        workspaces = {
          -- Table form, overriding both options
          work = { rc = "~/.taskrc-work", task_format = "{{description}} {{project}}", task_bullet = "-" },
          -- Table form, overriding neither
          personal = { rc = "~/.taskrc-personal" },
          -- String form: no per-workspace options at all
          archive = "~/.taskrc-archive",
        },
      })
    end)

    it("should use the workspace's own format", function()
      assert.are.same("{{description}} {{project}}", plugin.get_workspace_option("work", "task_format"))
      assert.are.same("-", plugin.get_workspace_option("work", "task_bullet"))
    end)

    it("should fall back to the global format for a workspace that sets none", function()
      assert.are.same("{{description}} {{icons}}", plugin.get_workspace_option("personal", "task_format"))
      assert.are.same("*", plugin.get_workspace_option("personal", "task_bullet"))
    end)

    it("should fall back to the global format for a workspace given as a string", function()
      assert.are.same("{{description}} {{icons}}", plugin.get_workspace_option("archive", "task_format"))
    end)

    it("should fall back to the global format for an unknown workspace", function()
      assert.are.same("{{description}} {{icons}}", plugin.get_workspace_option("nope", "task_format"))
    end)

    it("should fall back to the global format when there is no workspace", function()
      assert.are.same("{{description}} {{icons}}", plugin.get_workspace_option(nil, "task_format"))
    end)
  end)

  it("should render each view with its own workspace's format", function()
    setup_plugin({
      task_format = "{{description}} {{icons}}",
      workspaces = {
        work = { rc = "~/.taskrc-work", task_format = "{{description}} {{project}}", task_bullet = "-" },
        personal = { rc = "~/.taskrc-personal" },
      },
    })

    test_utils.set_mock_buffer_content({
      "# Work | @work status:pending",
      "# Personal | @personal status:pending",
    })

    test_utils.execute_user_command("FrontlineRefresh")

    assert.are.same({
      "# Work | @work status:pending",
      "- [ ] Write the docs frontline `aaaa1111`",
      "",
      "",
      "# Personal | @personal status:pending",
      "* [ ] Write the docs [H] `aaaa1111`",
      "",
      "",
    }, test_utils.mock_buffer_content)
  end)

  it("should render a view with the global format when it names no workspace", function()
    setup_plugin({
      task_format = "{{description}} {{project}}",
      task_bullet = "+",
      workspaces = {
        work = { rc = "~/.taskrc-work", task_format = "{{description}}" },
      },
    })

    test_utils.set_mock_buffer_content({ "# Anything | status:pending" })

    test_utils.execute_user_command("FrontlineRefresh")

    assert.are.same({
      "# Anything | status:pending",
      "+ [ ] Write the docs frontline `aaaa1111`",
      "",
      "",
    }, test_utils.mock_buffer_content)
  end)

  it("should use the default workspace's format when the header names none", function()
    setup_plugin({
      task_format = "{{description}} {{icons}}",
      default_workspace = "work",
      workspaces = {
        work = { rc = "~/.taskrc-work", task_format = "{{description}} {{project}}", task_bullet = "-" },
      },
    })

    test_utils.set_mock_buffer_content({ "# Anything | status:pending" })

    test_utils.execute_user_command("FrontlineRefresh")

    assert.are.same({
      "# Anything | status:pending",
      "- [ ] Write the docs frontline `aaaa1111`",
      "",
      "",
    }, test_utils.mock_buffer_content)
  end)
end)
