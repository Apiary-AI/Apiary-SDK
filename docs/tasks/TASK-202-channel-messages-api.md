# TASK-202: Channel messages API

**Status:** done
**Branch:** `task/202-channel-messages-api`
**Depends on:** TASK-201
**Blocks:** TASK-204, TASK-205, TASK-209
**Edition:** shared
**Feature doc:** [FEATURE_CHANNELS.md](../features/list-1/FEATURE_CHANNELS.md) §10.2, §9

## Objective

Implement the message CRUD endpoints for channels. Agents and humans post messages (discussion, proposal, vote, decision, context, system, action types), list messages with pagination, and edit within a time window. On first non-initiator message, channel transitions from `open` to `deliberating`.

## Requirements

### Functional

- [ ] FR-1: `POST /api/v1/hives/{hive}/channels/{id}/messages` — post message with content, message_type, metadata, reply_to, mentions
- [ ] FR-2: `GET /api/v1/hives/{hive}/channels/{id}/messages` — list messages paginated, chronological
- [ ] FR-3: `GET /api/v1/hives/{hive}/channels/{id}/messages?since={timestamp}` — messages since timestamp (for polling)
- [ ] FR-4: `PATCH /api/v1/hives/{hive}/channels/{id}/messages/{msg_id}` — edit message (author only, within 5 min)
- [ ] FR-5: Auto-transition channel from `open` to `deliberating` on first non-initiator message
- [ ] FR-6: Increment `channels.message_count` and update `last_message_at` on each message
- [ ] FR-7: Mention detection: if `mentions` contains agent IDs not yet participants, auto-add them with `contributor` role (per §7.2)
- [ ] FR-8: Validate message_type against allowed enum values
- [ ] FR-9: Validate metadata structure per message_type (proposals need options, votes need proposal_ref, etc.)
- [ ] FR-10: Activity log on message create
- [ ] FR-11: Broadcast message event via Reverb for real-time dashboard updates

### Non-Functional

- [ ] NFR-1: PSR-12 compliant
- [ ] NFR-2: Form Request validation
