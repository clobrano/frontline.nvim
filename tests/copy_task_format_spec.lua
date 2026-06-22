
local mappings = require("frontline.mappings")
local render = mappings._render_copy_template

describe("copy task format template", function()

  local task = {
    uuid = "abcdef1234567890abcdef1234567890",
    description = "Fix the login bug",
    status = "pending",
    project = "work",
    priority = "H",
    tags = { "urgent", "backend" },
    due = "20251225T103000Z",
    scheduled = "20251220T000000Z",
    urgency = 15.5,
  }

  it("renders description only (default)", function()
    assert.are.equal("Fix the login bug", render("{{description}}", task))
  end)

  it("renders description with bullet and checkbox", function()
    assert.are.equal("* [ ] Fix the login bug", render("* [ ] {{description}}", task))
  end)

  it("renders tags as space-separated list", function()
    assert.are.equal("Fix the login bug urgent backend", render("{{description}} {{tags}}", task))
  end)

  it("renders due date", function()
    local result = render("{{description}} due:{{due}}", task)
    assert.are.equal("Fix the login bug due:2025-12-25 10:30", result)
  end)

  it("renders scheduled date without time when midnight", function()
    local result = render("scheduled:{{scheduled}}", task)
    assert.are.equal("scheduled:2025-12-20", result)
  end)

  it("renders short_uuid", function()
    assert.are.equal("Fix the login bug `abcdef12`", render("{{description}} `{{short_uuid}}`", task))
  end)

  it("renders full uuid", function()
    local result = render("{{uuid}}", task)
    assert.are.equal("abcdef1234567890abcdef1234567890", result)
  end)

  it("renders project", function()
    assert.are.equal("work: Fix the login bug", render("{{project}}: {{description}}", task))
  end)

  it("renders priority", function()
    assert.are.equal("(H) Fix the login bug", render("({{priority}}) {{description}}", task))
  end)

  it("renders urgency", function()
    assert.are.equal("Fix the login bug [15.5]", render("{{description}} [{{urgency}}]", task))
  end)

  it("trims trailing whitespace from empty placeholders", function()
    local task_minimal = {
      uuid = "abcdef1234567890",
      description = "Simple task",
      status = "pending",
    }
    assert.are.equal("Simple task", render("{{description}} {{tags}}", task_minimal))
  end)

  it("handles spaces around placeholder names", function()
    assert.are.equal("Fix the login bug", render("{{ description }}", task))
  end)

  it("renders complex format with multiple fields", function()
    local result = render("* [ ] {{description}} +{{project}} ({{priority}}) due:{{due}}", task)
    assert.are.equal("* [ ] Fix the login bug +work (H) due:2025-12-25 10:30", result)
  end)

  it("renders status field", function()
    assert.are.equal("pending", render("{{status}}", task))
  end)

  it("unknown placeholders resolve to empty string", function()
    assert.are.equal("Fix the login bug", render("{{description}} {{nonexistent}}", task))
  end)
end)
