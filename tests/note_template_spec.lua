
local mappings = require("frontline.mappings")
local render = mappings._render_note_template
local ensure = mappings._ensure_task_metadata

describe("note template rendering", function()

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

  it("expands {{title}} and {{description}} to the task description", function()
    assert.are.equal("# Fix the login bug", render("# {{title}}", task))
    assert.are.equal("Fix the login bug", render("{{description}}", task))
  end)

  it("expands task fields", function()
    local result = render("{{project}} {{priority}} {{tags}} {{due}} {{short_uuid}}", task)
    assert.are.equal("work H urgent backend 2025-12-25 10:30 abcdef12", result)
  end)

  it("expands {{date}} and {{time}}", function()
    assert.are.equal(os.date("%Y-%m-%d"), render("{{date}}", task))
    assert.are.equal(os.date("%H:%M"), render("{{time}}", task))
  end)

  it("preserves multi-line layout and blank lines", function()
    local template = "# {{title}}\n\n## Context\n\n## Next steps\n"
    assert.are.equal("# Fix the login bug\n\n## Context\n\n## Next steps\n", render(template, task))
  end)

  it("leaves unknown placeholders untouched", function()
    assert.are.equal("{{unknown}}", render("{{unknown}}", task))
    assert.are.equal("{{date:YYYY-MM-DD}}", render("{{date:YYYY-MM-DD}}", task))
  end)
end)

describe("note task metadata", function()

  local uuid = "abcdef12"

  it("adds frontmatter to a template that has none", function()
    local result = ensure("# My note\n", uuid)
    assert.are.equal("---\ntask: `abcdef12`\n---\n\n# My note\n", result)
  end)

  it("adds the task field to existing frontmatter, keeping the other keys", function()
    local content = "---\ntags: [note]\nauthor: me\n---\n\n# My note\n"
    local result = ensure(content, uuid)
    assert.are.equal("---\ntags: [note]\nauthor: me\ntask: `abcdef12`\n---\n\n# My note\n", result)
  end)

  it("overwrites a task field the template already declares", function()
    local content = "---\ntask: something-else\ntags: [note]\n---\n\n# My note\n"
    local result = ensure(content, uuid)
    assert.are.equal("---\ntask: `abcdef12`\ntags: [note]\n---\n\n# My note\n", result)
  end)

  it("leaves a nested task key alone and adds the top-level one", function()
    local content = "---\nmeta:\n  task: nested\n---\n\n# My note\n"
    local result = ensure(content, uuid)
    assert.are.equal("---\nmeta:\n  task: nested\ntask: `abcdef12`\n---\n\n# My note\n", result)
  end)

  it("handles frontmatter closed with the YAML end-of-document marker", function()
    local content = "---\ntags: [note]\n...\n\n# My note\n"
    local result = ensure(content, uuid)
    assert.are.equal("---\ntags: [note]\ntask: `abcdef12`\n...\n\n# My note\n", result)
  end)

  it("treats a leading --- that never closes as body content", function()
    local content = "---\nnot really frontmatter\n"
    local result = ensure(content, uuid)
    assert.are.equal("---\ntask: `abcdef12`\n---\n\n---\nnot really frontmatter\n", result)
  end)

  it("does not treat a horizontal rule further down as frontmatter", function()
    local content = "# My note\n\n---\n\nmore text\n"
    local result = ensure(content, uuid)
    assert.are.equal("---\ntask: `abcdef12`\n---\n\n# My note\n\n---\n\nmore text\n", result)
  end)

  it("produces just the frontmatter for an empty template", function()
    assert.are.equal("---\ntask: `abcdef12`\n---\n", ensure("", uuid))
  end)

  it("matches the built-in note format", function()
    local result = ensure("# Fix the login bug\n", uuid)
    assert.are.equal("---\ntask: `abcdef12`\n---\n\n# Fix the login bug\n", result)
  end)
end)
