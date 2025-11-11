# frontline.nvim

A Neovim plugin for integrating Taskwarrior task management directly into Markdown files.

## Features

- 📝 Embed Taskwarrior queries in Markdown headers
- 🔄 Automatic task list updates on file open/save
- ✅ Task status indicators: `[ ]` pending, `[S]` started, `[x]` completed
- 🎯 Priority, dependency, and annotation icons
- ⚙️ Configurable blank lines after task lists
- ⌨️ Interactive task management with keybindings
- 🕐 Local timezone display for dates and times

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
* [status] description (scheduled) [due] [icons] (hash)
```

Examples:
```markdown
* [ ] Fix authentication bug (2025-11-15 10:00) [2025-11-20 17:00] [!!!,🔒] (abcd1234)
* [ ] Simple task (abcd1234)
* [ ] Task with due date only [2025-11-20 17:00] (abcd1234)
```

Where:
- `[status]`: `[ ]` pending, `[S]` started, `[x]` completed
- `description`: Task description from Taskwarrior
- `(scheduled)`: Scheduled date in rounded parenthesis (if set)
- `[due]`: Due date in squared brackets (if set)
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

### Interactive Task Management

Place your cursor on any task line and use these default keybindings:

| Keybinding | Action | Description |
|------------|--------|-------------|
| `<leader>td` | Toggle Done | Mark task as complete or reopen it |
| `<leader>ts` | Toggle Started | Start or stop working on task |
| `<leader>tm` | Modify Task | Modify task properties (prompts for input) |
| `<leader>ta` | Add Annotation | Add a note to the task |
| `<leader>te` | Edit Task | Open task in Taskwarrior's interactive editor |

**Examples:**

```vim
" On a task line, press <leader>td to mark it done
" Press <leader>td again to reopen it

" Press <leader>ts to start working on a task
" Press <leader>ts again to stop

" Press <leader>tm and enter: priority:H due:tomorrow
" Press <leader>ta and enter: "Started working on this"

" Press <leader>te to open the full Taskwarrior editor in a split
" Edit all task properties, save and close to update
```

After any modification, the task list automatically refreshes to show the updated state.

## Configuration

```lua
require('frontline').setup({
  newlines_after_tasks = 2,  -- Number of blank lines after task lists (default: 2)
  mappings = {
    toggle_done = "<leader>td",      -- Toggle task done/undone
    toggle_started = "<leader>ts",   -- Toggle task started/unstarted
    modify_task = "<leader>tm",      -- Modify task properties
    add_annotation = "<leader>ta",   -- Add task annotation
    edit_task = "<leader>te",        -- Edit task in Taskwarrior editor
  },
})
```

### Available Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `newlines_after_tasks` | number | 2 | Number of blank lines to add after each task list |
| `mappings.toggle_done` | string | `"<leader>td"` | Keybinding to toggle task done/undone |
| `mappings.toggle_started` | string | `"<leader>ts"` | Keybinding to toggle task started/unstarted |
| `mappings.modify_task` | string | `"<leader>tm"` | Keybinding to modify task |
| `mappings.add_annotation` | string | `"<leader>ta"` | Keybinding to add annotation |
| `mappings.edit_task` | string | `"<leader>te"` | Keybinding to edit task in Taskwarrior editor |

**Note:** Set any mapping to `false` to disable it:

```lua
require('frontline').setup({
  mappings = {
    toggle_done = "<leader>td",
    toggle_started = false,  -- Disable this mapping
    modify_task = "<leader>tm",
    add_annotation = "<leader>ta",
  },
})
```

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

All tests should pass (30/30):
- Integration tests: 5
- Parser tests: 3
- Task Client tests: 4
- Renderer tests: 18

## License

MIT

## Contributing

Contributions welcome! Please feel free to submit a Pull Request.
