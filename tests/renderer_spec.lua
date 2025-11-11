
local renderer = require("frontline.renderer")

describe("Renderer Module", function()
  it("should format a pending task correctly", function()
    local task = {
      id = 1,
      description = "Test Pending Task",
      status = "pending",
      uuid = "abcdef1234567890",
    }
        local expected = "* [ ] Test Pending Task () (abcdef12)"
        assert.are.same(expected, renderer.format_task(task))
      end)
    
      it("should format a started task correctly", function()
        local task = {
          id = 2,
          description = "Test Started Task",
          status = "pending", -- Taskwarrior marks started tasks as pending with a 'start' attribute
          start = "20251110T100000Z",
          uuid = "fedcba9876543210",
        }
        local expected = "* [S] Test Started Task () (fedcba98)"
        assert.are.same(expected, renderer.format_task(task))
      end)
    
      it("should format a completed task correctly", function()
        local task = {
          id = 3,
          description = "Test Completed Task",
          status = "completed",
          uuid = "1234567890abcdef",
        }
        local expected = "* [x] Test Completed Task () (12345678)"
        assert.are.same(expected, renderer.format_task(task))
      end)
    
      it("should include due date if present", function()
        local task = {
          id = 4,
          description = "Task with Due Date",
          status = "pending",
          due = "20251225T103000Z",
          uuid = "abcabcabcabcabca",
        }
        local expected = "* [ ] Task with Due Date (2025-12-25 10:30) (abcabcab)"
        assert.are.same(expected, renderer.format_task(task))
      end)
    
      it("should include priority icon if present", function()
        local task = {
          id = 5,
          description = "High Priority Task",
          status = "pending",
          priority = "H",
          uuid = "defdefdefdefdefd",
        }
        local expected = "* [ ] High Priority Task () [H] (defdefde)"
        assert.are.same(expected, renderer.format_task(task))
      end)
    
      it("should include dependency icon if present", function()
        local task = {
          id = 6,
          description = "Dependent Task",
          status = "pending",
          depends = {"some-uuid"},
          uuid = "1111222233334444",
        }
        local expected = "* [ ] Dependent Task () [🔒] (11112222)"
        assert.are.same(expected, renderer.format_task(task))
      end)
    
      it("should include annotation icon if present", function()
        local task = {
          id = 7,
          description = "Annotated Task",
          status = "pending",
          annotations = {{description = "Some note"}},
          uuid = "5555666677778888",
        }
        local expected = "* [ ] Annotated Task () [A] (55556666)"
        assert.are.same(expected, renderer.format_task(task))
      end)
    
      it("should combine all extra icons if present", function()
        local task = {
          id = 8,
          description = "All Icons Task",
          status = "pending",
          due = "20251111T090000Z",
          priority = "M",
          depends = {"dep-uuid"},
          annotations = {{description = "Another note"}},
          uuid = "9999aaaabbbbcccc",
        }
        local expected = "* [ ] All Icons Task (2025-11-11 09:00) [M,🔒,A] (9999aaaa)"
        assert.are.same(expected, renderer.format_task(task))
      end)
    
      it("should handle task with no optional fields", function()
        local task = {
          id = 9,
          description = "Simple Task",
          status = "pending",
          uuid = "dddeeefff0001111",
        }
        local expected = "* [ ] Simple Task () (dddeeeff)"
        assert.are.same(expected, renderer.format_task(task))
      end)
    
      it("should handle empty description", function()
        local task = {
          id = 10,
          description = "",
          status = "pending",
          uuid = "2222333344445555",
        }
        local expected = "* [ ]  () (22223333)"
        assert.are.same(expected, renderer.format_task(task))
      end)
    
end)
