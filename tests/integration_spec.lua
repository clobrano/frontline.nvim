
local plugin
local task_client = require("frontline.task_client")

describe("Integration Tests: Automatic and Manual Refresh", function()
  local test_utils
  local original_run_shell_command

  before_each(function()
    -- Load test_utils here to ensure it's available
    test_utils = require("frontline.test_utils")
    -- Setup all Neovim mocks
    test_utils.setup_mocks()
    -- Save original task_client._run_shell_command
    original_run_shell_command = task_client._run_shell_command
    -- Load the plugin *after* mocks are set up
    plugin = require("frontline")
    -- Setup the plugin with mocks in place
    plugin.setup()
  end)

  after_each(function()
    -- Restore original task_client._run_shell_command
    task_client._set_run_shell_command_mock(original_run_shell_command)
    -- Restore all Neovim mocks after each test
    test_utils.restore_mocks()
    -- Clear the cached plugin module to ensure fresh load for next test
    package.loaded["frontline"] = nil
    package.loaded["frontline.test_utils"] = nil -- Also clear test_utils
  end)

  it("should refresh tasks automatically on BufReadPost for markdown files", function()
    local initial_content = {
      "# My Tasks | status:pending",
      "Existing content below header",
    }
    test_utils.set_mock_buffer_content(initial_content)

    local mock_task_output = '[{"id":1,"description":"New Task 1","status":"pending","uuid":"aaaa1111bbbb2222"}]'
    task_client._set_run_shell_command_mock(function(cmd)
      assert.truthy(string.find(cmd, "task status:pending export"))
      return mock_task_output, 0
    end)

    test_utils.trigger_autocmd("BufReadPost", 0)

    local expected_content = {
      "# My Tasks | status:pending",
      "* [ ] New Task 1 () (aaaa1111)",
      "Existing content below header",
    }
    assert.are.same(expected_content, test_utils.mock_buffer_content)
  end)

  it("should refresh tasks automatically on BufWritePost for markdown files", function()
    local initial_content = {
      "# My Tasks | status:pending",
      "* [ ] Old Task 1 () (cccc3333)",
      "Existing content below header",
    }
    test_utils.set_mock_buffer_content(initial_content)

    local mock_task_output = '[{"id":2,"description":"Updated Task 2","status":"pending","uuid":"dddd4444eeee5555"}]'
    task_client._set_run_shell_command_mock(function(cmd)
      assert.truthy(string.find(cmd, "task status:pending export"))
      return mock_task_output, 0
    end)

    test_utils.trigger_autocmd("BufWritePost", 0)

    local expected_content = {
      "# My Tasks | status:pending",
      "* [ ] Updated Task 2 () (dddd4444)",
      "Existing content below header",
    }
    assert.are.same(expected_content, test_utils.mock_buffer_content)
  end)

  it("should refresh tasks manually via :FrontlineRefresh command", function()
    local initial_content = {
      "# My Tasks | status:waiting",
      "Some text",
    }
    test_utils.set_mock_buffer_content(initial_content)

    local mock_task_output = '[{"id":3,"description":"Waiting Task","status":"pending","uuid":"ffff6666gggg7777"}]'
    task_client._set_run_shell_command_mock(function(cmd)
      assert.truthy(string.find(cmd, "task status:waiting export"))
      return mock_task_output, 0
    end)

    test_utils.execute_user_command("FrontlineRefresh")

    local expected_content = {
      "# My Tasks | status:waiting",
      "* [ ] Waiting Task () (ffff6666)",
      "Some text",
    }
    assert.are.same(expected_content, test_utils.mock_buffer_content)
  end)

  it("should not refresh for non-markdown files", function()
    local initial_content = {
      "# My Tasks | status:pending",
    }
    test_utils.set_mock_buffer_content(initial_content)
    test_utils.set_mock_filetype("lua")

    local task_client_called = false
    task_client._set_run_shell_command_mock(function(cmd)
      task_client_called = true
      return "[]", 0
    end)

    test_utils.trigger_autocmd("BufReadPost", 0)

    assert.is_false(task_client_called)
    assert.are.same(initial_content, test_utils.mock_buffer_content)
  end)

  it("should handle multiple query sections in a single file", function()
    local initial_content = {
      "# Work Tasks | project:work",
      "Existing work content",
      "## Personal Tasks | project:personal",
      "Existing personal content",
    }
    test_utils.set_mock_buffer_content(initial_content)

    local call_count = 0
    task_client._set_run_shell_command_mock(function(cmd)
      call_count = call_count + 1
      if string.find(cmd, "project:work") then
        return '[{"id":1,"description":"Work Task 1","status":"pending","uuid":"work1111work2222"}]' , 0
      elseif string.find(cmd, "project:personal") then
        return '[{"id":2,"description":"Personal Task 1","status":"pending","uuid":"pers3333pers4444"}]' , 0
      end
      return "[]", 0
    end)

    test_utils.trigger_autocmd("BufReadPost", 0)

    local expected_content = {
      "# Work Tasks | project:work",
      "* [ ] Work Task 1 () (work1111)",
      "## Personal Tasks | project:personal",
      "* [ ] Personal Task 1 () (pers3333)",
    }
    assert.are.same(expected_content, test_utils.mock_buffer_content)
    assert.are.same(2, call_count)
  end)
end)
