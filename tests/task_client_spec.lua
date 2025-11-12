
local task_client = require("frontline.task_client")

describe("Task Client Module", function()
  local original_run_shell_command

  before_each(function()
    -- Save the original function and set up a mock for each test
    original_run_shell_command = task_client._run_shell_command
  end)

  after_each(function()
    -- Restore the original function after each test
    task_client._set_run_shell_command_mock(original_run_shell_command)
  end)

  it("should execute a query and parse valid JSON output", function()
    local mock_json_output = '[{"id":1,"description":"Test Task","status":"pending"}]'
    task_client._set_run_shell_command_mock(function(cmd)
      assert.truthy(string.find(cmd, "task 'project:test' export"))
      return mock_json_output, 0
    end)

    local tasks, err = task_client.execute_query("project:test")

    assert.is_nil(err)
    assert.are.same(1, #tasks)
    assert.are.same(1, tasks[1].id)
    assert.are.same("Test Task", tasks[1].description)
  end)

  it("should handle Taskwarrior command failure", function()
    task_client._set_run_shell_command_mock(function(cmd)
      return "Error: Invalid query", 1
    end)

    local tasks, err = task_client.execute_query("invalid_query")

    assert.is_nil(tasks)
    assert.truthy(string.find(err, "Taskwarrior command failed"))
  end)

  it("should handle invalid JSON output", function()
    task_client._set_run_shell_command_mock(function(cmd)
      return "This is not valid JSON", 0
    end)

    local tasks, err = task_client.execute_query("project:test")

    assert.is_nil(tasks)
    assert.truthy(string.find(err, "Failed to parse Taskwarrior JSON output"))
  end)

  it("should return an empty table for no tasks found", function()
    local mock_json_output = '[]'
    task_client._set_run_shell_command_mock(function(cmd)
      return mock_json_output, 0
    end)

    local tasks, err = task_client.execute_query("project:nonexistent")

    assert.is_nil(err)
    assert.are.same(0, #tasks)
  end)

  it("should properly quote complex queries with parentheses", function()
    local complex_query = "(end.after:sow end.before=eow) (due: or due.before=sow or due.after=eow) -TNFsprint279"
    local mock_json_output = '[{"id":1,"description":"Complex Task","status":"completed"}]'

    task_client._set_run_shell_command_mock(function(cmd)
      -- Verify the query is properly wrapped in single quotes
      local expected_pattern = "task '%(end%.after:sow end%.before=eow%) %(due: or due%.before=sow or due%.after=eow%) %-TNFsprint279' export"
      assert.truthy(string.find(cmd, expected_pattern), "Command should properly quote complex query with parentheses")
      return mock_json_output, 0
    end)

    local tasks, err = task_client.execute_query(complex_query)

    assert.is_nil(err)
    assert.are.same(1, #tasks)
    assert.are.same("Complex Task", tasks[1].description)
  end)
end)
