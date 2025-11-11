
local renderer = require("frontline.renderer")

describe("Renderer Module", function()
  it("should format a pending task correctly", function()
    local task = {
      id = 1,
      description = "Test Pending Task",
      status = "pending",
      uuid = "abcdef1234567890",
    }
        local expected = "* [ ] Test Pending Task (abcdef12)"
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
        local expected = "* [S] Test Started Task (fedcba98)"
        assert.are.same(expected, renderer.format_task(task))
      end)
    
      it("should format a completed task correctly", function()
        local task = {
          id = 3,
          description = "Test Completed Task",
          status = "completed",
          uuid = "1234567890abcdef",
        }
        local expected = "* [x] Test Completed Task (12345678)"
        assert.are.same(expected, renderer.format_task(task))
      end)
    
      it("should include due date if present (squared brackets)", function()
        local task = {
          id = 4,
          description = "Task with Due Date",
          status = "pending",
          due = "20251225T103000Z",
          uuid = "abcabcabcabcabca",
        }
        local expected = "* [ ] Task with Due Date [2025-12-25 10:30] (abcabcab)"
        assert.are.same(expected, renderer.format_task(task))
      end)

      it("should include scheduled date if present (rounded parenthesis)", function()
        local task = {
          id = 41,
          description = "Task with Scheduled Date",
          status = "pending",
          scheduled = "20251220T090000Z",
          uuid = "schedschedsched1",
        }
        local expected = "* [ ] Task with Scheduled Date (2025-12-20 09:00) (schedsch)"
        assert.are.same(expected, renderer.format_task(task))
      end)

      it("should include both scheduled and due dates", function()
        local task = {
          id = 42,
          description = "Task with Both Dates",
          status = "pending",
          scheduled = "20251220T090000Z",
          due = "20251225T103000Z",
          uuid = "bothbothbothbot1",
        }
        local expected = "* [ ] Task with Both Dates (2025-12-20 09:00) [2025-12-25 10:30] (bothboth)"
        assert.are.same(expected, renderer.format_task(task))
      end)
    
      it("should include high priority icon (!!!)", function()
        local task = {
          id = 5,
          description = "High Priority Task",
          status = "pending",
          priority = "H",
          uuid = "defdefdefdefdefd",
        }
        local expected = "* [ ] High Priority Task [!!!] (defdefde)"
        assert.are.same(expected, renderer.format_task(task))
      end)

      it("should include medium priority icon (!!)", function()
        local task = {
          id = 51,
          description = "Medium Priority Task",
          status = "pending",
          priority = "M",
          uuid = "medmedmedmedmed1",
        }
        local expected = "* [ ] Medium Priority Task [!!] (medmedme)"
        assert.are.same(expected, renderer.format_task(task))
      end)

      it("should include low priority icon (!)", function()
        local task = {
          id = 52,
          description = "Low Priority Task",
          status = "pending",
          priority = "L",
          uuid = "lowlowlowlowlow1",
        }
        local expected = "* [ ] Low Priority Task [!] (lowlowlo)"
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
        local expected = "* [ ] Dependent Task [🔒] (11112222)"
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
        local expected = "* [ ] Annotated Task [A] (55556666)"
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
        local expected = "* [ ] All Icons Task [2025-11-11 09:00] [!!,🔒,A] (9999aaaa)"
        assert.are.same(expected, renderer.format_task(task))
      end)

      it("should combine scheduled, due, and icons", function()
        local task = {
          id = 81,
          description = "Complete Task",
          status = "pending",
          scheduled = "20251110T080000Z",
          due = "20251111T090000Z",
          priority = "H",
          depends = {"dep-uuid"},
          annotations = {{description = "Another note"}},
          uuid = "completecomplete",
        }
        local expected = "* [ ] Complete Task (2025-11-10 08:00) [2025-11-11 09:00] [!!!,🔒,A] (complete)"
        assert.are.same(expected, renderer.format_task(task))
      end)
    
      it("should handle task with no optional fields", function()
        local task = {
          id = 9,
          description = "Simple Task",
          status = "pending",
          uuid = "dddeeefff0001111",
        }
        local expected = "* [ ] Simple Task (dddeeeff)"
        assert.are.same(expected, renderer.format_task(task))
      end)
    
      it("should handle empty description", function()
        local task = {
          id = 10,
          description = "",
          status = "pending",
          uuid = "2222333344445555",
        }
        local expected = "* [ ]  (22223333)"
        assert.are.same(expected, renderer.format_task(task))
      end)
    
end)
