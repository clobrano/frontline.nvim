
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

  describe("Reverse Dependencies", function()
    it("should query reverse dependencies successfully", function()
      -- Mock returns task that depends on test-uuid
      local mock_json = '[{"uuid":"rev1","description":"Blocked task 1","status":"pending","depends":["test-uuid"]}]'
      task_client._set_run_shell_command_mock(function(cmd)
        assert.truthy(string.find(cmd, "depends.any:test%-uuid"))
        return mock_json, 0
      end)

      local reverse_deps, err = task_client.get_reverse_dependencies("test-uuid")
      assert.is_nil(err)
      assert.are.same(1, #reverse_deps)
      assert.are.same("rev1", reverse_deps[1].uuid)
      assert.are.same("Blocked task 1", reverse_deps[1].description)
    end)

    it("should handle no reverse dependencies", function()
      task_client._set_run_shell_command_mock(function(cmd)
        return '[]', 0
      end)

      local reverse_deps, err = task_client.get_reverse_dependencies("test-uuid")
      assert.is_nil(err)
      assert.are.same(0, #reverse_deps)
    end)

    it("should handle reverse dependency query failure", function()
      task_client._set_run_shell_command_mock(function(cmd)
        return "Error: invalid UUID", 1
      end)

      local reverse_deps, err = task_client.get_reverse_dependencies("bad-uuid")
      assert.is_nil(reverse_deps)
      assert.truthy(string.find(err, "Failed to query reverse dependencies"))
    end)

    it("should handle invalid JSON in reverse dependency response", function()
      task_client._set_run_shell_command_mock(function(cmd)
        return "Not valid JSON", 0
      end)

      local reverse_deps, err = task_client.get_reverse_dependencies("test-uuid")
      assert.is_nil(reverse_deps)
      assert.truthy(string.find(err, "Failed to parse reverse dependencies JSON"))
    end)

    it("should return multiple reverse dependencies", function()
      -- Mock returns multiple tasks that depend on test-uuid
      local mock_json = '[{"uuid":"rev1","description":"Task 1","status":"pending","depends":["test-uuid"]},{"uuid":"rev2","description":"Task 2","status":"completed","depends":["test-uuid","other-uuid"]}]'
      task_client._set_run_shell_command_mock(function(cmd)
        return mock_json, 0
      end)

      local reverse_deps, err = task_client.get_reverse_dependencies("test-uuid")
      assert.is_nil(err)
      assert.are.same(2, #reverse_deps)
      assert.are.same("rev1", reverse_deps[1].uuid)
      assert.are.same("rev2", reverse_deps[2].uuid)
    end)

    it("should filter out false positives from substring matching", function()
      -- Mock returns tasks with similar UUIDs but not exact match
      local mock_json = '[{"uuid":"rev1","description":"Match","status":"pending","depends":["test-uuid"]},{"uuid":"rev2","description":"False positive","status":"pending","depends":["other-test-uuid-different"]}]'
      task_client._set_run_shell_command_mock(function(cmd)
        return mock_json, 0
      end)

      local reverse_deps, err = task_client.get_reverse_dependencies("test-uuid")
      assert.is_nil(err)
      assert.are.same(1, #reverse_deps)
      assert.are.same("rev1", reverse_deps[1].uuid)
      assert.are.same("Match", reverse_deps[1].description)
    end)
  end)
end)
