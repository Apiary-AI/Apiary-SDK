# TASK-245: EventBus unification plan

**Status:** done
**Branch:** `task/245-eventbus-unification-plan`
**Depends on:** —
**Blocks:** TASK-246, TASK-247, TASK-248, TASK-249, TASK-250
**Edition:** shared
**Feature doc:** [FEATURE_CHANNELS.md](../features/list-1/FEATURE_CHANNELS.md) §7.1

## Objective

Unify agent notifications through the EventBus. Task lifecycle events and channel activity flow through `/events/poll` instead of dedicated polling endpoints. The agent poll loop becomes two calls: `/tasks/poll` (claim work) + `/events/poll` (notifications for everything else).

## Background

Currently there are three separate notification systems:

1. **Task polling** (`/tasks/poll`) — agents claim work from the task queue
2. **EventBus** (`/events/poll`) — agent-to-agent pub/sub, fully built (Phase 3, tasks 051-054) but unused by the SDK
3. **Notification webhooks** — push notifications to external services (Slack, email, etc.)

TASK-204 proposed a fourth polling endpoint (`/channels/poll`) for channel activity. This creates fragmentation — agents would need to poll three separate endpoints. Instead, channel notifications (and task lifecycle events) should flow through the EventBus, which is already built and supports subscriptions, cursor-based polling, and adaptive intervals.

**Supersedes:** [TASK-204](TASK-204-channel-polling-api.md) (Channel polling API)

## Plan

### Sub-tasks

| #   | Task                                                                                          | Depends On | Description |
|-----|-----------------------------------------------------------------------------------------------|------------|-------------|
| 246 | [Wire task events into EventBus](TASK-246-task-events-eventbus.md)                            | —          | Publish task lifecycle events to EventBus |
| 247 | [Wire channel events into EventBus](TASK-247-channel-events-eventbus.md)                      | TASK-202   | Publish channel activity events to EventBus |
| 248 | [Channel summary endpoint](TASK-248-channel-summary-endpoint.md)                              | TASK-247   | On-demand channel enrichment API |
| 249 | [Python SDK — event polling client](TASK-249-sdk-event-polling.md)                            | TASK-246   | Add event polling to the Python SDK |
| 250 | [Events dashboard page](TASK-250-events-dashboard.md)                                         | —          | Dashboard UI for events and subscriptions |

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Agent Poll Loop                         │
│                                                             │
│   ┌──────────────┐          ┌──────────────┐               │
│   │ /tasks/poll   │          │ /events/poll  │               │
│   │ (claim work)  │          │ (notifications)│               │
│   └──────────────┘          └──────┬───────┘               │
│                                     │                       │
│                    ┌────────────────┼────────────────┐      │
│                    │                │                │      │
│              task.completed   channel.message   channel.    │
│              task.failed      .created          mention     │
│              task.expired     channel.vote      channel.    │
│              task.dead_letter .needed           status.     │
│                                                 changed    │
└─────────────────────────────────────────────────────────────┘
```

Existing systems remain unchanged:
- **Task polling** (`/tasks/poll`) — still used for claiming work (atomic UPDATE...WHERE)
- **Notification webhooks** — still used for pushing to external services
- **Dashboard WebSocket** — still used for real-time dashboard updates

The EventBus becomes the unified channel for agent-to-agent notifications, replacing the need for dedicated polling endpoints per feature area.
