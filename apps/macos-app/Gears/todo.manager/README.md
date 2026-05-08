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

- `todo.create`: create or reuse a local todo with list, tags, priority, dates,
  reminders, repeat metadata, checklist items, and an optional idempotency key.
- `todo.query`: read local todos by status, list, tags, priority, date range,
  due bucket, or search text.
- `todo.update`: update task fields or completion state.
- `todo.delete`: soft-delete one task and cancel scheduled notifications.

Capabilities return structured task data, warnings, and failure codes. Common
today, tomorrow, single non-reminder day-part, next-weekday, explicit
`YYYY-MM-DD`, weekend, and reminder phrasing is normalized into structured
dates where possible. Create calls reuse matching idempotency keys and
short-window exact duplicates so agent retries do not create duplicate tasks.
Reminder-only tasks can appear in Today/Upcoming, and the native inspector can
add, edit, remove, and clear absolute or due-relative reminders. Reminder
requests without a
concrete clock time and reminder authorization problems must be reported as
structured failure or partial scheduling state, not hidden behind a successful
reminder claim.
Query payloads include schedule summaries (`date_source`, `date_state`,
`time_state`, `is_overdue`, and `relevant_at`) so agents and the native list can
distinguish due, start, reminder-only, all-day, timed, overdue, and unscheduled
tasks without guessing.

## Current Limits

- V1 is local-only and does not call the TickTick API.
- `repeat_rrule` is stored and displayed as task metadata. Automatic recurrence
  expansion is a later slice.
- Codex calls use the generated Gee MCP bridge and shared external invocation
  queue. Codex must not run package-local scripts to modify todo data.
