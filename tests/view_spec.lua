
local view = require("frontline.view")

-- Render with dates left in UTC so the expectations do not depend on the
-- machine's timezone.
local function render(data, opts)
  opts = vim.tbl_extend("force", { convert_dates_to_local = false }, opts or {})
  local lines = view.render(data, opts)
  return lines
end

-- Find the first line whose text contains needle
local function find_line(lines, needle)
  for _, line in ipairs(lines) do
    if line:find(needle, 1, true) then
      return line
    end
  end
  return nil
end

local function has_line(lines, needle)
  return find_line(lines, needle) ~= nil
end

describe("view.annotation_state", function()
  it("detects TODO prefixes regardless of case", function()
    assert.are.equal("todo", view.annotation_state("TODO: do the thing"))
    assert.are.equal("todo", view.annotation_state("todo: do the thing"))
  end)

  it("detects DONE prefixes regardless of case", function()
    assert.are.equal("done", view.annotation_state("DONE: did the thing"))
    assert.are.equal("done", view.annotation_state("done: did the thing"))
  end)

  it("detects markdown checkboxes", function()
    assert.are.equal("todo", view.annotation_state("[ ] unchecked"))
    assert.are.equal("done", view.annotation_state("[x] checked"))
    assert.are.equal("done", view.annotation_state("[X] checked"))
  end)

  it("treats everything else as a plain note", function()
    assert.are.equal("plain", view.annotation_state("just a note"))
    assert.are.equal("plain", view.annotation_state('NOTE: "/tmp/notes.md"'))
    assert.are.equal("plain", view.annotation_state(""))
    assert.are.equal("plain", view.annotation_state(nil))
  end)
end)

describe("view.toggle_annotation_text", function()
  it("flips TODO to DONE and back, preserving the text", function()
    assert.are.equal("DONE: do the thing", view.toggle_annotation_text("TODO: do the thing"))
    assert.are.equal("TODO: do the thing", view.toggle_annotation_text("DONE: do the thing"))
  end)

  it("normalises the case of the prefix it writes", function()
    assert.are.equal("DONE: do the thing", view.toggle_annotation_text("todo: do the thing"))
  end)

  it("flips markdown checkboxes", function()
    assert.are.equal("[x] unchecked", view.toggle_annotation_text("[ ] unchecked"))
    assert.are.equal("[ ] checked", view.toggle_annotation_text("[x] checked"))
    assert.are.equal("[ ] checked", view.toggle_annotation_text("[X] checked"))
  end)

  it("returns nil for plain annotations", function()
    assert.is_nil(view.toggle_annotation_text("just a note"))
    assert.is_nil(view.toggle_annotation_text(""))
  end)
end)

describe("view.render", function()
  local function base_task(overrides)
    return vim.tbl_extend("force", {
      uuid = "a2f1c3d8aaaabbbbccccddddeeeeffff",
      description = "Refactor the annotation shortcuts",
      status = "pending",
    }, overrides or {})
  end

  it("puts the status marker, description and short hash on the title line", function()
    local lines = render({ task = base_task() })
    assert.is_truthy(lines[1]:match("^%[ %] Refactor the annotation shortcuts"))
    assert.is_truthy(lines[1]:match("`a2f1c3d8`$"))
  end)

  it("uses the started marker for a started task", function()
    local lines = render({ task = base_task({ start = "20260730T091200Z" }) })
    assert.is_truthy(lines[1]:match("^%[S%]"))
    assert.is_truthy(has_line(lines, "started"))
  end)

  it("appends the end date for a completed task", function()
    local lines = render({ task = base_task({
      status = "completed",
      ["end"] = "20260728T140000Z",
    }) })
    assert.is_truthy(lines[1]:match("^%[x%]"))
    assert.is_truthy(lines[1]:find("2026-07-28", 1, true))
  end)

  it("stays compact for a task with no optional fields", function()
    local lines = render({ task = base_task() })
    -- title, blank, status row only
    assert.are.equal(3, #lines)
    assert.is_truthy(has_line(lines, "status"))
  end)

  it("omits date rows that are not set", function()
    local lines = render({ task = base_task() })
    assert.is_nil(find_line(lines, "due"))
    assert.is_nil(find_line(lines, "scheduled"))
    assert.is_nil(find_line(lines, "wait"))
    assert.is_nil(find_line(lines, "until"))
  end)

  it("renders due and scheduled rows when set", function()
    local lines = render({ task = base_task({
      due = "20260802T000000Z",
      scheduled = "20260731T000000Z",
    }) })
    assert.is_truthy(find_line(lines, "due"):find("2026-08-02", 1, true))
    assert.is_truthy(find_line(lines, "scheduled"):find("2026-07-31", 1, true))
  end)

  it("renders project, tags and priority", function()
    local lines = render({ task = base_task({
      project = "frontline.nvim",
      tags = { "nvim", "ux" },
      priority = "H",
    }) })
    assert.is_truthy(find_line(lines, "project"):find("frontline.nvim", 1, true))
    assert.is_truthy(find_line(lines, "tags"):find("+nvim +ux", 1, true))
    assert.is_truthy(find_line(lines, "status"):find("H", 1, true))
  end)

  it("includes urgency by default and hides it when disabled", function()
    local task = base_task({ urgency = 12.4 })
    assert.is_truthy(find_line(render({ task = task }), "urgency 12.4"))
    assert.is_nil(find_line(render({ task = task }, { show_urgency = false }), "urgency"))
  end)

  it("omits the annotations section when there are none", function()
    local lines = render({ task = base_task() })
    assert.is_nil(find_line(lines, "Annotations"))
  end)

  it("renders annotations with checkboxes and dates", function()
    local lines = render({ task = base_task({
      annotations = {
        { entry = "20260729T101500Z", description = "TODO: decide the window size" },
        { entry = "20260729T111500Z", description = "DONE: survey existing mappings" },
        { entry = "20260728T090000Z", description = 'NOTE: "~/notes/view.md"' },
      },
    }) })

    assert.is_truthy(has_line(lines, "Annotations (3)"))
    assert.is_truthy(find_line(lines, "decide the window size"):find("☐", 1, true))
    assert.is_truthy(find_line(lines, "survey existing mappings"):find("☑", 1, true))
    assert.is_truthy(find_line(lines, "notes/view.md"):find("•", 1, true))
    assert.is_truthy(find_line(lines, "decide the window size"):find("2026-07-29", 1, true))
  end)

  it("hides annotation dates when disabled", function()
    local data = { task = base_task({
      annotations = { { entry = "20260729T101500Z", description = "TODO: something" } },
    }) }
    local lines = render(data, { annotation_dates = false })
    assert.is_nil(find_line(lines, "2026-07-29"))
    assert.is_truthy(has_line(lines, "TODO: something"))
  end)

  it("omits dependency sections when there are none", function()
    local lines = render({ task = base_task(), forward_deps = {}, reverse_deps = {} })
    assert.is_nil(find_line(lines, "Blocked by"))
    assert.is_nil(find_line(lines, "Blocking"))
  end)

  it("renders dependencies with an open count and hashes", function()
    local lines = render({
      task = base_task(),
      forward_deps = {
        { uuid = "9b7e0c11", short_hash = "9b7e0c11", description = "Design the View layout", status = "pending" },
        { uuid = "41d0a6f2", short_hash = "41d0a6f2", description = "Read the mappings module", status = "completed" },
      },
      reverse_deps = {
        { uuid = "77aa31b9", short_hash = "77aa31b9", description = "Release v0.5.0", status = "pending" },
      },
    })

    assert.is_truthy(has_line(lines, "Blocked by (2 · 1 open)"))
    assert.is_truthy(has_line(lines, "Blocking (1)"))
    assert.is_truthy(find_line(lines, "Design the View layout"):find("☐", 1, true))
    assert.is_truthy(find_line(lines, "Read the mappings module"):find("☑", 1, true))
    assert.is_truthy(find_line(lines, "Release v0.5.0"):find("`77aa31b9`", 1, true))
  end)

  it("hides dependency sections when disabled", function()
    local lines = render({
      task = base_task(),
      forward_deps = {
        { uuid = "9b7e0c11", short_hash = "9b7e0c11", description = "A dependency", status = "pending" },
      },
    }, { show_dependencies = false })
    assert.is_nil(find_line(lines, "Blocked by"))
  end)

  it("reports annotation and dependency lines in the line metadata", function()
    local _, _, line_meta = view.render({
      task = base_task({
        annotations = { { entry = "20260729T101500Z", description = "TODO: something" } },
      }),
      forward_deps = {
        { uuid = "9b7e0c11", short_hash = "9b7e0c11", description = "A dependency", status = "pending" },
      },
    }, { convert_dates_to_local = false })

    local kinds = {}
    for _, meta in pairs(line_meta) do
      kinds[meta.kind] = (kinds[meta.kind] or 0) + 1
    end

    assert.are.equal(1, kinds.annotation)
    assert.are.equal(1, kinds.dependency)
  end)

  it("keeps every line within max_width when content is short", function()
    local lines, _, _, width = view.render({ task = base_task() },
      { convert_dates_to_local = false, max_width = 60 })
    for _, line in ipairs(lines) do
      assert.is_true(vim.fn.strdisplaywidth(line) <= 60,
        string.format("line too wide: %q", line))
    end
    assert.is_true(width <= 60)
  end)

  it("does not lose the hash when the title exceeds max_width", function()
    local lines = render({ task = base_task({ description = string.rep("long ", 40) }) },
      { max_width = 60 })
    assert.is_truthy(lines[1]:match("`a2f1c3d8`$"))
  end)
end)
