local renderer = require("frontline.renderer")

-- Tasks are built with dates that have no time component so the expected
-- strings do not depend on the machine's timezone.
local function pending_task(overrides)
  local task = {
    id = 1,
    description = "Fix the login bug",
    status = "pending",
    uuid = "abcdef1234567890",
    project = "work",
    priority = "H",
    tags = { "urgent", "backend" },
    urgency = 15.5,
    due = "20251225T000000Z",
    scheduled = "20251220T000000Z",
  }
  for key, value in pairs(overrides or {}) do
    task[key] = value
  end
  return task
end

local function format(format_str, task, opts)
  opts = opts or {}
  opts.format = format_str
  opts.convert_to_local = opts.convert_to_local == nil and false or opts.convert_to_local
  return renderer.format_task(task or pending_task(), opts)
end

describe("Task format", function()
  describe("defaults", function()
    it("should render the default format like the built-in layout", function()
      local task = pending_task({ depends = { "dep-uuid" }, _reverse_deps = { "rev-uuid" } })
      local expected = "* [ ] Fix the login bug (⏱️2025-12-20) [⏰2025-12-25] [H🔒⚓] `abcdef12`"

      assert.are.same(expected, format(renderer.DEFAULT_TASK_FORMAT, task))
      -- ... and an unset format falls back to exactly the same line
      assert.are.same(expected, renderer.format_task(task, { convert_to_local = false }))
    end)

    it("should keep the checkbox and the short uuid whatever the format is", function()
      assert.are.same("* [ ] `abcdef12`", format("", pending_task()))
      assert.are.same("* [x] `abcdef12`",
        format("", pending_task({ status = "completed" })))
    end)
  end)

  describe("placeholders", function()
    it("should render the description alone", function()
      assert.are.same("* [ ] Fix the login bug `abcdef12`", format("{{description}}"))
    end)

    it("should render the project", function()
      assert.are.same("* [ ] Fix the login bug +work `abcdef12`",
        format("{{description}} +{{project}}"))
    end)

    it("should render only the dates asked for", function()
      assert.are.same("* [ ] Fix the login bug [⏰2025-12-25] `abcdef12`",
        format("{{description}} {{due}}"))
      assert.are.same("* [ ] Fix the login bug (⏱️2025-12-20) `abcdef12`",
        format("{{description}} {{scheduled}}"))
      assert.are.same("* [ ] Fix the login bug [⏰2025-12-25] (⏱️2025-12-20) `abcdef12`",
        format("{{description}} {{due}} {{scheduled}}"))
    end)

    it("should render undecorated dates with .raw", function()
      assert.are.same("* [ ] Fix the login bug due:2025-12-25 `abcdef12`",
        format("{{description}} due:{{due.raw}}"))
      assert.are.same("* [ ] Fix the login bug sch:2025-12-20 `abcdef12`",
        format("{{description}} sch:{{scheduled.raw}}"))
    end)

    it("should render the marker group and its individual markers", function()
      local task = pending_task({ depends = { "dep" }, _reverse_deps = { "rev" }, recur = "weekly" })

      assert.are.same("* [ ] Fix the login bug [H🔒⚓🔁] `abcdef12`",
        format("{{description}} {{markers}}", task))
      assert.are.same("* [ ] Fix the login bug H 🔒 ⚓ 🔁 `abcdef12`",
        format("{{description}} {{priority}} {{blocked}} {{blocking}} {{recurring}}", task))
    end)

    it("should honour priority_labels and expose the raw value", function()
      assert.are.same("* [ ] Fix the login bug ↑ `abcdef12`",
        format("{{description}} {{priority}}", nil, { priority_labels = { H = "↑" } }))
      assert.are.same("* [ ] Fix the login bug H `abcdef12`",
        format("{{description}} {{priority.raw}}", nil, { priority_labels = { H = "↑" } }))
    end)

    it("should render tags with and without the + prefix", function()
      assert.are.same("* [ ] Fix the login bug +urgent +backend `abcdef12`",
        format("{{description}} {{tags}}"))
      assert.are.same("* [ ] Fix the login bug urgent backend `abcdef12`",
        format("{{description}} {{tags.raw}}"))
    end)

    it("should render the urgency", function()
      assert.are.same("* [ ] Fix the login bug (15.5) `abcdef12`",
        format("{{description}} ({{urgency}})"))
    end)

    it("should render the completion date for completed tasks only", function()
      local completed = pending_task({ status = "completed", ["end"] = "20251201T090000Z" })

      assert.are.same("* [x] Fix the login bug {✅2025-12-01} `abcdef12`",
        format("{{description}} {{completed}}", completed))
      assert.are.same("* [x] Fix the login bug 2025-12-01 `abcdef12`",
        format("{{description}} {{completed.raw}}", completed))
      assert.are.same("* [x] Fix the login bug {✅2025-12-01} `abcdef12`",
        format("{{description}} {{end}}", completed))

      -- A deleted task carries an 'end' date too, but it did not complete
      local deleted = pending_task({ status = "deleted", ["end"] = "20251201T090000Z" })
      assert.are.same("* [-] Fix the login bug `abcdef12`",
        format("{{description}} {{completed}}", deleted))
    end)

    it("should tolerate spaces inside the braces", function()
      assert.are.same("* [ ] Fix the login bug 2025-12-25 `abcdef12`",
        format("{{ description }} {{ due.raw }}"))
    end)
  end)

  describe("{{icons}}", function()
    it("should group completion, dates and markers", function()
      local task = pending_task({ depends = { "dep" } })
      assert.are.same("* [ ] Fix the login bug (⏱️2025-12-20) [⏰2025-12-25] [H🔒] `abcdef12`",
        format("{{description}} {{icons}}", task))
    end)

    it("should drop the scheduled date of a completed task", function()
      local completed = pending_task({ status = "completed", ["end"] = "20251201T090000Z" })
      assert.are.same("* [x] Fix the login bug {✅2025-12-01} [⏰2025-12-25] [H] `abcdef12`",
        format("{{description}} {{icons}}", completed))
    end)

    it("should render nothing for a task with no dates or markers", function()
      local bare = { description = "Bare", status = "pending", uuid = "0011223344556677" }
      assert.are.same("* [ ] Bare `00112233`", format("{{description}} {{icons}}", bare))
    end)
  end)

  describe("whitespace", function()
    it("should collapse the gaps left by empty placeholders", function()
      local bare = { description = "Bare", status = "pending", uuid = "0011223344556677" }
      assert.are.same("* [ ] Bare `00112233`",
        format("{{description}} {{due}} {{project}} {{markers}}", bare))
    end)

    it("should trim leading and trailing whitespace", function()
      assert.are.same("* [ ] Fix the login bug `abcdef12`", format("  {{description}}   "))
    end)
  end)

  describe("bullet", function()
    it("should use the configured bullet", function()
      assert.are.same("- [ ] Fix the login bug `abcdef12`",
        format("{{description}}", nil, { bullet = "-" }))
    end)

    it("should drop the bullet when it is empty", function()
      assert.are.same("[ ] Fix the login bug `abcdef12`",
        format("{{description}}", nil, { bullet = "" }))
    end)
  end)

  describe("validation", function()
    it("should accept the default format", function()
      assert.are.same(0, #renderer.validate_task_format(renderer.DEFAULT_TASK_FORMAT))
    end)

    it("should report unknown placeholders", function()
      local problems = renderer.validate_task_format("{{description}} {{nope}}")
      assert.are.same(1, #problems)
      assert.are.same("nope", problems[1].name)
    end)

    it("should explain placeholders that are always rendered", function()
      local problems = renderer.validate_task_format("{{uid}} {{status}}")
      assert.are.same(2, #problems)
      assert.is_true(problems[1].reason:find("appended") ~= nil)
      assert.is_true(problems[2].reason:find("checkbox") ~= nil)
    end)

    it("should report unknown modifiers", function()
      local problems = renderer.validate_task_format("{{due.tomorrow}}")
      assert.are.same(1, #problems)
      assert.are.same("due.tomorrow", problems[1].name)
    end)

    it("should render an unknown placeholder as nothing", function()
      assert.are.same("* [ ] Fix the login bug `abcdef12`", format("{{description}} {{nope}}"))
    end)
  end)

  describe("legacy positional arguments", function()
    it("should still format with the positional signature", function()
      local task = pending_task()
      assert.are.same("* [ ] Fix the login bug (⏱️2025-12-20) [⏰2025-12-25] [↑] `abcdef12`",
        renderer.format_task(task, false, false, { H = "↑" }))
    end)
  end)
end)
