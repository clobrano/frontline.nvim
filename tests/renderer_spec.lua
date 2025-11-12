
local renderer = require("frontline.renderer")

-- Helper to calculate timezone offset in seconds
local function get_timezone_offset()
  local now = os.time()
  local utc_time = os.time(os.date("!*t", now))
  local local_time = os.time(os.date("*t", now))
  return os.difftime(local_time, utc_time)
end

-- Helper to convert UTC ISO date to expected local time string
local function utc_to_local_string(iso_date)
  local year = tonumber(string.sub(iso_date, 1, 4))
  local month = tonumber(string.sub(iso_date, 5, 6))
  local day = tonumber(string.sub(iso_date, 7, 8))
  local hour = tonumber(string.sub(iso_date, 10, 11))
  local minute = tonumber(string.sub(iso_date, 12, 13))
  local second = tonumber(string.sub(iso_date, 14, 15))

  -- Properly convert UTC to local time
  -- First, create epoch time treating the values as UTC
  local utc_epoch = os.time({
    year = year,
    month = month,
    day = day,
    hour = hour,
    min = minute,
    sec = second,
    isdst = false
  })

  -- Adjust by timezone offset to get actual UTC epoch
  local timezone_offset = get_timezone_offset()
  local actual_utc_epoch = utc_epoch - timezone_offset

  -- Convert to local time
  local local_time = os.date("*t", actual_utc_epoch)

  if local_time.hour == 0 and local_time.min == 0 then
    return string.format("%04d-%02d-%02d", local_time.year, local_time.month, local_time.day)
  else
    return string.format("%04d-%02d-%02d %02d:%02d", local_time.year, local_time.month, local_time.day, local_time.hour, local_time.min)
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
        local expected = "* [ ] Task with Due Date [" .. utc_to_local_string("20251225T103000Z") .. "] (abcabcab)"
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
        local expected = "* [ ] Task with Scheduled Date (" .. utc_to_local_string("20251220T090000Z") .. ") (schedsch)"
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
        local expected = "* [ ] Task with Both Dates (" .. utc_to_local_string("20251220T090000Z") .. ") [" .. utc_to_local_string("20251225T103000Z") .. "] (bothboth)"
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
        local expected = "* [ ] Task with Due Date at Midnight [" .. utc_to_local_string("20251225T000000Z") .. "] (midnight)"
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
        local expected = "* [ ] Task with Scheduled at Midnight (" .. utc_to_local_string("20251220T000000Z") .. ") (schedmid)"
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
        local expected = "* [ ] Both Dates at Midnight (" .. utc_to_local_string("20251220T000000Z") .. ") [" .. utc_to_local_string("20251225T000000Z") .. "] (bothmidn)"
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
        local expected = "* [ ] All Icons Task [" .. utc_to_local_string("20251111T090000Z") .. "] [!!,🔒,A] (9999aaaa)"
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
        local expected = "* [ ] Complete Task (" .. utc_to_local_string("20251110T080000Z") .. ") [" .. utc_to_local_string("20251111T090000Z") .. "] [!!!,🔒,A] (complete)"
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

      describe("Date conversion modes", function()
        it("should convert UTC to local when convert_to_local is true", function()
          local task = {
            id = 100,
            description = "Task with conversion",
            status = "pending",
            due = "20251225T103000Z",
            uuid = "conversiontest01",
          }
          local expected = "* [ ] Task with conversion [" .. utc_to_local_string("20251225T103000Z") .. "] (conversi)"
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
          local expected = "* [ ] Task without conversion [2025-12-25 10:30] (noconver)"
          assert.are.same(expected, renderer.format_task(task, false))
        end)

        it("should apply midnight detection to converted time", function()
          local task = {
            id = 102,
            description = "Midnight in local time after conversion",
            status = "pending",
            -- This is midnight UTC, which might be different in local time
            due = "20251225T000000Z",
            uuid = "midnighttest001",
          }
          -- Should use converted time for midnight detection
          local expected = "* [ ] Midnight in local time after conversion [" .. utc_to_local_string("20251225T000000Z") .. "] (midnight)"
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
          -- Midnight in UTC (00:00) should be omitted even without conversion
          local expected = "* [ ] Midnight without conversion [2025-12-25] (midnight)"
          assert.are.same(expected, renderer.format_task(task, false))
        end)

        it("should handle scheduled dates with conversion disabled", function()
          local task = {
            id = 104,
            description = "Scheduled without conversion",
            status = "pending",
            scheduled = "20251220T143000Z",
            uuid = "schednoconv0001",
          }
          local expected = "* [ ] Scheduled without conversion (2025-12-20 14:30) (schednoc)"
          assert.are.same(expected, renderer.format_task(task, false))
        end)
      end)

end)
