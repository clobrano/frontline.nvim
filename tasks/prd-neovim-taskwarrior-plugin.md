# Product Requirements Document: Neovim Taskwarrior Plugin

## 1. Introduction/Overview

This document outlines the requirements for a Neovim plugin designed to integrate with the Taskwarrior task manager. The primary goal is to enhance a user's workflow by allowing them to track and update Taskwarrior tasks directly within their Neovim Markdown files. This plugin will enable users to embed Taskwarrior queries within Markdown headers, displaying the matching tasks in a formatted list below the header. The task list will automatically refresh upon file open/reload and save.

## 2. Goals

*   Enable Neovim users to view and manage their Taskwarrior tasks within Markdown files.
*   Provide a seamless way to integrate Taskwarrior queries into daily notes or project documentation.
*   Improve productivity by reducing context switching between Neovim and the command line for basic task management.

## 3. User Stories

*   As a project manager, I want to embed Taskwarrior queries in my weekly/journal Markdown file so that I can see relevant tasks for the week or day directly in my notes.
*   As a Neovim user, I want the task list to automatically refresh when I open, reload, or save my Markdown file so that I always see an up-to-date list of tasks.
*   As a Neovim user, I want to be able to mark tasks as done or undone directly from the displayed list so that I can quickly update my task status without leaving Neovim.
*   As a Neovim user, I want to be able to modify task descriptions and add annotations to tasks from within Neovim so that I can keep my task details current.

## 4. Functional Requirements

1.  **Markdown Header Parsing:**
    1.1. The plugin SHALL identify Taskwarrior queries within Markdown headers.
    1.2. A Taskwarrior query SHALL be identified by a pipe `|` character separating the Markdown header from the query string (e.g., `# My Tasks | project:myproject +PENDING`).
2.  **Taskwarrior Query Execution:**
    2.1. The plugin SHALL execute the identified Taskwarrior query using the `task <query> export` command to retrieve task data in JSON format.
    2.2. The plugin SHALL display the results of the query in a formatted list directly below the Markdown header.
3.  **Task List Display:**
    3.1. Each task in the list SHALL be displayed as a Markdown list item.
    3.2. The default format for each task SHALL be: `* [status] [description] (due date) [priority_dependency_annotation_icons] (short_hash)`.
    3.4. After the due date, an OPTIONAL section `[priority_dependency_annotation_icons]` SHALL be displayed, containing 1-2 character icons for:
        *   **Priority:** `H` (High), `M` (Medium), `L` (Low), or empty if no priority.
        *   **Dependency:** `🔒` (lock icon) if the task has dependencies, or empty otherwise.
        *   **Annotation:** `A` if the task has annotations, or empty otherwise.
        *   Example: `[H,🔒,A]` or `[M,A]` or `[L]` or `[🔒]`, or nothing if the tasks has none of them.
    3.5. The `[status]` indicator SHALL be:
        *   `[ ]` for pending tasks.
        *   `[S]` for started tasks.
        *   `[x]` for completed tasks.

4.  **Automatic Refresh:**
    4.1. The task list SHALL automatically refresh when the Markdown file is opened or reloaded in Neovim.
    4.1. The task list SHALL automatically refresh before the Markdown file is saved in Neovim.
5.  **User Interaction (Mappings):**
    5.1. The plugin SHALL provide a Neovim mapping to toggle a task's status between done and undone.
    5.2. The plugin SHALL provide a Neovim mapping to toggle a task's status between started and unstarted.
    5.3. The plugin SHALL provide a Neovim mapping to modify a task's description. This SHALL prompt the user for a modification string and execute `task <short_hash> <user string>`.
    5.4. The plugin SHALL provide a Neovim mapping to add an annotation to a task. This SHALL prompt the user for an annotation string and execute `task <short_hash> annotation:<user string>`.
    5.5. After any user interaction that modifies a task, the task list for the affected section SHALL be reloaded.

## 5. Non-Goals (Out of Scope)

*   Support for multiple Taskwarrior databases in the initial version.
*   Advanced Taskwarrior reporting features.
*   Complex filtering or sorting within Neovim beyond what the Taskwarrior query provides.
*   Allow users to customize the output format of tasks.

## 6. Design Considerations

*   The plugin should aim for compatibility with the Taskwiki plugin's header query format, but it is not mandatory.

## 7. Technical Considerations

*   The plugin SHALL be implemented in Lua.
*   The plugin SHALL utilize the `task export` command to retrieve task data in JSON format for reliable parsing.
*   Error messages for invalid Taskwarrior queries or no results should be displayed at the bottom of the Neovim buffer.

## 8. Success Metrics

*   Successful parsing and display of Taskwarrior tasks from Markdown headers.
*   Correct and timely refreshing of task lists.
*   Successful execution of task modification, toggle, and annotation commands from within Neovim.

## 9. Open Questions

*   None at this time.
