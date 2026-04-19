# TASK-246: Wire task events into EventBus

**Status:** done
**Branch:** `task/246-task-events-eventbus`
**Depends on:** —
**Blocks:** TASK-249
**Edition:** shared
**Feature doc:** [FEATURE_CHANNELS.md](../features/list-1/FEATURE_CHANNELS.md) §7.1

## Objective

Publish task lifecycle events to the EventBus when tasks reach terminal states, so agents can subscribe to and poll for task notifications via the existing `/events/poll` endpoint.

## Background

Task state transitions already trigger Laravel broadcasts (for the dashboard WebSocket) and the notification dispatcher (for external webhooks). This task adds a third publish target — the EventBus — so that agents polling `/events/poll` are notified of task completions, failures, and other terminal states without needing a separate endpoint.

This is additive: existing broadcast and notification dispatcher behavior is unchanged.

## Requirements

### Functional

- [ ] FR-1: When a task transitions to `completed`, publish a `task.completed` event to the EventBus
- [ ] FR-2: When a task transitions to `failed`, publish a `task.failed` event to the EventBus
- [ ] FR-3: When a task transitions to `dead_letter`, publish a `task.dead_letter` event to the EventBus
- [ ] FR-4: When a task transitions to `expired`, publish a `task.expired` event to the EventBus
- [ ] FR-5: Event payload includes: `task_id`, `hive_id`, `type`, `target_agent_id`, `status`, `result_summary` (truncated to 500 chars)
- [ ] FR-6: Events are hive-scoped — only agents subscribed within the same hive receive them (consistent with `EventBus::dispatch()` which matches subscriptions by event type + hive scope)
- [ ] FR-7: Include `target_agent_id` in the event payload so consuming agents can filter client-side for events relevant to them. Note: the EventBus does not currently support agent-targeted delivery — dispatch and poll are keyed only by event type plus hive/apiary scope. If agent-targeted routing is needed, it must be built as a prerequisite (see FR-8).
- [ ] FR-8: (Prerequisite) Evaluate whether agent-targeted delivery is needed for task events. Options: (a) consuming agents filter by `target_agent_id` in the payload (simplest, no EventBus changes), or (b) add a `target_agent_id` column to the `events` table and filter in `EventBus::poll()` (more efficient but requires schema + service changes). Recommend option (a) for initial implementation since task events are low-volume.

### Non-Functional

- [ ] NFR-1: Event publishing must not block the task state transition — use queue dispatch if EventBus publish is expensive
- [ ] NFR-2: Reuse the existing `EventBus` service (TASK-053) for publishing — no new event infrastructure
- [ ] NFR-3: Event type prefix follows existing convention: `task.*`

## Architecture & Design

### Convergence Point: `TaskStatusChanged` Event

Most code paths that transition tasks to terminal states converge on the `TaskStatusChanged` Laravel event, but several paths are incomplete — they either use `safeBroadcast()` (WebSocket only, no listener dispatch) or emit no event at all. The full inventory:

| Path | Method | Dispatch mechanism |
|------|--------|--------------------|
| Agent completes task | `TaskController::complete()` → `runCompletionSideEffects()` | `event(TaskStatusChanged::fromTask())` via `DB::afterCommit` |
| Agent fails task | `TaskController::fail()` | `safeBroadcast(TaskStatusChanged::fromTask())` |
| Response delivery | `TaskController::deliverResponse()` | `event(TaskStatusChanged::fromTask())` via `DB::afterCommit` |
| Webhook wait completes | `WebhookWaitService::completeWaitingStep()` | `event(TaskStatusChanged::fromTask())` via `DB::afterCommit` |
| Webhook wait expires | `WebhookWaitService::expireTimedOutWaitTasks()` | `safeBroadcast(TaskStatusChanged::fromTask())` |
| Parent completed by policy | `CompletionPolicyService::completeParent()` | `event(TaskStatusChanged::fromTask())` via `DB::afterCommit` |
| Parent failed by policy | `CompletionPolicyService::failParent()` | `event(TaskStatusChanged::fromTask())` via `DB::afterCommit` |
| Workflow run completes | `WorkflowExecutionService::completeRun()` | `event(TaskStatusChanged::fromTask())` via `DB::afterCommit` |
| Workflow run fails | `WorkflowExecutionService::failRun()` | `event(TaskStatusChanged::fromTask())` via `DB::afterCommit` |
| Missing dependency | `TaskDependencyService::registerDependencies()` | `event(TaskStatusChanged::fromTask())` via `DB::afterCommit` |
| Dependency failure | `TaskDependencyService::evaluateSingleWaitingTask()` | `event(TaskStatusChanged::fromTask())` via `DB::afterCommit` |
| Task expiry | `TaskExpiryService::handle()` | `safeBroadcast(TaskStatusChanged::fromTask())` |
| Task timeout (max retries) | `TaskTimeoutService::failTask()` | None — no `TaskStatusChanged` emitted |
| Progress timeout (max retries) | `ProgressTimeoutService::handleMaxRetriesExceeded()` | None — no `TaskStatusChanged` emitted |

The existing `DispatchSystemEventNotification` listener (registered in `AppServiceProvider::registerNotificationListeners()`) already uses this convergence point to fan out notifications for all terminal task transitions. The EventBus publish should follow the same pattern.

### Files to Create / Modify

| Action | Path | Purpose |
|--------|------|---------|
| Create | `app/Listeners/PublishTaskEventToEventBus.php` | Listener that publishes task terminal events to EventBus, registered on `TaskStatusChanged` |
| Modify | `app/Providers/AppServiceProvider.php` | Register `PublishTaskEventToEventBus` listener on `TaskStatusChanged` (alongside existing `DispatchSystemEventNotification`) |
| Modify | `app/Services/EventBus.php` | Ensure publish method supports the task event payload shape |
| Create | `tests/Feature/TaskEventBusTest.php` | Test that terminal task transitions publish to EventBus |

### Key Design Decisions

- **Use `TaskStatusChanged` as the shared hook point** — do NOT scatter EventBus publish calls across controllers and services. All terminal transitions already converge on this event. Register a new listener in `AppServiceProvider` alongside the existing `DispatchSystemEventNotification` listener. This mirrors the proven pattern at `app/Providers/AppServiceProvider.php:128–131` and `app/Listeners/DispatchSystemEventNotification.php:25–63`.
- The new `PublishTaskEventToEventBus` listener filters for terminal statuses (`completed`, `failed`, `dead_letter`, `expired`) — same match logic as `DispatchSystemEventNotification::handleTaskStatusChanged()`.
- Publish to EventBus alongside (not instead of) existing broadcast + notification dispatcher
- Use the same `EventBus::publish()` method used by agent-to-agent events (note: the service class is `EventBus`, not `EventBusService`)
- Event type uses dot-notation (`task.completed`) consistent with existing event naming
- No agent-targeted delivery in initial implementation — the EventBus dispatches events based on event type + hive/apiary scope only (see `EventBus::dispatch()` lines 198–218 and `EventBus::poll()` lines 235–285). Consuming agents filter by `target_agent_id` in the event payload if they only want events for tasks targeted at them.
- **Important caveat:** Five paths do not currently trigger `Event::listen()` handlers and must be fixed as a prerequisite within this task:
  - **`safeBroadcast()` paths (3)** — these only broadcast to WebSocket channels, they do NOT trigger `Event::listen()` handlers. Must be migrated to `event()`:
    1. `TaskController::fail()`
    2. `WebhookWaitService::expireTimedOutWaitTasks()`
    3. `TaskExpiryService::handle()`
  - **No event emission at all (2)** — these transition tasks to `failed`/`dead_letter` but never emit `TaskStatusChanged`. Must add `event(TaskStatusChanged::fromTask())`:
    4. `TaskTimeoutService::failTask()`
    5. `ProgressTimeoutService::handleMaxRetriesExceeded()`

## Implementation Plan

1. **Fix all 5 paths that bypass `Event::listen()` handlers**: Ensure every terminal transition emits `event(TaskStatusChanged::fromTask())` via `DB::afterCommit`, consistent with all other paths. This ensures `Event::listen()` handlers (including the new EventBus publisher and the existing `DispatchSystemEventNotification`) fire for ALL terminal transitions.
   - **Migrate `safeBroadcast()` → `event()` (3 paths):** `TaskController::fail()`, `WebhookWaitService::expireTimedOutWaitTasks()`, `TaskExpiryService::handle()`
   - **Add missing `event()` dispatch (2 paths):** `TaskTimeoutService::failTask()`, `ProgressTimeoutService::handleMaxRetriesExceeded()`
2. **Create `PublishTaskEventToEventBus` listener**: Modeled after `DispatchSystemEventNotification::handleTaskStatusChanged()` — filter for terminal statuses, resolve hive, call `EventBus::publish()` with the task event payload.
3. **Register listener in `AppServiceProvider::registerNotificationListeners()`**: Add `Event::listen(TaskStatusChanged::class, [PublishTaskEventToEventBus::class, 'handle'])` alongside the existing registrations.
4. Construct event payload with task metadata (task_id, hive_id, type, target_agent_id, status, result_summary)
5. Write feature tests verifying events appear in `/events/poll` after task transitions across multiple code paths (not just the controller)

## Test Plan

### Feature Tests

- [ ] Completing a task publishes `task.completed` to EventBus
- [ ] Failing a task publishes `task.failed` to EventBus
- [ ] Task expiry publishes `task.expired` to EventBus
- [ ] Dead-lettered task publishes `task.dead_letter` to EventBus
- [ ] Event payload contains required fields (task_id, hive_id, type, target_agent_id, result_summary)
- [ ] Events are hive-scoped (agent in different hive does not receive them)
- [ ] Existing broadcast and notification dispatcher still fire (no regression)

## Validation Checklist

- [ ] All tests pass (`php artisan test`)
- [ ] PSR-12 compliant
- [ ] Activity logging on state changes
- [ ] API responses use `{ data, meta, errors }` envelope
- [ ] No credentials logged in plaintext
