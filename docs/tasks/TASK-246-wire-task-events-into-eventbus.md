# TASK-246: Wire Task Events into EventBus

**Status:** done
**Branch:** `task/246-wire-task-events-into-eventbus`
**Depends on:** TASK-054 (EventBus), TASK-105 (NotificationDispatcher)

## Objective

When task status changes to terminal states (completed, failed, dead_letter, expired),
publish events to the EventBus so agents can subscribe and receive notifications via
`/events/poll`.

## Requirements

### Functional

- [ ] FR-1: Terminal task statuses (completed, failed, dead_letter, expired) publish corresponding events to EventBus
- [ ] FR-2: Event types are `task.completed`, `task.failed`, `task.dead_letter`, `task.expired`
- [ ] FR-3: Non-terminal statuses (pending, in_progress, waiting, cancelled, awaiting_children) do NOT publish events
- [ ] FR-4: Event payload includes task_id, task_type, status, hive_id, target_agent_id, result_summary
- [ ] FR-5: source_agent_id is set to the claiming agent when it belongs to the same hive
- [ ] FR-6: Existing notification dispatch (webhooks) continues to work unchanged
- [ ] FR-7: EventBus publish failures are caught and logged without breaking task completion
- [ ] FR-8: Agents subscribed to task event types can poll and receive them via /events/poll

### Non-Functional

- [ ] NF-1: No Cloud namespace imports (CE-compatible)
- [ ] NF-2: SQLite-compatible queries
- [ ] NF-3: PSR-12 / Pint compliant

## Implementation

The wiring is done in `DispatchSystemEventNotification::handleTaskStatusChanged()`, which
already listens for `TaskStatusChanged` events and dispatches to notification endpoints.
The EventBus publish is added alongside (not replacing) the notification dispatch, each
in its own try/catch block to ensure independence.
