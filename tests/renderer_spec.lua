
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
        local expected = "* [ ] Test Pending Task `abcdef12`"
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
        local expected = "* [S] Test Started Task `fedcba98`"
        assert.are.same(expected, renderer.format_task(task))
      end)
    
      it("should format a completed task without end date normally", function()
        local task = {
          id = 3,
          description = "Test Completed Task",
          status = "completed",
          uuid = "1234567890abcdef",
        }
        local expected = "* [x] Test Completed Task `12345678`"
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
        local expected = "* [x] Completed with End Date {✅" .. convert_iso_to_local_date_only("20260115T143000Z") .. "} `enddate1`"
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
        local expected = "* [x] Completed with Scheduled {✅" .. convert_iso_to_local_date_only("20260115T143000Z") .. "} `compsche`"
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
        local expected = "* [x] Completed with All Dates {✅" .. convert_iso_to_local_date_only("20260115T143000Z") .. "} [⏰" .. convert_iso_to_local("20260120T000000Z") .. "] `compalld`"
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
        local expected = "* [ ] Task with Due Date [⏰" .. convert_iso_to_local("20251225T103000Z") .. "] `abcabcab`"
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
        local expected = "* [ ] Task with Scheduled Date (⏱️" .. convert_iso_to_local("20251220T090000Z") .. ") `schedsch`"
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
        local expected = "* [ ] Task with Both Dates (⏱️" .. convert_iso_to_local("20251220T090000Z") .. ") [⏰" .. convert_iso_to_local("20251225T103000Z") .. "] `bothboth`"
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
        local expected = "* [ ] Task with Due Date at Midnight [⏰" .. convert_iso_to_local("20251225T000000Z") .. "] `midnight`"
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
        local expected = "* [ ] Task with Scheduled at Midnight (⏱️" .. convert_iso_to_local("20251220T000000Z") .. ") `schedmid`"
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
        local expected = "* [ ] Both Dates at Midnight (⏱️" .. convert_iso_to_local("20251220T000000Z") .. ") [⏰" .. convert_iso_to_local("20251225T000000Z") .. "] `bothmidn`"
        assert.are.same(expected, renderer.format_task(task))
      end)
    
      it("should show the priority value", function()
        local task = {
          id = 5,
          description = "High Priority Task",
          status = "pending",
          priority = "H",
          uuid = "defdefdefdefdefd",
        }
        local expected = "* [ ] High Priority Task [H] `defdefde`"
        assert.are.same(expected, renderer.format_task(task))
      end)

      it("should show a custom priority value as configured in Taskwarrior", function()
        local task = {
          id = 51,
          description = "Custom Priority Task",
          status = "pending",
          priority = "A",
          uuid = "medmedmedmedmed1",
        }
        local expected = "* [ ] Custom Priority Task [A] `medmedme`"
        assert.are.same(expected, renderer.format_task(task))
      end)

      it("should show the configured label instead of the value when mapped", function()
        local task = {
          id = 52,
          description = "Low Priority Task",
          status = "pending",
          priority = "L",
          uuid = "lowlowlowlowlow1",
        }
        local expected = "* [ ] Low Priority Task [↓] `lowlowlo`"
        assert.are.same(expected, renderer.format_task(task, nil, nil, { H = "↑", M = "-", L = "↓" }))
      end)

      it("should ignore an empty priority", function()
        local task = {
          id = 53,
          description = "Unset Priority Task",
          status = "pending",
          priority = "",
          uuid = "unsetunsetunset1",
        }
        local expected = "* [ ] Unset Priority Task `unsetuns`"
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
        local expected = "* [ ] Dependent Task [🔒] `11112222`"
        assert.are.same(expected, renderer.format_task(task))
      end)
    
      it("should not show any icon for annotations", function()
        local task = {
          id = 7,
          description = "Annotated Task",
          status = "pending",
          annotations = {{description = "Some note"}},
          uuid = "5555666677778888",
        }
        local expected = "* [ ] Annotated Task `55556666`"
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
        local expected = "* [ ] All Icons Task [⏰" .. convert_iso_to_local("20251111T090000Z") .. "] [M🔒] `9999aaaa`"
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
        local expected = "* [ ] Complete Task (⏱️" .. convert_iso_to_local("20251110T080000Z") .. ") [⏰" .. convert_iso_to_local("20251111T090000Z") .. "] [H🔒] `complete`"
        assert.are.same(expected, renderer.format_task(task))
      end)
    
      it("should handle task with no optional fields", function()
        local task = {
          id = 9,
          description = "Simple Task",
          status = "pending",
          uuid = "dddeeefff0001111",
        }
        local expected = "* [ ] Simple Task `dddeeeff`"
        assert.are.same(expected, renderer.format_task(task))
      end)
    
      it("should handle empty description", function()
        local task = {
          id = 10,
          description = "",
          status = "pending",
          uuid = "2222333344445555",
        }
        local expected = "* [ ]  `22223333`"
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
          local expected = "* [ ] Task blocking others [⚓] `blocking`"
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
          local expected = "* [ ] Task with both dependency types [🔒⚓] `both1234`"
          assert.are.same(expected, renderer.format_task(task))
        end)

        it("should not show anchor icon when _reverse_deps is empty", function()
          local task = {
            description = "Task blocking nothing",
            status = "pending",
            uuid = "noblock123456",
            _reverse_deps = {}
          }
          local expected = "* [ ] Task blocking nothing `noblock1`"
          assert.are.same(expected, renderer.format_task(task))
        end)

        it("should not show anchor icon when _reverse_deps is nil", function()
          local task = {
            description = "Task blocking nothing",
            status = "pending",
            uuid = "noblock223456"
          }
          local expected = "* [ ] Task blocking nothing `noblock2`"
          assert.are.same(expected, renderer.format_task(task))
        end)

        it("should show recurring icon for tasks with a recur field", function()
          local task = {
            description = "Weekly recurring task",
            status = "pending",
            uuid = "recurringtask12",
            recur = "weekly",
            _reverse_deps = {}
          }
          local expected = "* [ ] Weekly recurring task [🔁] `recurrin`"
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
            annotations = {{description = "note"}},
            recur = "monthly"
          }
          -- Order: priority, lock, anchor, recurring
          local expected = "* [ ] Complete icon task [H🔒⚓🔁] `allicons`"
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
          local expected = "* [ ] Blocking task with priority [M⚓] `blocking`"
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
          local expected = "* [ ] Blocking multiple tasks [⚓] `multiple`"
          assert.are.same(expected, renderer.format_task(task))
        end)
      end)

      describe("Relative date format", function()
        -- Helper: create an ISO date offset by N days from today (at local noon for stability)
        local function iso_date_offset(n)
          local now = os.date("*t")
          local ts = os.time({ year = now.year, month = now.month, day = now.day, hour = 12, min = 0, sec = 0 })
          ts = ts + n * 86400
          local d = os.date("!*t", ts) -- UTC time table
          return string.format("%04d%02d%02dT%02d%02d%02dZ", d.year, d.month, d.day, d.hour, d.min, d.sec)
        end

        -- Helper: expected relative string for N days offset
        local function expected_relative(n)
          if n == 0 then
            return "today"
          elseif n == 1 then
            return "tomorrow"
          elseif n == -1 then
            return "yesterday"
          elseif n > 1 and n < 7 then
            return string.format("+%d days", n)
          elseif n >= 7 and n < 30 then
            local w = math.floor(n / 7)
            return string.format("+%d %s", w, w == 1 and "week" or "weeks")
          elseif n >= 30 then
            local m = math.floor(n / 30)
            return string.format("+%d %s", m, m == 1 and "month" or "months")
          elseif n <= -2 and n > -7 then
            return string.format("%d days ago", -n)
          elseif n <= -7 and n > -30 then
            local w = math.floor((-n) / 7)
            return string.format("%d %s ago", w, w == 1 and "week" or "weeks")
          else
            local m = math.floor((-n) / 30)
            return string.format("%d %s ago", m, m == 1 and "month" or "months")
          end
        end

        it("should show 'today' for a due date that is today", function()
          local task = {
            description = "Due Today",
            status = "pending",
            due = iso_date_offset(0),
            uuid = "reltoday00000001",
          }
          local expected = "* [ ] Due Today [⏰today] `reltoday`"
          assert.are.same(expected, renderer.format_task(task, true, true))
        end)

        it("should show 'tomorrow' for a due date 1 day away", function()
          local task = {
            description = "Due Tomorrow",
            status = "pending",
            due = iso_date_offset(1),
            uuid = "reltomrw00000001",
          }
          local expected = "* [ ] Due Tomorrow [⏰tomorrow] `reltomrw`"
          assert.are.same(expected, renderer.format_task(task, true, true))
        end)

        it("should show 'yesterday' for a due date 1 day ago", function()
          local task = {
            description = "Due Yesterday",
            status = "pending",
            due = iso_date_offset(-1),
            uuid = "relyest000000001",
          }
          local expected = "* [ ] Due Yesterday [⏰yesterday] `relyest0`"
          assert.are.same(expected, renderer.format_task(task, true, true))
        end)

        it("should show 'N days' for a future due date less than 1 week away", function()
          local task = {
            description = "Due In Days",
            status = "pending",
            due = iso_date_offset(3),
            uuid = "reldays000000001",
          }
          local expected = "* [ ] Due In Days [⏰" .. expected_relative(3) .. "] `reldays0`"
          assert.are.same(expected, renderer.format_task(task, true, true))
        end)

        it("should show '-N days' for a past due date less than 1 week ago", function()
          local task = {
            description = "Overdue Days",
            status = "pending",
            due = iso_date_offset(-3),
            uuid = "relndays00000001",
          }
          local expected = "* [ ] Overdue Days [⏰" .. expected_relative(-3) .. "] `relndays`"
          assert.are.same(expected, renderer.format_task(task, true, true))
        end)

        it("should show 'N weeks' for a future due date between 1 and 4 weeks away", function()
          local task = {
            description = "Due In Weeks",
            status = "pending",
            due = iso_date_offset(14),
            uuid = "relweeks00000001",
          }
          local expected = "* [ ] Due In Weeks [⏰" .. expected_relative(14) .. "] `relweeks`"
          assert.are.same(expected, renderer.format_task(task, true, true))
        end)

        it("should show '-N weeks' for a past due date between 1 and 4 weeks ago", function()
          local task = {
            description = "Overdue Weeks",
            status = "pending",
            due = iso_date_offset(-14),
            uuid = "relnweeks0000001",
          }
          local expected = "* [ ] Overdue Weeks [⏰" .. expected_relative(-14) .. "] `relnweek`"
          assert.are.same(expected, renderer.format_task(task, true, true))
        end)

        it("should show 'N months' for a future due date more than 1 month away", function()
          local task = {
            description = "Due In Months",
            status = "pending",
            due = iso_date_offset(60),
            uuid = "relmonth00000001",
          }
          local expected = "* [ ] Due In Months [⏰" .. expected_relative(60) .. "] `relmonth`"
          assert.are.same(expected, renderer.format_task(task, true, true))
        end)

        it("should show '-N months' for a past due date more than 1 month ago", function()
          local task = {
            description = "Overdue Months",
            status = "pending",
            due = iso_date_offset(-60),
            uuid = "relnmonth0000001",
          }
          local expected = "* [ ] Overdue Months [⏰" .. expected_relative(-60) .. "] `relnmont`"
          assert.are.same(expected, renderer.format_task(task, true, true))
        end)

        it("should apply relative format to scheduled date as well", function()
          local task = {
            description = "Scheduled Relative",
            status = "pending",
            scheduled = iso_date_offset(7),
            uuid = "relschedfut00001",
          }
          local expected = "* [ ] Scheduled Relative (⏱️" .. expected_relative(7) .. ") `relsched`"
          assert.are.same(expected, renderer.format_task(task, true, true))
        end)

        it("should apply relative format to both scheduled and due dates", function()
          local task = {
            description = "Both Relative",
            status = "pending",
            scheduled = iso_date_offset(3),
            due = iso_date_offset(7),
            uuid = "relboth000000001",
          }
          local expected = "* [ ] Both Relative (⏱️" .. expected_relative(3) .. ") [⏰" .. expected_relative(7) .. "] `relboth0`"
          assert.are.same(expected, renderer.format_task(task, true, true))
        end)

        it("should not use relative format when use_relative is false", function()
          local task = {
            description = "Absolute Date",
            status = "pending",
            due = "20251225T000000Z",
            uuid = "absdate000000001",
          }
          -- When use_relative is false (default), absolute date is shown
          local result = renderer.format_task(task, false, false)
          assert.is_true(result:find("%d%d%d%d%-%d%d%-%d%d") ~= nil)
          assert.is_nil(result:find("days"))
          assert.is_nil(result:find("weeks"))
        end)

        it("should apply relative format to end date of completed tasks", function()
          local task = {
            description = "Completed Task",
            status = "completed",
            uuid = "relcomplt0000001",
            ["end"] = iso_date_offset(-5),
          }
          local result = renderer.format_task(task, true, true)
          local expected = "* [x] Completed Task {✅" .. expected_relative(-5) .. "} `relcompl`"
          assert.are.same(expected, result)
        end)

        it("should show absolute end date when use_relative is false", function()
          local task = {
            description = "Completed Absolute",
            status = "completed",
            uuid = "relcompabs000001",
            ["end"] = iso_date_offset(-5),
          }
          local result = renderer.format_task(task, true, false)
          assert.is_true(result:find("{✅%d%d%d%d%-%d%d%-%d%d}") ~= nil)
        end)
      end)

      describe("Date conversion modes", function()
        it("should convert UTC to local when convert_to_local is true `default`", function()
          local task = {
            id = 100,
            description = "Task with conversion",
            status = "pending",
            due = "20251225T103000Z",
            uuid = "conversiontest01",
          }
          local expected = "* [ ] Task with conversion [⏰" .. convert_iso_to_local("20251225T103000Z") .. "] `conversi`"
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
          local expected = "* [ ] Task without conversion [⏰" .. format_iso_date_raw("20251225T103000Z") .. "] `noconver`"
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
          local expected = "* [ ] Midnight after conversion [⏰" .. convert_iso_to_local("20251225T000000Z") .. "] `midnight`"
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
          local expected = "* [ ] Midnight without conversion [⏰2025-12-25] `midnight`"
          assert.are.same(expected, renderer.format_task(task, false))
        end)
      end)

end)
