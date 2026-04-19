# TASK-207: Materialization — channel -> tasks

**Status:** done
**Branch:** `task/207-materialization`
**Depends on:** TASK-205
**Blocks:** TASK-221
**Edition:** shared
**Feature doc:** [FEATURE_CHANNELS.md](../features/list-1/FEATURE_CHANNELS.md) §6

## Objective

Implement the bridge from deliberation to execution: when a channel resolves, its outcome materializes into tasks. Supports manual materialization (POST endpoint) and auto-materialization (configured in channel's `on_resolve`).

## Requirements

### Functional

- [x] FR-1: `POST /api/v1/hives/{hive}/channels/{id}/materialize` — create tasks from resolution, accepts array of task templates
- [x] FR-2: `GET /api/v1/hives/{hive}/channels/{id}/tasks` — list tasks created from this channel
- [x] FR-3: Created tasks get `channel_id` set, linking them back to the deliberation
- [x] FR-4: Task payload can include channel context: resolution outcome, summary, message_count
- [x] FR-5: Auto-materialization: on resolution, if `on_resolve.create_tasks` is configured, auto-create tasks
- [x] FR-6: `on_resolve.update_knowledge`: auto-write resolution to knowledge store as a decision entry
- [x] FR-7: Record in `channel_tasks` join table
- [x] FR-8: Summary generation: template-based extraction of proposals + votes + decision into `channel.summary`
- [x] FR-9: Activity log on materialization
- [x] FR-10: Only allow materialization on resolved channels
