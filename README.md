# frontline.nvim

A Neovim plugin for integrating Taskwarrior task management directly into Markdown files.

## Features

- 📝 Embed Taskwarrior queries in Markdown headers
- 🔄 Automatic task list updates on file open/save
- ✅ Task status indicators: `[ ]` pending, `[S]` started, `[x]` completed, `[-]` deleted
- 🎯 Priority, dependency, and reverse dependency markers
- ⚙️ Configurable blank lines after task lists
- ⌨️ Interactive task management with keybindings
- 🔎 Compact task View with annotations, dependencies and inline TODO toggling
- 🕐 Local timezone display for dates and times
- 🗂️ Multiple Taskwarrior workspaces support with `@workspace` syntax
- 🎨 Smart autocomplete for projects, tags, dates, workspaces, and priorities
- 🔃 Configurable task sorting: global default and per-view `sort:` / `sort.reverse:` directives

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

### Task Sorting

Tasks within each view are sorted by urgency by default. You can change the default sort globally via config, or override it per-view using `sort:` and `sort.reverse:` directives in the header.

**Per-view sort syntax:**

```markdown
# Due Soon | +PENDING due.before:eow sort:due

# Recently Completed | +COMPLETED sort.reverse:completed

# By Project | @work +PENDING sort:project
```

`sort:field` sorts ascending; `sort.reverse:field` sorts descending. Active tasks always appear before completed/deleted tasks regardless of the sort field.

**Supported sort fields:**

| Field | Description |
|-------|-------------|
| `urgency` | Taskwarrior urgency score (default) |
| `priority` | Priority, ordered as configured in Taskwarrior (`uda.priority.values`) |
| `due` | Due date (earliest first) |
| `scheduled` | Scheduled date (earliest first) |
| `completed` / `end` | Completion date |
| `project` | Project name (alphabetical) |

Tasks with no value for the chosen field sort last (e.g. tasks without a due date when sorting by `due`).

**Global default sort:**

```lua
require('frontline').setup({
  default_sort = { field = "due", reverse = false },  -- default: urgency ascending
})
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
* [ ] Fix authentication bug (2025-11-15 10:00) [2025-11-20 17:00] [H🔒] (abcd1234)
* [ ] Simple task (abcd1234)
* [ ] Task with due date only [2025-11-20 17:00] (abcd1234)
```

Where:
- `[status]`: `[ ]` pending, `[S]` started, `[x]` completed, `[-]` deleted
- `description`: Task description from Taskwarrior
- `(scheduled)`: Scheduled date in rounded parenthesis (if set)
- `[due]`: Due date in squared brackets (if set)
- `[icons]`: Priority (the configured value, e.g. `H`), Dependencies (🔒), Reverse Dependencies (⚓)
- `(hash)`: Short task UUID (first 8 characters)

### Date Display

Dates are converted from Taskwarrior's UTC timestamps to your local timezone,
and a whole-day date (midnight) is shown as a bare day, without a time:

```markdown
* [ ] Fix authentication bug (2025-11-15 10:00) [2025-11-20 17:00] `abcd1234`
* [ ] Whole-day deadline [2025-11-20] `abcd1234`
```

Set `relative_dates = true` to show due, scheduled and completion dates as
`today`, `tomorrow`, `+3 days`, `2 weeks ago` and so on. In that format the day
alone says nothing about something happening in a few hours, so a date falling
**today** shows its time instead:

```markdown
* [ ] Dentist [⏰2pm] `abcd1234`
* [ ] Standup (⏱️10am) `abcd1234`
* [ ] Odd time [⏰11:35am] `abcd1234`
* [ ] Whole-day deadline [⏰today] `abcd1234`
* [ ] Not until tomorrow [⏰tomorrow] `abcd1234`
```

A time on its own always means today. A whole-day (midnight) event has no time
to show and keeps saying `today`. Completed tasks follow the same rule: a task
finished today shows the time of its `✅` end date, while older ones show the
day only.

### Priority Display

Priority is a Taskwarrior UDA, so the set of values and their order is whatever
`uda.priority.values` says. Frontline therefore displays the value itself rather
than mapping it to a fixed icon, and it stays correct if you redefine the values:

```
uda.priority.values=H,M,L,     ->  * [ ] Fix the parser [H🔒] `a1b2c3d4`
uda.priority.values=A,B,,C     ->  * [ ] Fix the parser [A🔒] `a1b2c3d4`
```

The empty entry marks where tasks with **no** priority rank. In `A,B,,C` above,
`C` sorts *below* a task with no priority at all; `sort:priority` honours this.

To show something other than the raw value, map it in `priority_labels`. Pick
glyphs of the same width so task lines stay aligned:

```lua
require('frontline').setup({
  priority_labels = { H = "↑", M = "-", L = "↓" },
})
```

Values without an entry keep showing as-is.

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
| `<leader>tv` | View Task | Open the compact task View (see below) |
| `<leader>ta` | Add Annotation | Add a note to the task |
| `<leader>tt` | Add TODO Annotation | Add a note pre-filled with `TODO: ` |
| `<leader>tm` | Modify Task | Modify task properties (prompts for input) |
| `<leader>te` | Edit Task | Open task in Taskwarrior's interactive editor |
| `<leader>tn` | Create Task | Create new task with smart context-aware pre-fill |
| `<leader>tB` | Add Dependency | Create new task as dependency of current task |
| `<leader>tu` | Undo Task | Undo last action on task |
| `<leader>tb` | Show Dependencies | Show task dependencies and reverse dependencies |
| `<leader>tr` | Show Blocked Tasks | Show tasks blocked by this task |
| `<leader>tc` | Copy Task | Copy the task to the clipboard (see [Copy Task Format](#copy-task-format)) |
| `<leader>to` | Open URL | Open a URL or file path found in the task's annotations |
| `<leader>tj` | Create Note | Create a Markdown note linked to the task |

### Task View

`<leader>tv` opens a floating window with everything worth knowing about the task
under the cursor:

```
╭─ Task ──────────────────────────────────────────────────────╮
│[S] Refactor the annotation shortcuts             `a2f1c3d8` │
│H · frontline.nvim · +nvim +ux · urgency 12.4                │
│⏱️ 2026-07-31 (tomorrow) · ⏰ 2026-08-02 (+3 days)            │
│                                                             │
│Annotations (3)                                              │
│  ☐ 2026-07-29  TODO: decide the floating window size        │
│  ☑ 2026-07-29  DONE: survey existing mappings               │
│  • 2026-07-28  NOTE: "~/notes/frontline-view.md"            │
│                                                             │
│Blocked by (2 · 1 open)                                      │
│  ☐ Design the View layout                      `9b7e0c11`   │
│  ☑ Read the mappings module                    `41d0a6f2`   │
│Blocking (1)                                                 │
│  ☐ Release v0.5.0                              `77aa31b9`   │
╰─────────────────────────────────────────────────────────────╯
```

The layout is dense on purpose: the status marker on the title line already says
pending/started/completed, every date shares one line, and project, tags,
priority and urgency share another. Each element appears only when it is set, so
most tasks are far shorter than the one above:

```
╭─ Task ───────────────────────────────────────╮
│[ ] Buy milk                       `3fa9c201` │
│home · urgency 1.2                            │
│⏰ 2026-07-31 (tomorrow)                       │
╰──────────────────────────────────────────────╯
```

A task with nothing but a description renders as a single line.

The window is sized to its content and grows with the terminal: the four size
options are read as a fraction of the screen when they are `1` or less, and as
absolute columns or rows otherwise. `min_height` defaults to 70% of the screen
so the window keeps a steady size whether or not the content fills it — a short
task in a snug window reads as if something has scrolled out of sight.
`max_width` keeps long annotations from stretching across a wide monitor, and
`max_height` decides when a task with many annotations starts to scroll instead
of growing.

#### Highlight groups

Each element of the View has its own highlight group, so a colorscheme or your
own config can restyle any one of them. All are defined as links with
`default = true`, so an existing definition always wins:

| Group | Links to | Applies to |
|-------|----------|------------|
| `FrontlineViewDescription` | `Title` | The task description on the title line |
| `FrontlineViewHash` | `Comment` | Short hashes, on the title and dependency lines |
| `FrontlineViewPriority` | `Statement` | The priority value |
| `FrontlineViewProject` | `Directory` | The project name |
| `FrontlineViewTags` | `Special` | The `+tag` list |
| `FrontlineViewRecur` | `Special` | The recurrence period |
| `FrontlineViewWaiting` | `Comment` | The `waiting` marker |
| `FrontlineViewUrgency` | `Comment` | The urgency value |
| `FrontlineViewSeparator` | `Comment` | The `·` between fields |
| `FrontlineViewOverdue` | `WarningMsg` | A due date in the past |
| `FrontlineViewSection` | `Title` | The Annotations / Blocked by / Blocking headers |
| `FrontlineViewTodo` | `WarningMsg` | The `☐` marker of an open annotation |
| `FrontlineViewDone` | `Comment` | A completed annotation |
| `FrontlineViewAnnotationDate` | `Comment` | The date prefix on an annotation |
| `FrontlineViewDepOpen` | `Normal` | An incomplete dependency |
| `FrontlineViewDepDone` | `Comment` | A completed dependency |

```lua
vim.api.nvim_set_hl(0, "FrontlineViewProject", { fg = "#7aa2f7", bold = true })
vim.api.nvim_set_hl(0, "FrontlineViewTags", { fg = "#9ece6a", italic = true })
```

Inside the View:

| Key | Action |
|-----|--------|
| `q`, `<Esc>` | Close the View |
| `a` | Add an annotation |
| `x` | Toggle the annotation under the cursor between `TODO:`/`DONE:` (or `[ ]`/`[x]`) |
| `d` | Toggle done |
| `s` | Toggle started |
| `e` | Edit the task in Taskwarrior's interactive editor, the same one `<leader>te` opens |
| `<CR>` | On an annotation: open its URL or file path. On a dependency: open that task's View |
| `<BS>` | Go back to the previous task after drilling into a dependency |
| `?` | Show these keys |

Only `q` and `<Esc>` close the window. Every other key re-renders the View in
place, so actions can be repeated without reopening it — add three annotations
in a row, tick off several TODOs, or start and stop a task while watching its
urgency change. Files opened with `<CR>` load into the window the View was
opened from and are waiting behind it once you close the View.

`e` is the exception: Taskwarrior's editor needs a full window, so the View steps
aside, the editor takes over the window the View was opened from, and the View
comes back on the same task once you write and quit — including the drill-down
history, so `<BS>` still walks back out of the dependencies you followed to get
there. Cancelling the edit brings the View back untouched.

`x` is the quickest way to clear the outstanding TODOs that block task completion
when `require_todo_annotations_done` is enabled. Taskwarrior has no "edit
annotation" command, so the toggle removes the annotation and re-adds it with the
new text — the annotation's timestamp is reset as a result.

### Smart Task Creation with Autocomplete

The plugin provides intelligent autocomplete when creating tasks (`<leader>tn`) or adding dependencies (`<leader>tB`).

**Autocomplete Features:**
- **Projects** (`project:`): Suggests existing projects from your Taskwarrior database
- **Tags** (`+`): Suggests existing tags (excluding virtual tags like PENDING, COMPLETED)
- **Dates** (`due:`, `scheduled:`): Suggests common date shortcuts (today, tomorrow, eow, 1w, etc.)
- **Workspaces** (`@`): Suggests configured workspaces
- **Priority** (`priority:`): Suggests the values configured in Taskwarrior (H, M, L by default)

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

" Press <leader>tv to see the whole task: dates, tags, annotations, dependencies

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
  view = {
    min_width = 0.5,          -- Narrowest the View gets
    max_width = 0.9,          -- Widest the View gets
    min_height = 0.7,         -- Shortest the View gets
    max_height = 0.85,        -- Tallest the View gets
    border = "rounded",       -- Any border accepted by nvim_open_win
    show_urgency = true,      -- Show urgency on the attribute line
    show_dependencies = true, -- Show the "Blocked by" / "Blocking" sections
    annotation_dates = true,  -- Prefix annotations with their date
  },
  mappings = {
    toggle_done = "<leader>td",      -- Toggle task done/undone
    toggle_started = "<leader>ts",   -- Toggle task started/unstarted
    view_task = "<leader>tv",        -- Open the task View
    add_annotation = "<leader>ta",   -- Add task annotation
    modify_task = "<leader>tm",      -- Modify task properties
    edit_task = "<leader>te",        -- Edit task in Taskwarrior editor
    show_blocking_dependencies = "<leader>tb",  -- Show dependencies
    add_dependency = "<leader>tB",   -- Add task as dependency
    undo_task = "<leader>tu",        -- Undo last action
    create_task = "<leader>tn",      -- Create new task
  },
})
```

### Breaking changes

`<leader>ta` used to list a task's annotations and `<leader>tA` added one. Since
annotations are created far more often than they are listed, the two have been
reworked:

- `<leader>ta` now **adds** an annotation (this matches what this README has always documented).
- `<leader>tA` is no longer bound by default.
- `<leader>tv` opens the task View, which shows annotations along with the rest of the task.

The standalone annotation list is still available as `mappings.show_annotations`;
it simply has no default binding any more. If you bind it back to `<leader>ta`,
your binding wins over `add_annotation` and the plugin warns once at startup.

```lua
require('frontline').setup({
  mappings = {
    show_annotations = "<leader>tA",  -- keep the old list on a different key
  },
})
```

### Available Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `newlines_after_tasks` | number | 2 | Number of blank lines to add after each task list |
| `convert_dates_to_local` | boolean | true | Convert Taskwarrior's UTC timestamps to the local timezone |
| `relative_dates` | boolean | false | Show due/scheduled/end dates as `tomorrow`, `+3 days`, `2 weeks ago`, and today's dates as their time (`2pm`). See [Date Display](#date-display) above. |
| `workspaces` | table | `{}` | Map of workspace names to Taskwarrior rc file paths |
| `default_workspace` | string | `nil` | Default workspace name (nil uses system taskwarrior) |
| `enable_reverse_dependencies` | boolean | true | Enable reverse dependency tracking (⚓ icon and "tasks this task is blocking" view) |
| `reverse_dependencies_warn_threshold` | number | 1000 | Warn if reverse dependency queries take longer than this (in milliseconds). Set to 0 to disable warnings. |
| `default_sort` | table | `{ field = "urgency", reverse = false }` | Default sort for all views. `field` can be `urgency`, `priority`, `due`, `scheduled`, `completed`, or `project`. Set `reverse = true` to flip the order. |
| `copy_task_format` | string | `"{{description}}"` | Template for the `<leader>tc` copy-to-clipboard action. See [Copy Task Format](#copy-task-format) below. |
| `priority_labels` | table | `{}` | Text shown for each priority value. Empty means the value itself is displayed. See [Priority Display](#priority-display) below. |
| `notes_directory` | string | `nil` | Directory where task notes are created (nil = current working directory). Overridden per workspace. |
| `note_template` | string | `nil` | Markdown file used as the note template (nil = built-in template). See [Task Notes](#task-notes) below. |
| `view.min_width` | number | 0.5 | Narrowest the task View gets |
| `view.max_width` | number | 0.9 | Widest the task View gets |
| `view.min_height` | number | 0.7 | Shortest the task View gets |
| `view.max_height` | number | 0.85 | Tallest the task View gets |
| `view.border` | string | `"rounded"` | Border style for the task View window |
| `view.show_urgency` | boolean | true | Show urgency on the View's attribute line |
| `view.show_dependencies` | boolean | true | Show the "Blocked by" / "Blocking" sections in the View |
| `view.annotation_dates` | boolean | true | Prefix annotations in the View with their date |
| `mappings.toggle_done` | string | `"<leader>td"` | Keybinding to toggle task done/undone |
| `mappings.toggle_started` | string | `"<leader>ts"` | Keybinding to toggle task started/unstarted |
| `mappings.view_task` | string | `"<leader>tv"` | Keybinding to open the task View |
| `mappings.modify_task` | string | `"<leader>tm"` | Keybinding to modify task |
| `mappings.add_annotation` | string | `"<leader>ta"` | Keybinding to add annotation |
| `mappings.show_annotations` | string | `nil` | Keybinding to list annotations only (no default; the View covers this) |
| `mappings.add_todo_annotation` | string | `"<leader>tt"` | Keybinding to add an annotation pre-filled with `TODO: ` |
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

### Copy Task Format

The `copy_task_format` option controls what gets copied to the clipboard when you press `<leader>tc`. It uses a Jinja-like `{{placeholder}}` syntax:

```lua
require('frontline').setup({
  -- Examples:
  copy_task_format = "{{description}}",                                   -- default
  copy_task_format = "* [ ] {{description}}",                             -- bullet + checkbox
  copy_task_format = "* [ ] {{description}} +{{project}} due:{{due}}",    -- full detail
  copy_task_format = "{{description}} {{tags}}",                          -- with tags
  copy_task_format = "{{description}} `{{short_uuid}}`",                  -- with short hash
})
```

Available placeholders:

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{{description}}` | Task description | `Fix the login bug` |
| `{{uuid}}` | Full UUID | `abcdef12-3456-...` |
| `{{short_uuid}}` | First 8 chars of UUID | `abcdef12` |
| `{{status}}` | Task status | `pending` |
| `{{project}}` | Project name | `work` |
| `{{priority}}` | Priority value | `H`, `M`, or `L` by default |
| `{{tags}}` | Space-separated tags | `urgent backend` |
| `{{due}}` | Due date | `2025-12-25 10:30` |
| `{{scheduled}}` | Scheduled date | `2025-12-20` |
| `{{urgency}}` | Urgency score | `15.5` |

Empty placeholders are replaced with an empty string and trailing whitespace is trimmed.

### Task Notes

`<leader>tj` creates a Markdown note for the task under the cursor, links it back
to the task with a `NOTE: "path"` annotation, and opens it. The file is created in
`notes_directory` (or the current working directory), and the proposed path can be
edited in the prompt.

By default the note uses the built-in template:

```markdown
---
task: `abcdef12`
---

# Fix the login bug
```

Set `note_template` to use one of your own templates instead — typically a file
already living in your vault:

```lua
require('frontline').setup({
  notes_directory = "~/notes",
  note_template = "templates/task.md",  -- relative paths resolve inside notes_directory
  -- note_template = "~/notes/templates/task.md",  -- absolute paths work too

  -- Both options can also be set per workspace:
  workspaces = {
    work = {
      rc = "~/.config/taskwarrior/work/.taskrc",
      notes_directory = "~/notes/work",
      note_template = "templates/work-task.md",
    },
  },
})
```

The per-workspace value wins over the global one, which wins over the built-in
template. If the configured file cannot be read, frontline warns and falls back to
the built-in template rather than failing the note creation.

**The `task:` metadata is always added by frontline.** A template — built-in or
your own — never has to (and never can) provide the link to Taskwarrior:

- No frontmatter in the template → frontline prepends a block containing `task:`.
- Frontmatter present → `task:` is added to it, keeping your other keys.
- A `task:` key already in the frontmatter → frontline overwrites its value.

So a template like this:

```markdown
---
tags: [task, work]
created: {{date}}
---

# {{title}}

## Context

## Next steps
```

produces:

```markdown
---
tags: [task, work]
created: 2025-12-25
task: `abcdef12`
---

# Fix the login bug

## Context

## Next steps
```

Templates support the same placeholders as [Copy Task Format](#copy-task-format),
plus:

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{{title}}` | Task description (alias of `{{description}}`) | `Fix the login bug` |
| `{{date}}` | Current date | `2025-12-25` |
| `{{time}}` | Current time | `10:30` |

Unlike the copy format, placeholders frontline does not recognise are left in the
note untouched, so templates shared with other plugins keep working.

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

All tests should pass (33/33):
- Integration tests: 5
- Parser tests: 6
- Task Client tests: 4
- Renderer tests: 18

## License

MIT

## Contributing

Contributions welcome! Please feel free to submit a Pull Request.
