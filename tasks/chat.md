# Clarifying Questions for Neovim Taskwarrior Plugin PRD

Please provide your answers inline to the following questions to help me create a comprehensive PRD.

## 1. Problem/Goal
What specific problem does this plugin solve for Neovim users who use Taskwarrior? What is the main benefit they will get?

I can write my weekly/journal markdown file with specific headers showing the tasks for the week, the day, etc.

## 2. Target User
Who is the primary user of this plugin? (e.g., developers, writers, project managers)

It is a project manager tool

## 3. Core Functionality - Markdown Headers and Queries
You mentioned "Markdown headers with some simple queries for Taskwarrior."
a. Can you give examples of what these "simple queries" might look like?

```markdown
\# This is the normal header | (project:TNF or project:M8s) +WEEK
```

The above is a normal Markdown header, after the pipe there is a normal Taskwarrior query, so that the `task` command can parse it and return the list of tasks

e.g.

```bash
$ task "(project:TNF or project:M8s) +WEEK"

ID  Project       Tag desc                                                                                                             due
253 TNF.sprint279 [2] [OCPEDGE-2213] _[TNF] podman-etcd should recover from double graceful node shutdown_ ^                           4d
                        2025-11-05 resource-agents branch fix-learner-stale-attribute
                        2025-11-05 I also noticed that this is probably the as same as [OCPBUGS-62856], or at least the same root
                      cause
237 TNF.sprint279 [2] [OCPEDGE-1788] create cold-boot e2e tests from mixed gns and ungns scenarios => [openshift/origin PR30404] ^     4d
                        2025-10-27 already in review, remove the due date
                        2025-10-29 re-launched test after rebase and cleanups

2 tasks
```

NOTE that the tool shall use the `export` command, to be able to parse the data in Json format
```bash
$ task "(project:TNF or project:M8s) +WEEK" export
[
{"id":237,"description":"[OCPEDGE-1788] create cold-boot e2e tests from mixed gns and ungns scenarios => [openshift\/origin PR30404] ^","due":"20251114T170000Z","entry":"20251016T094132Z","modified":"20251110T072239Z","project":"TNF.sprint279","start":"20251016T101659Z","status":"pending","uuid":"cf4467bc-6e87-4a54-8364-3f9bba4fbf05","annotations":[{"entry":"20251027T072348Z","description":"already in review, remove the due date"},{"entry":"20251029T144137Z","description":"re-launched test after rebase and cleanups"}],"tags":["hold","sprint"],"urgency":13.7426},
{"id":253,"description":"[OCPEDGE-2213] _[TNF] podman-etcd should recover from double graceful node shutdown_ ^","due":"20251114T170000Z","entry":"20251026T082458Z","modified":"20251110T072239Z","priority":"H","project":"TNF.sprint279","start":"20251028T190311Z","status":"pending","uuid":"6c39fb56-cd32-4061-b19e-298dc0392c27","annotations":[{"entry":"20251105T090515Z","description":"resource-agents branch fix-learner-stale-attribute"},{"entry":"20251105T131303Z","description":"I also noticed that this is probably the as same as [OCPBUGS-62856], or at least the same root cause"}],"tags":["etcd","sprint"],"urgency":19.6933}
]
```


b. How should the plugin identify a Taskwarrior query within a Markdown header? (e.g., a specific prefix like `# Taskwarrior: pending`, or a code block, etc.)

I want it to be compatible with Taskwiki plugin, hence the Markdown header is separated from the query via a pipe `|`

c. What kind of Taskwarrior data should be displayed in the section below the header? (e.g., task ID, description, due date, project, tags, status)

I want the following data: `* [status] [description] (due date) <priority> (short_hash)`, see the example below

```
* [S] [OCPBUGS-60588] _TNF Podman-etcd should use etcdctl snapshot utility to backup data_ (2025-11-11 10:00) (b9bcad69)  #94ed86cf
```

So we have a markdown list, starting with a checkbox `[ ]`, empty if the task is undone, with an S if started `[S]`, with an x if done `[x]`

I'd like this to be configurable though

Then there is the task's description (e.g. [OCPBUGS-60588] _TNF Podman-etcd should use etcdctl snapshot utility to backup data_)

Then due date (with or without time) (e.g. (2025-11-11 10:00))

Then the priority (H for high, M for medium, L for low, or nothing)

Then the short hashcode in between parentesis (e.g.  (b9bcad69))


## 4. User Interaction
a. How should the user trigger the refresh of the task list beyond file open/reload? (e.g., a specific Neovim command, saving the file, a timer)

When loading the file and when saving

b. Will the user be able to interact with the displayed tasks directly within Neovim? If so, what actions? (e.g., mark as done, edit description, add tags)

Yes there will be mappings to
1. toggle mark done, undone
2. Modify => we want a text area to get the modification string, then we can use `task <short_hash> [user string]` and reload the page
3. Add annotation => we want a text area to get the annotation string, then we can use `task <short_hash> annotation:[user string]` and reload the page 

## 5. Non-Goals
Are there any specific Taskwarrior functionalities or Neovim integrations that this plugin *should not* include in its initial version?

Not support for multiple Taskwarrior databases

## 6. Design/UI
Are there any preferences for how the tasks should be formatted or highlighted within the Neovim buffer?

No

## 7. Error Handling
How should the plugin handle cases where a Taskwarrior query is invalid or returns no results?

Show an error message at the bottom

## 8. Configuration
Will there be any configuration options for the plugin? (e.g., default query, refresh interval)

Not in this version


