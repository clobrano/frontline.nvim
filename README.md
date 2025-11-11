# frontline.nvim

A Neovim plugin for integrating Taskwarrior task management directly into Markdown files.

## Features

- 📝 Embed Taskwarrior queries in Markdown headers
- 🔄 Automatic task list updates on file open/save
- ✅ Task status indicators: `[ ]` pending, `[S]` started, `[x]` completed
- 🎯 Priority, dependency, and annotation icons
- ⚙️ Configurable blank lines after task lists

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "yourusername/frontline.nvim",
  config = function()
    require('frontline').setup({
      newlines_after_tasks = 2,  -- Number of blank lines after tasks (default: 2)
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "yourusername/frontline.nvim",
  config = function()
    require('frontline').setup()
  end,
}
```

## Usage

### Basic Query Syntax

Add Taskwarrior queries to your Markdown headers using the pipe `|` separator:

```markdown
# My Pending Tasks | status:pending

# High Priority Work | project:work priority:H

# Due This Week | due.before:eow
```

### Task Format

Tasks are displayed as Markdown list items:

```markdown
* [status] description (due_date) [icons] (hash)
```

Example:
```markdown
* [ ] Fix authentication bug (2025-11-15 10:00) [!!!,🔒] (abcd1234)
```

Where:
- `[status]`: `[ ]` pending, `[S]` started, `[x]` completed
- `description`: Task description from Taskwarrior
- `(due_date)`: Due date and time (if set)
- `[icons]`: Priority (`!!!` high, `!!` medium, `!` low), Dependencies (🔒), Annotations (A)
- `(hash)`: Short task UUID (first 8 characters)

### Automatic Refresh

The plugin automatically refreshes task lists:
- When you open a Markdown file (`BufReadPost`)
- Before you save a Markdown file (`BufWritePost`)

### Manual Refresh

Use the command to manually trigger a refresh:

```vim
:FrontlineRefresh
```

## Configuration

```lua
require('frontline').setup({
  newlines_after_tasks = 2,  -- Number of blank lines after task lists (default: 2)
})
```

### Available Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `newlines_after_tasks` | number | 2 | Number of blank lines to add after each task list |

## Requirements

- Neovim 0.5+
- [Taskwarrior](https://taskwarrior.org/) installed and configured
- Tasks in your Taskwarrior database

## Local Testing

Test the plugin without installing it:

```bash
cd /path/to/frontline.nvim
nvim -u test_config.lua test.md
```

## Example Markdown File

```markdown
# Today's Tasks | +today status:pending

# Work Project | project:work

# High Priority | priority:H status:pending
```

When opened in Neovim, each section will automatically populate with matching tasks.

## Compatibility

This plugin aims for compatibility with [Taskwiki](https://github.com/tools-life/taskwiki)'s header query format.

## Development

### Running Tests

```bash
nvim --headless -c "PlenaryBustedDirectory tests/"
```

All tests should pass (22/22):
- Integration tests: 5
- Parser tests: 3
- Task Client tests: 4
- Renderer tests: 10

## License

MIT

## Contributing

Contributions welcome! Please feel free to submit a Pull Request.
