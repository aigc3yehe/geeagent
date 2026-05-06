# Todo Manager

Todo Manager is GeeAgent's local-first task gear. It is inspired by the quick
capture and task organization shape of TickTick, but it does not sync with a
TickTick account in V1.

## Data

Todo records live under:

```text
~/Library/Application Support/GeeAgent/gear-data/todo.manager/
```

The gear owns its lists, tasks, event records, and reminder scheduling metadata.
Mutable task data must not be written into `WorkbenchStore` or another Gear's
private storage.

## Agent Capabilities

- `todo.create`: create a local todo with list, tags, priority, dates,
  reminders, repeat metadata, and checklist items.
- `todo.query`: read local todos by status, list, tags, priority, date range,
  due bucket, or search text.
- `todo.update`: update task fields or completion state.
- `todo.delete`: soft-delete one task and cancel scheduled notifications.

Capabilities return structured task data, warnings, and failure codes. Reminder
authorization problems must be reported as partial or failed scheduling state,
not hidden behind a successful reminder claim.

## Current Limits

- V1 is local-only and does not call the TickTick API.
- `repeat_rrule` is stored and displayed as task metadata. Automatic recurrence
  expansion is a later slice.
- Codex calls use the generated Gee MCP bridge and shared external invocation
  queue. Codex must not run package-local scripts to modify todo data.
