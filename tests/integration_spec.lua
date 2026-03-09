
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

describe("show_blocking_dependencies", function()
  local test_utils
  local mappings
  local original_run_shell_command

  before_each(function()
    test_utils = require("frontline.test_utils")
    test_utils.setup_mocks()
    original_run_shell_command = task_client._run_shell_command
    plugin = require("frontline")
    plugin.setup({})
    mappings = require("frontline.mappings")
  end)

  after_each(function()
    task_client._set_run_shell_command_mock(original_run_shell_command)
    test_utils.restore_mocks()
    package.loaded["frontline"] = nil
    package.loaded["frontline.mappings"] = nil
    package.loaded["frontline.test_utils"] = nil
  end)

  it("should show tasks blocking this task (forward deps)", function()
    local original_get_current_line = vim.api.nvim_get_current_line
    vim.api.nvim_get_current_line = function()
      return "* [ ] Dependent task (dep01234)"
    end

    local echo_chunks_received = nil
    local original_echo = vim.api.nvim_echo
    vim.api.nvim_echo = function(chunks, ...)
      echo_chunks_received = chunks
    end

    task_client._set_run_shell_command_mock(function(cmd)
      if string.find(cmd, "'dep01234' export") then
        return '[{"uuid":"dep01234-full-uuid","description":"Dependent task","status":"pending","depends":["blocker-uuid"]}]', 0
      elseif string.find(cmd, "'blocker%-uuid' export") then
        return '[{"uuid":"blocker-uuid","description":"Blocking task","status":"pending"}]', 0
      end
      return '[]', 0
    end)

    mappings.show_blocking_dependencies()

    assert.is_not_nil(echo_chunks_received, "Echo should be called")
    local output_text = ""
    for _, chunk in ipairs(echo_chunks_received) do
      output_text = output_text .. chunk[1]
    end
    assert.truthy(string.find(output_text, "Tasks blocking this task"), "Should show 'Tasks blocking this task' section")
    assert.truthy(string.find(output_text, "Blocking task"), "Should show the blocking task description")

    vim.api.nvim_get_current_line = original_get_current_line
    vim.api.nvim_echo = original_echo
  end)

  it("should notify when task has no blocking dependencies", function()
    local original_get_current_line = vim.api.nvim_get_current_line
    vim.api.nvim_get_current_line = function()
      return "* [ ] Standalone task (solo1234)"
    end

    local notify_msg = nil
    local original_notify = vim.notify
    vim.notify = function(msg, ...) notify_msg = msg end

    task_client._set_run_shell_command_mock(function(cmd)
      if string.find(cmd, "'solo1234' export") then
        return '[{"uuid":"solo1234-full-uuid","description":"Standalone task","status":"pending"}]', 0
      end
      return '[]', 0
    end)

    mappings.show_blocking_dependencies()

    assert.truthy(notify_msg, "Should send a notification")
    assert.truthy(string.find(notify_msg, "no blocking dependencies"), "Should say 'no blocking dependencies'")

    vim.api.nvim_get_current_line = original_get_current_line
    vim.notify = original_notify
  end)
end)

describe("show_blocked_tasks", function()
  local test_utils
  local mappings
  local original_run_shell_command

  before_each(function()
    test_utils = require("frontline.test_utils")
    test_utils.setup_mocks()
    original_run_shell_command = task_client._run_shell_command
    plugin = require("frontline")
    plugin.setup({})
    mappings = require("frontline.mappings")
  end)

  after_each(function()
    task_client._set_run_shell_command_mock(original_run_shell_command)
    test_utils.restore_mocks()
    package.loaded["frontline"] = nil
    package.loaded["frontline.mappings"] = nil
    package.loaded["frontline.test_utils"] = nil
  end)

  it("should show tasks this task is blocking (reverse deps)", function()
    local original_get_current_line = vim.api.nvim_get_current_line
    vim.api.nvim_get_current_line = function()
      return "* [ ] Blocking task (abcd1234)"
    end

    local echo_chunks_received = nil
    local original_echo = vim.api.nvim_echo
    vim.api.nvim_echo = function(chunks, ...)
      echo_chunks_received = chunks
    end

    task_client._set_run_shell_command_mock(function(cmd)
      if string.find(cmd, "'abcd1234' export") then
        return '[{"uuid":"abcd1234-full-uuid","description":"Blocking task","status":"pending"}]', 0
      elseif string.find(cmd, "depends.any:abcd1234%-full%-uuid") then
        return '[{"uuid":"blocked-uuid","description":"Waiting task","status":"pending","depends":["abcd1234-full-uuid"]}]', 0
      end
      return '[]', 0
    end)

    mappings.show_blocked_tasks()

    assert.is_not_nil(echo_chunks_received, "Echo should be called")
    local output_text = ""
    for _, chunk in ipairs(echo_chunks_received) do
      output_text = output_text .. chunk[1]
    end
    assert.truthy(string.find(output_text, "Tasks this task is blocking"), "Should show 'Tasks this task is blocking' section")
    assert.truthy(string.find(output_text, "Waiting task"), "Should show the blocked task description")

    vim.api.nvim_get_current_line = original_get_current_line
    vim.api.nvim_echo = original_echo
  end)

  it("should notify when task is not blocking any other task", function()
    local original_get_current_line = vim.api.nvim_get_current_line
    vim.api.nvim_get_current_line = function()
      return "* [ ] Leaf task (leaf1234)"
    end

    local notify_msg = nil
    local original_notify = vim.notify
    vim.notify = function(msg, ...) notify_msg = msg end

    task_client._set_run_shell_command_mock(function(cmd)
      if string.find(cmd, "'leaf1234' export") then
        return '[{"uuid":"leaf1234-full-uuid","description":"Leaf task","status":"pending"}]', 0
      elseif string.find(cmd, "depends.any:leaf1234%-full%-uuid") then
        return '[]', 0
      end
      return '[]', 0
    end)

    mappings.show_blocked_tasks()

    assert.truthy(notify_msg, "Should send a notification")
    assert.truthy(string.find(notify_msg, "not blocking"), "Should say task is not blocking anything")

    vim.api.nvim_get_current_line = original_get_current_line
    vim.notify = original_notify
  end)

  it("should work regardless of enable_reverse_dependencies config", function()
    -- Reconfigure with reverse deps disabled
    plugin.setup({ enable_reverse_dependencies = false })
    mappings = require("frontline.mappings")

    local original_get_current_line = vim.api.nvim_get_current_line
    vim.api.nvim_get_current_line = function()
      return "* [ ] Some task (task1234)"
    end

    local echo_chunks_received = nil
    local original_echo = vim.api.nvim_echo
    vim.api.nvim_echo = function(chunks, ...)
      echo_chunks_received = chunks
    end

    local reverse_dep_queried = false
    task_client._set_run_shell_command_mock(function(cmd)
      if string.find(cmd, "'task1234' export") then
        return '[{"uuid":"task1234-full-uuid","description":"Some task","status":"pending"}]', 0
      elseif string.find(cmd, "depends.any:task1234%-full%-uuid") then
        reverse_dep_queried = true
        return '[{"uuid":"blocked-uuid","description":"Blocked task","status":"pending","depends":["task1234-full-uuid"]}]', 0
      end
      return '[]', 0
    end)

    mappings.show_blocked_tasks()

    assert.is_true(reverse_dep_queried, "Reverse deps should always be queried")
    assert.is_not_nil(echo_chunks_received, "Echo should be called to display results")

    local output_text = ""
    for _, chunk in ipairs(echo_chunks_received) do
      output_text = output_text .. chunk[1]
    end
    assert.truthy(string.find(output_text, "Tasks this task is blocking"), "Should show 'Tasks this task is blocking' section")
    assert.truthy(string.find(output_text, "Blocked task"), "Should show the blocked task description")

    vim.api.nvim_get_current_line = original_get_current_line
    vim.api.nvim_echo = original_echo
  end)
end)
