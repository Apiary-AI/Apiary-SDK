# TASK-204: Channel polling API

> **Superseded by [TASK-245](TASK-245-eventbus-unification-plan.md).** Channel notifications now flow through the EventBus rather than a dedicated polling endpoint.

**Status:** superseded
**Branch:** `task/204-channel-polling-api`
**Depends on:** TASK-202
**Blocks:** TASK-212
**Edition:** shared
**Feature doc:** [FEATURE_CHANNELS.md](../features/list-1/FEATURE_CHANNELS.md) §7.1, §10.6

## Objective

Implement the agent polling endpoint for channel activity. Agents poll alongside tasks to discover channels with unread messages, pending mentions, or votes needed.

## Requirements

### Functional

- [ ] FR-1: `GET /api/v1/hives/{hive}/channels/poll` — returns channels where the authenticated agent is a participant and has activity
- [ ] FR-2: Each channel in response includes: channel_id, unread_count, last_message_at, mentioned (bool), status, needs_vote (bool)
- [ ] FR-3: `unread_count` computed from messages created after participant's `last_read_at`
- [ ] FR-4: `mentioned` is true if any unread message includes the agent in its `mentions` array
- [ ] FR-5: `needs_vote` is true if there's an open proposal the agent hasn't voted on yet
- [ ] FR-6: `next_poll_ms` in response for adaptive polling interval
- [ ] FR-7: Update participant's `last_read_at` when agent reads messages (via GET messages endpoint)
- [ ] FR-8: Respect `mention_policy`: if `mention_only`, only return channel when `mentioned=true`
