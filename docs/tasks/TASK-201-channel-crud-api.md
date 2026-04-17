# TASK-201: Channel CRUD API

**Status:** done
**Branch:** `task/201-channel-crud-api`
**Depends on:** TASK-200
**Blocks:** TASK-202, TASK-203, TASK-204, TASK-209
**Edition:** shared
**Feature doc:** [FEATURE_CHANNELS.md](../features/list-1/FEATURE_CHANNELS.md) §10.1, §10.7

## Objective

Implement the core Channel CRUD API endpoints. Agents and the dashboard can create, list, get, update, and archive channels within a hive.

## Requirements

### Functional

- [ ] FR-1: `POST /api/v1/hives/{hive}/channels` — create channel with title, channel_type, topic, participants, resolution_policy, linked_refs, on_resolve, stale_after, initial_message
- [ ] FR-2: `GET /api/v1/hives/{hive}/channels` — list channels in hive, filterable by status, channel_type, paginated
- [ ] FR-3: `GET /api/v1/hives/{hive}/channels/{id}` — get channel with summary, participant list, message_count
- [ ] FR-4: `PATCH /api/v1/hives/{hive}/channels/{id}` — update settings (title, resolution_policy, stale_after, on_resolve)
- [ ] FR-5: `DELETE /api/v1/hives/{hive}/channels/{id}` — archive channel (soft: set status=archived)
- [ ] FR-6: On create, auto-add the creator as participant with `initiator` role
- [ ] FR-7: `auto_invite` support: invite agents by capability match
- [ ] FR-8: `initial_message` support: create first message atomically with channel
- [ ] FR-9: Form Request validation for all inputs
- [ ] FR-10: Hive-scoped via BelongsToHive global scope
- [ ] FR-11: Activity log on create, update, archive
- [ ] FR-12: Consistent JSON envelope responses

### Non-Functional

- [ ] NFR-1: ChannelController follows thin-controller pattern (delegate to ChannelService)
- [ ] NFR-2: PSR-12 compliant
