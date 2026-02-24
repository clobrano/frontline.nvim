
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
    -- Setup the plugin with mocks in place (enable reverse dependencies for tests)
    plugin.setup({ enable_reverse_dependencies = true })
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
      "## Other Section",
      "Some other content",
    }
    test_utils.set_mock_buffer_content(initial_content)

    local mock_task_output = '[{"id":1,"description":"New Task 1","status":"pending","uuid":"aaaa1111bbbb2222"}]'
    task_client._set_run_shell_command_mock(function(cmd)
      if string.find(cmd, "task 'status:pending' export") then
        return mock_task_output, 0
      elseif string.find(cmd, "depends.any:") then
        -- No reverse dependencies
        return '[]', 0
      end
      return '[]', 0
    end)

    test_utils.trigger_autocmd("BufReadPost", 0)

    local expected_content = {
      "# My Tasks | status:pending",
      "* [ ] New Task 1 (aaaa1111)",
      "",
      "",
      "## Other Section",
      "Some other content",
    }
    assert.are.same(expected_content, test_utils.mock_buffer_content)
  end)

  it("should refresh tasks automatically on BufWritePost for markdown files", function()
    local initial_content = {
      "# My Tasks | status:pending",
      "* [ ] Old Task 1 () (cccc3333)",
      "## Other Section",
      "Existing content below header",
    }
    test_utils.set_mock_buffer_content(initial_content)

    local mock_task_output = '[{"id":2,"description":"Updated Task 2","status":"pending","uuid":"dddd4444eeee5555"}]'
    task_client._set_run_shell_command_mock(function(cmd)
      if string.find(cmd, "task 'status:pending' export") then
        return mock_task_output, 0
      elseif string.find(cmd, "depends.any:") then
        return '[]', 0
      end
      return '[]', 0
    end)

    test_utils.trigger_autocmd("BufWritePost", 0)

    local expected_content = {
      "# My Tasks | status:pending",
      "* [ ] Updated Task 2 (dddd4444)",
      "",
      "",
      "## Other Section",
      "Existing content below header",
    }
    assert.are.same(expected_content, test_utils.mock_buffer_content)
  end)

  it("should refresh tasks manually via :FrontlineRefresh command", function()
    local initial_content = {
      "# My Tasks | status:waiting",
      "Some text",
      "## Another Section",
      "More content",
    }
    test_utils.set_mock_buffer_content(initial_content)

    local mock_task_output = '[{"id":3,"description":"Waiting Task","status":"pending","uuid":"ffff6666gggg7777"}]'
    task_client._set_run_shell_command_mock(function(cmd)
      if string.find(cmd, "task 'status:waiting' export") then
        return mock_task_output, 0
      elseif string.find(cmd, "depends.any:") then
        return '[]', 0
      end
      return '[]', 0
    end)

    test_utils.execute_user_command("FrontlineRefresh")

    local expected_content = {
      "# My Tasks | status:waiting",
      "* [ ] Waiting Task (ffff6666)",
      "",
      "",
      "## Another Section",
      "More content",
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
      elseif string.find(cmd, "depends.any:") then
        return '[]', 0
      end
      return "[]", 0
    end)

    test_utils.trigger_autocmd("BufReadPost", 0)

    local expected_content = {
      "# Work Tasks | project:work",
      "* [ ] Work Task 1 (work1111)",
      "",
      "",
      "## Personal Tasks | project:personal",
      "* [ ] Personal Task 1 (pers3333)",
      "",
      "",
    }
    assert.are.same(expected_content, test_utils.mock_buffer_content)
    -- Now we expect 4 calls: 2 main queries + 2 reverse dependency queries
    assert.are.same(4, call_count)
  end)

  it("should fetch and display reverse dependencies with anchor icon during refresh", function()
    -- Mock buffer with task query
    test_utils.set_mock_buffer_content({
      "# My Tasks | status:pending",
      ""
    })

    -- Track which commands are called
    local main_query_called = false
    local reverse_dep_called = false

    task_client._set_run_shell_command_mock(function(cmd)
      if string.find(cmd, "status:pending") then
        main_query_called = true
        -- Return task with dependencies that will trigger reverse dep query
        return '[{"uuid":"task1uuid","description":"Main task","status":"pending"}]', 0
      elseif string.find(cmd, "depends.any:task1uuid") then
        reverse_dep_called = true
        -- Return a task that depends on task1 (must include depends field!)
        return '[{"uuid":"blocked1uuid","description":"Blocked task","status":"pending","depends":["task1uuid"]}]', 0
      end
      return '[]', 0
    end)

    plugin.refresh_current_buffer()

    -- Verify reverse dependency was queried
    assert.is_true(main_query_called, "Main query should be called")
    assert.is_true(reverse_dep_called, "Reverse dependency query should be called")

    -- Verify rendered output includes anchor icon
    local buffer_lines = test_utils.mock_buffer_content
    assert.truthy(string.find(buffer_lines[2], "⚓"), "Output should contain anchor icon")
    assert.truthy(string.find(buffer_lines[2], "Main task"), "Output should contain task description")
  end)

  it("should not show anchor icon when task has no reverse dependencies", function()
    test_utils.set_mock_buffer_content({
      "# My Tasks | status:pending",
      ""
    })

    task_client._set_run_shell_command_mock(function(cmd)
      if string.find(cmd, "status:pending") then
        return '[{"uuid":"task2uuid","description":"Standalone task","status":"pending"}]', 0
      elseif string.find(cmd, "depends.any:task2uuid") then
        -- No tasks depend on this one
        return '[]', 0
      end
      return '[]', 0
    end)

    plugin.refresh_current_buffer()

    local buffer_lines = test_utils.mock_buffer_content
    assert.is_falsy(string.find(buffer_lines[2], "⚓"), "Output should not contain anchor icon")
    assert.truthy(string.find(buffer_lines[2], "Standalone task"), "Output should contain task description")
  end)

  it("should sort tasks by urgency (highest first)", function()
    local initial_content = {
      "# My Tasks | status:pending",
      "",
    }
    test_utils.set_mock_buffer_content(initial_content)

    -- Return tasks with different urgency values, in non-sorted order
    local mock_task_output = vim.fn.json_encode({
      {id=1, description="Low urgency task", status="pending", uuid="lowurg1111111111", urgency=1.5},
      {id=2, description="High urgency task", status="pending", uuid="highurg222222222", urgency=19.7},
      {id=3, description="Medium urgency task", status="pending", uuid="medurg3333333333", urgency=8.2},
    })

    task_client._set_run_shell_command_mock(function(cmd)
      if string.find(cmd, "status:pending") then
        return mock_task_output, 0
      elseif string.find(cmd, "depends.any:") then
        return '[]', 0
      end
      return '[]', 0
    end)

    plugin.refresh_current_buffer()

    local buffer_lines = test_utils.mock_buffer_content
    -- Tasks should be sorted: high (19.7), medium (8.2), low (1.5)
    assert.truthy(string.find(buffer_lines[2], "High urgency task"), "First task should be highest urgency")
    assert.truthy(string.find(buffer_lines[3], "Medium urgency task"), "Second task should be medium urgency")
    assert.truthy(string.find(buffer_lines[4], "Low urgency task"), "Third task should be lowest urgency")
  end)

  it("should sort tasks with missing urgency field last", function()
    local initial_content = {
      "# My Tasks | status:pending",
      "",
    }
    test_utils.set_mock_buffer_content(initial_content)

    local mock_task_output = vim.fn.json_encode({
      {id=1, description="No urgency task", status="pending", uuid="nourg11111111111"},
      {id=2, description="Has urgency task", status="pending", uuid="hasurg2222222222", urgency=5.0},
    })

    task_client._set_run_shell_command_mock(function(cmd)
      if string.find(cmd, "status:pending") then
        return mock_task_output, 0
      elseif string.find(cmd, "depends.any:") then
        return '[]', 0
      end
      return '[]', 0
    end)

    plugin.refresh_current_buffer()

    local buffer_lines = test_utils.mock_buffer_content
    -- Task with urgency should come first, task without urgency last
    assert.truthy(string.find(buffer_lines[2], "Has urgency task"), "Task with urgency should come first")
    assert.truthy(string.find(buffer_lines[3], "No urgency task"), "Task without urgency should come last")
  end)

  it("should sort completed and deleted tasks after active tasks", function()
    local initial_content = {
      "# My Tasks | status:any",
      "",
    }
    test_utils.set_mock_buffer_content(initial_content)

    local mock_task_output = vim.fn.json_encode({
      {id=1, description="Completed task",  status="completed", uuid="comp1111111111111", urgency=20.0},
      {id=2, description="Pending task",    status="pending",   uuid="pend2222222222222", urgency=5.0},
      {id=3, description="Deleted task",    status="deleted",   uuid="delt3333333333333", urgency=15.0},
      {id=4, description="Started task",    status="pending",   uuid="star4444444444444", urgency=8.0},
    })

    task_client._set_run_shell_command_mock(function(cmd)
      if string.find(cmd, "status:any") then
        return mock_task_output, 0
      elseif string.find(cmd, "depends.any:") then
        return '[]', 0
      end
      return '[]', 0
    end)

    plugin.refresh_current_buffer()

    local buffer_lines = test_utils.mock_buffer_content
    -- Active tasks first (sorted by urgency: started=8.0, pending=5.0),
    -- then done tasks (sorted by urgency: completed=20.0, deleted=15.0)
    assert.truthy(string.find(buffer_lines[2], "Started task"),   "First line should be highest-urgency active task")
    assert.truthy(string.find(buffer_lines[3], "Pending task"),   "Second line should be second-highest-urgency active task")
    assert.truthy(string.find(buffer_lines[4], "Completed task"), "Third line should be highest-urgency done task")
    assert.truthy(string.find(buffer_lines[5], "Deleted task"),   "Fourth line should be lowest-urgency done task")
  end)

  it("should show both lock and anchor icons when task has both dependency types", function()
    test_utils.set_mock_buffer_content({
      "# My Tasks | status:pending",
      ""
    })

    task_client._set_run_shell_command_mock(function(cmd)
      if string.find(cmd, "status:pending") then
        -- Return task with both dependencies (depends) and reverse dependencies (blocking others)
        return '[{"uuid":"task3uuid","description":"Complex task","status":"pending","depends":["dep1uuid"]}]', 0
      elseif string.find(cmd, "depends.any:task3uuid") then
        -- This task blocks another task (must include depends field!)
        return '[{"uuid":"blocked2uuid","description":"Blocked by complex","status":"pending","depends":["task3uuid"]}]', 0
      end
      return '[]', 0
    end)

    plugin.refresh_current_buffer()

    local buffer_lines = test_utils.mock_buffer_content
    -- Should contain both lock and anchor icons
    assert.truthy(string.find(buffer_lines[2], "🔒"), "Output should contain lock icon")
    assert.truthy(string.find(buffer_lines[2], "⚓"), "Output should contain anchor icon")
    assert.truthy(string.find(buffer_lines[2], "Complex task"), "Output should contain task description")
  end)
end)
