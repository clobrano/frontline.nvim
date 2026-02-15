
local renderer = require("frontline.renderer")

-- Helper to convert ISO date to local time using system date command
local function convert_iso_to_local(iso_date)
  -- Reformat from YYYYMMDDTHHmmssZ to YYYY-MM-DDTHH:MM:SSZ
  local formatted = string.gsub(iso_date, "(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)Z", "%1-%2-%3T%4:%5:%6Z")

  -- Use system date command
  local handle = io.popen(string.format("date -d '%s' '+%%Y-%%m-%%d %%H:%%M' 2>/dev/null", formatted))
  local result = handle:read("*a")
  handle:close()

  -- Trim whitespace
  result = result:gsub("^%s*(.-)%s*$", "%1")

  -- Apply midnight detection
  if result:match(" 00:00$") then
    return result:gsub(" 00:00$", "")
  end

  return result
end

-- Helper to extract date-only from local conversion (for end date tests)
local function convert_iso_to_local_date_only(iso_date)
  local full = convert_iso_to_local(iso_date)
  return string.match(full, "^(%d%d%d%d%-%d%d%-%d%d)") or full
end

-- Helper to format ISO date without conversion (raw)
local function format_iso_date_raw(iso_date)
  local year = string.sub(iso_date, 1, 4)
  local month = string.sub(iso_date, 5, 6)
  local day = string.sub(iso_date, 7, 8)
  local hour = string.sub(iso_date, 10, 11)
  local minute = string.sub(iso_date, 12, 13)

  if hour == "00" and minute == "00" then
    return string.format("%s-%s-%s", year, month, day)
  else
    return string.format("%s-%s-%s %s:%s", year, month, day, hour, minute)
  end
end

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
    
      it("should format a completed task without end date normally", function()
        local task = {
          id = 3,
          description = "Test Completed Task",
          status = "completed",
          uuid = "1234567890abcdef",
        }
        local expected = "* [x] Test Completed Task (12345678)"
        assert.are.same(expected, renderer.format_task(task))
      end)

      it("should format a completed task with end date in curly brackets", function()
        local task = {
          id = 31,
          description = "Completed with End Date",
          status = "completed",
          uuid = "enddate123456789",
          ["end"] = "20260115T143000Z",
        }
        local expected = "* [x] Completed with End Date {" .. convert_iso_to_local_date_only("20260115T143000Z") .. "} (enddate1)"
        assert.are.same(expected, renderer.format_task(task))
      end)

      it("should not show scheduled date for completed tasks", function()
        local task = {
          id = 32,
          description = "Completed with Scheduled",
          status = "completed",
          uuid = "compscheduled001",
          scheduled = "20260110T090000Z",
          ["end"] = "20260115T143000Z",
        }
        local expected = "* [x] Completed with Scheduled {" .. convert_iso_to_local_date_only("20260115T143000Z") .. "} (compsche)"
        assert.are.same(expected, renderer.format_task(task))
      end)

      it("should show due date but not scheduled date for completed tasks", function()
        local task = {
          id = 33,
          description = "Completed with All Dates",
          status = "completed",
          uuid = "compalldates0001",
          scheduled = "20260110T090000Z",
          due = "20260120T000000Z",
          ["end"] = "20260115T143000Z",
        }
        local expected = "* [x] Completed with All Dates {" .. convert_iso_to_local_date_only("20260115T143000Z") .. "} [" .. convert_iso_to_local("20260120T000000Z") .. "] (compalld)"
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
        -- Default is convert_to_local = true
        local expected = "* [ ] Task with Due Date [" .. convert_iso_to_local("20251225T103000Z") .. "] (abcabcab)"
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
        local expected = "* [ ] Task with Scheduled Date (" .. convert_iso_to_local("20251220T090000Z") .. ") (schedsch)"
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
        local expected = "* [ ] Task with Both Dates (" .. convert_iso_to_local("20251220T090000Z") .. ") [" .. convert_iso_to_local("20251225T103000Z") .. "] (bothboth)"
        assert.are.same(expected, renderer.format_task(task))
      end)

      it("should omit time for due date at midnight (00:00)", function()
        local task = {
          id = 43,
          description = "Task with Due Date at Midnight",
          status = "pending",
          due = "20251225T000000Z",
          uuid = "midnight00000001",
        }
        local expected = "* [ ] Task with Due Date at Midnight [" .. convert_iso_to_local("20251225T000000Z") .. "] (midnight)"
        assert.are.same(expected, renderer.format_task(task))
      end)

      it("should omit time for scheduled date at midnight (00:00)", function()
        local task = {
          id = 44,
          description = "Task with Scheduled at Midnight",
          status = "pending",
          scheduled = "20251220T000000Z",
          uuid = "schedmidnight001",
        }
        local expected = "* [ ] Task with Scheduled at Midnight (" .. convert_iso_to_local("20251220T000000Z") .. ") (schedmid)"
        assert.are.same(expected, renderer.format_task(task))
      end)

      it("should omit time for both dates at midnight", function()
        local task = {
          id = 45,
          description = "Both Dates at Midnight",
          status = "pending",
          scheduled = "20251220T000000Z",
          due = "20251225T000000Z",
          uuid = "bothmidnight0001",
        }
        local expected = "* [ ] Both Dates at Midnight (" .. convert_iso_to_local("20251220T000000Z") .. ") [" .. convert_iso_to_local("20251225T000000Z") .. "] (bothmidn)"
        assert.are.same(expected, renderer.format_task(task))
      end)
    
      it("should include high priority icon (🔴)", function()
        local task = {
          id = 5,
          description = "High Priority Task",
          status = "pending",
          priority = "H",
          uuid = "defdefdefdefdefd",
        }
        local expected = "* [ ] High Priority Task [🔴] (defdefde)"
        assert.are.same(expected, renderer.format_task(task))
      end)

      it("should include medium priority icon (🟠)", function()
        local task = {
          id = 51,
          description = "Medium Priority Task",
          status = "pending",
          priority = "M",
          uuid = "medmedmedmedmed1",
        }
        local expected = "* [ ] Medium Priority Task [🟠] (medmedme)"
        assert.are.same(expected, renderer.format_task(task))
      end)

      it("should include low priority icon (🟡)", function()
        local task = {
          id = 52,
          description = "Low Priority Task",
          status = "pending",
          priority = "L",
          uuid = "lowlowlowlowlow1",
        }
        local expected = "* [ ] Low Priority Task [🟡] (lowlowlo)"
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
        local expected = "* [ ] Annotated Task [🗒️] (55556666)"
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
        local expected = "* [ ] All Icons Task [" .. convert_iso_to_local("20251111T090000Z") .. "] [🟠🔒🗒️] (9999aaaa)"
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
        local expected = "* [ ] Complete Task (" .. convert_iso_to_local("20251110T080000Z") .. ") [" .. convert_iso_to_local("20251111T090000Z") .. "] [🔴🔒🗒️] (complete)"
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

      describe("Reverse dependencies (anchor icon)", function()
        it("should show anchor icon for tasks blocking others", function()
          local task = {
            description = "Task blocking others",
            status = "pending",
            uuid = "blocking123456",
            _reverse_deps = {
              {uuid = "rev1", description = "Blocked task"}
            }
          }
          local expected = "* [ ] Task blocking others [⚓] (blocking)"
          assert.are.same(expected, renderer.format_task(task))
        end)

        it("should show both lock and anchor icons", function()
          local task = {
            description = "Task with both dependency types",
            status = "pending",
            uuid = "both1234567890",
            depends = {"dep1"},
            _reverse_deps = {
              {uuid = "rev1", description = "Blocked task"}
            }
          }
          local expected = "* [ ] Task with both dependency types [🔒⚓] (both1234)"
          assert.are.same(expected, renderer.format_task(task))
        end)

        it("should not show anchor icon when _reverse_deps is empty", function()
          local task = {
            description = "Task blocking nothing",
            status = "pending",
            uuid = "noblock123456",
            _reverse_deps = {}
          }
          local expected = "* [ ] Task blocking nothing (noblock1)"
          assert.are.same(expected, renderer.format_task(task))
        end)

        it("should not show anchor icon when _reverse_deps is nil", function()
          local task = {
            description = "Task blocking nothing",
            status = "pending",
            uuid = "noblock223456"
          }
          local expected = "* [ ] Task blocking nothing (noblock2)"
          assert.are.same(expected, renderer.format_task(task))
        end)

        it("should show all icons in correct order", function()
          local task = {
            description = "Complete icon task",
            status = "pending",
            uuid = "allicons123456",
            priority = "H",
            depends = {"dep1"},
            _reverse_deps = {{uuid = "rev1"}},
            annotations = {{description = "note"}}
          }
          -- Order: priority, lock, anchor, annotations
          local expected = "* [ ] Complete icon task [🔴🔒⚓🗒️] (allicons)"
          assert.are.same(expected, renderer.format_task(task))
        end)

        it("should show anchor with priority but no lock", function()
          local task = {
            description = "Blocking task with priority",
            status = "pending",
            uuid = "blockingpriority",
            priority = "M",
            _reverse_deps = {{uuid = "rev1"}}
          }
          local expected = "* [ ] Blocking task with priority [🟠⚓] (blocking)"
          assert.are.same(expected, renderer.format_task(task))
        end)

        it("should show multiple reverse dependencies still shows one anchor", function()
          local task = {
            description = "Blocking multiple tasks",
            status = "pending",
            uuid = "multipleblocker",
            _reverse_deps = {
              {uuid = "rev1", description = "Task 1"},
              {uuid = "rev2", description = "Task 2"},
              {uuid = "rev3", description = "Task 3"}
            }
          }
          local expected = "* [ ] Blocking multiple tasks [⚓] (multiple)"
          assert.are.same(expected, renderer.format_task(task))
        end)
      end)

      describe("Date conversion modes", function()
        it("should convert UTC to local when convert_to_local is true (default)", function()
          local task = {
            id = 100,
            description = "Task with conversion",
            status = "pending",
            due = "20251225T103000Z",
            uuid = "conversiontest01",
          }
          local expected = "* [ ] Task with conversion [" .. convert_iso_to_local("20251225T103000Z") .. "] (conversi)"
          assert.are.same(expected, renderer.format_task(task, true))
        end)

        it("should display time as-is when convert_to_local is false", function()
          local task = {
            id = 101,
            description = "Task without conversion",
            status = "pending",
            due = "20251225T103000Z",
            uuid = "noconversionte01",
          }
          local expected = "* [ ] Task without conversion [" .. format_iso_date_raw("20251225T103000Z") .. "] (noconver)"
          assert.are.same(expected, renderer.format_task(task, false))
        end)

        it("should apply midnight detection to converted time", function()
          local task = {
            id = 102,
            description = "Midnight after conversion",
            status = "pending",
            due = "20251225T000000Z",
            uuid = "midnighttest001",
          }
          local expected = "* [ ] Midnight after conversion [" .. convert_iso_to_local("20251225T000000Z") .. "] (midnight)"
          assert.are.same(expected, renderer.format_task(task, true))
        end)

        it("should apply midnight detection to non-converted time", function()
          local task = {
            id = 103,
            description = "Midnight without conversion",
            status = "pending",
            due = "20251225T000000Z",
            uuid = "midnightnoconv1",
          }
          -- Midnight in UTC (00:00) should be omitted
          local expected = "* [ ] Midnight without conversion [2025-12-25] (midnight)"
          assert.are.same(expected, renderer.format_task(task, false))
        end)
      end)

end)
