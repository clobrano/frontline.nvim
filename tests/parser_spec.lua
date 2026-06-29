
local parser = require("frontline.parser")

describe("Parser Module", function()
  it("should extract queries from markdown headers", function()
    local lines = {
      "# My Tasks | status:pending project:work",
      "Some other text",
      "## Daily Todos | +today",
      "### Sub-section",
      "# Another Header without query",
      "# Header with | multiple | pipes | query:test",
    }
    local queries = parser.extract_queries(lines)

    assert.are.same(3, #queries)
    assert.are.same(1, queries[1].line_num)
    assert.are.same("# My Tasks", queries[1].header)
    assert.are.same("status:pending project:work", queries[1].query)

    assert.are.same(3, queries[2].line_num)
    assert.are.same("## Daily Todos", queries[2].header)
    assert.are.same("+today", queries[2].query)

    assert.are.same(6, queries[3].line_num)
    assert.are.same("# Header with | multiple | pipes", queries[3].header)
    assert.are.same("multiple | pipes | query:test", queries[3].query)
  end)

  it("should return an empty table if no queries are found", function()
    local lines = {
      "# Just a header",
      "No queries here",
      "## Another section",
    }
    local queries = parser.extract_queries(lines)
    assert.are.same(0, #queries)
  end)

  it("should extract sort directive from query", function()
    local lines = {
      "## Work | @work +PENDING due.before:eow sort:due",
    }
    local queries = parser.extract_queries(lines)
    assert.are.same(1, #queries)
    assert.are.same("+PENDING due.before:eow", queries[1].query)
    assert.are.same("due", queries[1].sort.field)
    assert.are.same(false, queries[1].sort.reverse)
  end)

  it("should extract sort.reverse directive from query", function()
    local lines = {
      "## Work | @work +PENDING due.before:eow sort.reverse:due",
    }
    local queries = parser.extract_queries(lines)
    assert.are.same(1, #queries)
    assert.are.same("+PENDING due.before:eow", queries[1].query)
    assert.are.same("due", queries[1].sort.field)
    assert.are.same(true, queries[1].sort.reverse)
  end)

  it("should have nil sort when no sort directive given", function()
    local lines = {
      "## Work | +PENDING",
    }
    local queries = parser.extract_queries(lines)
    assert.are.same(1, #queries)
    assert.is_nil(queries[1].sort)
  end)

  it("should handle empty lines and lines without headers", function()
    local lines = {
      "",
      "Some text",
      "# Tasks | +NEXT",
      "",
    }
    local queries = parser.extract_queries(lines)
    assert.are.same(1, #queries)
    assert.are.same("+NEXT", queries[1].query)
  end)
end)
