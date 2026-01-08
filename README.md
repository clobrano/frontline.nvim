# frontline.nvim

A Neovim plugin for integrating Taskwarrior task management directly into Markdown files.

## Features

- 📝 Embed Taskwarrior queries in Markdown headers
- 🔄 Automatic task list updates on file open/save
- ✅ Task status indicators: `[ ]` pending, `[S]` started, `[x]` completed, `[-]` deleted
- 🎯 Priority, dependency, reverse dependency, and annotation icons
- ⚙️ Configurable blank lines after task lists
- ⌨️ Interactive task management with keybindings
- 🕐 Local timezone display for dates and times
- 🗂️ Multiple Taskwarrior workspaces support with `@workspace` syntax
- 🎨 Smart autocomplete for projects, tags, dates, workspaces, and priorities

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

### Multiple Workspaces

Frontline supports multiple Taskwarrior databases (workspaces) using the `@workspace` syntax in your queries:

```markdown
# Personal Tasks | @personal status:pending

# Work Tasks | @work project:myproject status:pending

# Default Workspace Tasks | status:pending
```

**Configuration:**

```lua
require('frontline').setup({
  workspaces = {
    personal = "~/.config/taskwarrior/personal/.taskrc",
    work = "~/.config/taskwarrior/work/.taskrc",
  },
  default_workspace = "personal",  -- Used when no @workspace specified
})
```

**Key Points:**
- Use `@workspace_name` in your query to specify which workspace to use
- If no workspace is specified, the `default_workspace` is used
- If `default_workspace` is `nil`, the system's default Taskwarrior database is used
- A notification displays the current workspace when opening a file
- All task operations (create, modify, toggle, etc.) use the current workspace context
- **Override workspace in task operations:** Include `@workspace` in task creation input to override the current buffer's workspace

**Workspace Override Examples:**

When creating a task, you can override the current workspace:
```
# In a buffer with @personal workspace
# Press <leader>tn to create a new task

# Create in current workspace (personal):
New task: Fix bug in app project:mobile

# Override to create in work workspace:
New task: @work Review PR project:backend priority:H
```

This allows you to quickly create tasks in different workspaces without switching buffers.

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
- `[status]`: `[ ]` pending, `[S]` started, `[x]` completed, `[-]` deleted
- `description`: Task description from Taskwarrior
- `(scheduled)`: Scheduled date in rounded parenthesis (if set)
- `[due]`: Due date in squared brackets (if set)
- `[icons]`: Priority (🔴 high, 🟠 medium, 🟡 low), Dependencies (🔒), Reverse Dependencies (⚓), Annotations (🗒️)
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
| `<leader>tn` | Create Task | Create new task with smart context-aware pre-fill |
| `<leader>tB` | Add Dependency | Create new task as dependency of current task |
| `<leader>tu` | Undo Task | Undo last action on task |
| `<leader>tb` | Show Dependencies | Show task dependencies and reverse dependencies |

### Smart Task Creation with Autocomplete

The plugin provides intelligent autocomplete when creating tasks (`<leader>tn`) or adding dependencies (`<leader>tB`).

**Autocomplete Features:**
- **Projects** (`project:`): Suggests existing projects from your Taskwarrior database
- **Tags** (`+`): Suggests existing tags (excluding virtual tags like PENDING, COMPLETED)
- **Dates** (`due:`, `scheduled:`): Suggests common date shortcuts (today, tomorrow, eow, 1w, etc.)
- **Workspaces** (`@`): Suggests configured workspaces
- **Priority** (`priority:`): Suggests H (High), M (Medium), L (Low)

**How to Use Autocomplete:**
1. Press `<leader>tn` to create a new task (opens command-line mode with `:FrontlineCreateTask`)
2. The command line will be pre-filled with context-aware attributes if available
3. Type your task description and/or attributes (e.g., `project:`, `+`, `due:`, `@`)
4. Press `<Tab>` to trigger autocomplete suggestions
5. Use `<Tab>` and `<Shift-Tab>` to cycle through suggestions, or continue typing to filter
6. Press `<Enter>` to execute the command and create the task
7. Press `<Ctrl-c>` or `<Esc>` to cancel

**Examples:**
```
# After pressing <leader>tn:
:FrontlineCreateTask Fix bug project:<Tab>
  → Suggests: backend, frontend, mobile, web

:FrontlineCreateTask Update docs +<Tab>
  → Suggests: bug, feature, documentation, urgent

:FrontlineCreateTask Review PR due:<Tab>
  → Suggests: today, tomorrow, eow, 1w, 2w, 1m

:FrontlineCreateTask @<Tab>
  → Suggests: personal, work
```

**Alternative: Use Commands Directly**

You can also type the commands directly in command mode:
```vim
:FrontlineCreateTask Fix authentication bug project:backend priority:H due:tomorrow
:FrontlineCreateDependency Setup database project:backend
```

**Smart Context-Aware Pre-fill:**
- When creating from a task line: inherits workspace, project, due date, and scheduled date
- When creating from a header: inherits all filters from the header query
- The command line opens pre-filled with these context attributes
- Project and tags are cached for 5 minutes to improve performance

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
  workspaces = {
    personal = "~/.config/taskwarrior/personal/.taskrc",
    work = "~/.config/taskwarrior/work/.taskrc",
  },
  default_workspace = "personal",  -- Default workspace when none specified (nil = system taskwarrior)
  enable_reverse_dependencies = true,  -- Show anchor icon for tasks blocking others (default: true)
  reverse_dependencies_warn_threshold = 1000,  -- Warn if queries take > 1000ms (default: 1000)
  mappings = {
    toggle_done = "<leader>td",      -- Toggle task done/undone
    toggle_started = "<leader>ts",   -- Toggle task started/unstarted
    modify_task = "<leader>tm",      -- Modify task properties
    add_annotation = "<leader>ta",   -- Add task annotation
    edit_task = "<leader>te",        -- Edit task in Taskwarrior editor
    show_blocking_dependencies = "<leader>tb",  -- Show dependencies
    add_dependency = "<leader>tB",   -- Add task as dependency
    undo_task = "<leader>tu",        -- Undo last action
    create_task = "<leader>tn",      -- Create new task
  },
})
```

### Available Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `newlines_after_tasks` | number | 2 | Number of blank lines to add after each task list |
| `workspaces` | table | `{}` | Map of workspace names to Taskwarrior rc file paths |
| `default_workspace` | string | `nil` | Default workspace name (nil uses system taskwarrior) |
| `enable_reverse_dependencies` | boolean | true | Enable reverse dependency tracking (⚓ icon and "tasks this task is blocking" view) |
| `reverse_dependencies_warn_threshold` | number | 1000 | Warn if reverse dependency queries take longer than this (in milliseconds). Set to 0 to disable warnings. |
| `mappings.toggle_done` | string | `"<leader>td"` | Keybinding to toggle task done/undone |
| `mappings.toggle_started` | string | `"<leader>ts"` | Keybinding to toggle task started/unstarted |
| `mappings.modify_task` | string | `"<leader>tm"` | Keybinding to modify task |
| `mappings.add_annotation` | string | `"<leader>ta"` | Keybinding to add annotation |
| `mappings.edit_task` | string | `"<leader>te"` | Keybinding to edit task in Taskwarrior editor |
| `mappings.show_blocking_dependencies` | string | `"<leader>tb"` | Keybinding to show dependencies (forward and reverse) |
| `mappings.add_dependency` | string | `"<leader>tB"` | Keybinding to add task as dependency |
| `mappings.undo_task` | string | `"<leader>tu"` | Keybinding to undo last action |
| `mappings.create_task` | string | `"<leader>tn"` | Keybinding to create new task |

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
