## Relevant Files

- `lua/taskwarrior_nvim/init.lua` - Main plugin entry point, handles setup, autocmds, and core logic.
- `lua/taskwarrior_nvim/parser.lua` - Module for parsing Markdown headers and extracting Taskwarrior queries.
- `lua/taskwarrior_nvim/task_client.lua` - Module for interacting with the `task` command, executing queries, and parsing JSON output.
- `lua/taskwarrior_nvim/renderer.lua` - Module for formatting and rendering Taskwarrior tasks into the Neovim buffer.
- `lua/taskwarrior_nvim/mappings.lua` - Module for defining and handling user interaction mappings.
- `lua/taskwarrior_nvim/utils.lua` - Utility functions (e.g., for string manipulation, error display).
- `lua/taskwarrior_nvim/test_utils.lua` - Utility functions for testing.
- `tests/parser_spec.lua` - Unit tests for the parser module.
- `tests/task_client_spec.lua` - Unit tests for the task_client module.
- `tests/renderer_spec.lua` - Unit tests for the renderer module.
- `tests/integration_spec.lua` - Integration tests for the overall plugin functionality.

### Notes

- Unit tests should typically be placed alongside the code files they are testing (e.g., `MyComponent.lua` and `MyComponent_spec.lua` in the same directory, or in a dedicated `tests` directory mirroring the `lua` structure).
- For Neovim Lua plugins, testing often involves using a testing framework like `plenary.nvim` or `busted`. We will assume `plenary.nvim` for now.
- To run tests, you would typically use a command like `nvim --headless -c "PlenaryBustedDirectory tests/"` or similar, depending on the chosen testing framework.

## Tasks

- [ ] 1.0 Plugin Setup and Initialization
  - [x] 1.1 Create the basic plugin structure (`lua/taskwarrior_nvim/init.lua`).
  - [x] 1.2 Define the main setup function for the plugin.
  - [x] 1.3 Implement basic Neovim autocmds for `BufReadPost` and `BufWritePost` to trigger task list refresh.
  - [x] 1.4 Add a placeholder command `:TaskwarriorRefresh` for manual refresh.
- [ ] 2.0 Markdown Parsing and Query Extraction
  - [x] 2.1 Create `lua/taskwarrior_nvim/parser.lua`.
  - [x] 2.2 Implement a function to read the current buffer content.
  - [x] 2.3 Implement logic to identify Markdown headers containing Taskwarrior queries (e.g., `# Header | query`).
  - [x] 2.4 Extract the Taskwarrior query string from the identified headers.
  - [x] 2.5 Write unit tests for `parser.lua` to cover various header and query formats.
- [ ] 3.0 Taskwarrior Integration and Data Retrieval
  - [x] 3.1 Create `lua/taskwarrior_nvim/task_client.lua`.
  - [x] 3.2 Implement a function to execute `task <query> export` using `vim.fn.system()`.
  - [x] 3.3 Implement error handling for `task` command execution (e.g., command not found, invalid query).
  - [x] 3.4 Parse the JSON output from `task export` into a Lua table.
  - [x] 3.5 Write unit tests for `task_client.lua` to mock `vim.fn.system()` and test JSON parsing and error handling.
- [ ] 4.0 Task List Rendering
  - [x] 4.1 Create `lua/taskwarrior_nvim/renderer.lua`.
  - [x] 4.2 Implement a function to format a single Taskwarrior task into the specified Markdown list item format: `* [status] [description] (due date) [priority_dependency_annotation_icons] (short_hash)`.
  - [x] 4.3 Implement logic to determine the `[status]` indicator (`[ ]`, `[S]`, `[x]`).
  - [x] 4.4 Implement logic to determine the `[priority_dependency_annotation_icons]` (H/M/L, 🔒, A).
  - [ ] 4.5 Implement a function to replace the existing task list section in the buffer with the newly rendered list.
  - [x] 4.6 Write unit tests for `renderer.lua` to test various task data inputs and expected output formats.
- [ ] 5.0 Automatic Refresh Mechanism
  - [x] 5.1 Integrate the parser, task_client, and renderer modules into `init.lua` to create the refresh logic.
  - [ ] 5.2 Ensure the refresh mechanism correctly identifies the section to update and preserves surrounding content.
  - [x] 5.3 Implement the `BufReadPost` and `BufWritePost` autocmds to trigger the refresh.
  - [x] 5.4 Implement the `:TaskwarriorRefresh` command to manually trigger a refresh.
  - [x] 5.5 Write integration tests to verify automatic and manual refresh functionality.
- [ ] 6.0 User Interaction Mappings
  - [ ] 6.1 Create `lua/taskwarrior_nvim/mappings.lua`.
  - [ ] 6.2 Implement a function to get the `short_hash` of the task under the cursor.
  - [ ] 6.3 Implement a mapping to toggle task status (done/undone) using `task <short_hash> done` or `task <short_hash> undo`.
  - [ ] 6.4 Implement a mapping to toggle task status (started/unstarted) using `task <short_hash> start` or `task <short_hash> stop`.
  - [ ] 6.5 Implement a mapping to modify task description, prompting the user for input and executing `task <short_hash> <user string>`.
  - [ ] 6.6 Implement a mapping to add an annotation, prompting the user for input and executing `task <short_hash> annotation:<user string>`.
  - [ ] 6.7 Ensure that after any task modification, the relevant section of the buffer is reloaded.
  - [ ] 6.8 Write integration tests for user interaction mappings.
- [ ] 7.0 Error Handling
  - [ ] 7.1 Implement a utility function in `lua/taskwarrior_nvim/utils.lua` to display error messages at the bottom of the Neovim buffer.
  - [ ] 7.2 Integrate error display for invalid Taskwarrior queries or command execution failures.
  - [ ] 7.3 Ensure error messages are cleared after a successful refresh or user action.
  - [ ] 7.4 Write tests to verify error handling scenarios.
