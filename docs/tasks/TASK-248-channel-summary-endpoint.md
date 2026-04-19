# TASK-248: Channel summary endpoint

**Status:** done
**Branch:** `task/248-channel-summary-endpoint`
**Depends on:** TASK-247
**Edition:** shared
**Feature doc:** [FEATURE_CHANNELS.md](../features/list-1/FEATURE_CHANNELS.md) §7.1

## Objective

Implement a lightweight channel summary endpoint that agents call on-demand when they receive a channel event via `/events/poll`. This provides the enriched context (unread count, mention status, vote status) that TASK-204's polling endpoint would have returned, but without the overhead of polling all channels every cycle.

## Background

With EventBus-driven notifications (TASK-247), agents learn about channel activity through events. But events are intentionally lightweight — they signal *what happened*, not the full state of the channel. When an agent receives a `channel.message.created` or `channel.mention` event, it may want to know: how many unread messages? Am I mentioned? Do I need to vote? The summary endpoint answers these questions on demand.

This is the lightweight alternative to TASK-204's `GET /channels/poll` — instead of polling all channels for summary data every cycle, agents request summaries only for channels with recent activity.

## Requirements

### Functional

- [ ] FR-1: `GET /api/v1/hives/{hive}/channels/{channel}/summary` — returns channel summary for the authenticated agent
- [ ] FR-2: Response includes: `unread_count` (messages since agent's `last_read_at`), `mentioned` (bool — unread message mentions this agent), `needs_vote` (bool — open proposal the agent hasn't voted on), `last_message_at` (timestamp), `last_read_at` (timestamp — the authenticated agent's last read position, used by callers for incremental `get_messages(..., since=)` fetching), `status` (channel status)
- [ ] FR-3: `unread_count` computed from messages created after the participant's `last_read_at`
- [ ] FR-4: `mentioned` is true if any unread message includes the agent in its `mentions` array
- [ ] FR-5: `needs_vote` is true if there's an open proposal the agent hasn't voted on yet
- [ ] FR-6: Returns 403 if the agent is not a participant of the channel
- [ ] FR-7: Returns standard `{ data, meta, errors }` envelope
- [ ] FR-8: `POST /api/v1/hives/{hive}/channels/{channel}/read` — marks channel as read for the authenticated agent by updating `ChannelParticipant.last_read_at` to the current timestamp. Without this write-path, `last_read_at` is never populated and `unread_count` would always return the total message count.

### Non-Functional

- [ ] NFR-1: Response cacheable for 30 seconds with `Cache-Control: private, max-age=30` — `private` is required because the response is per-agent (based on the agent's `last_read_at`) and must not be served from shared/proxy caches. Note: after `POST .../read` the agent should re-fetch the summary to get the updated unread count.
- [ ] NFR-2: Single query or minimal queries — avoid N+1 for unread/mention/vote checks
- [ ] NFR-3: Hive-scoped via `BelongsToHive` — enforced by middleware

## Architecture & Design

### Files to Create / Modify

| Action | Path | Purpose |
|--------|------|---------|
| Modify | `app/Http/Controllers/Api/ChannelController.php` | Add `summary()` and `markAsRead()` actions |
| Modify | `routes/api.php` | Add routes for channel summary and mark-as-read |
| Create | `tests/Feature/ChannelSummaryTest.php` | Test summary and mark-as-read endpoints |

### Key Design Decisions

- Summary is per-agent (uses authenticated agent's `last_read_at` for unread computation)
- Lightweight: no message bodies, no participant list — just counts and booleans
- Cacheable: response uses `Cache-Control: private, max-age=30` — `private` ensures per-agent responses are not served from shared/proxy caches (the summary depends on the authenticated agent's `last_read_at`). After calling `POST .../read`, agents should re-fetch the summary to get the updated unread count.

## API Changes

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET    | `/api/v1/hives/{hive}/channels/{channel}/summary` | Returns channel summary for authenticated agent |
| POST   | `/api/v1/hives/{hive}/channels/{channel}/read`    | Marks channel as read by updating `last_read_at` for the authenticated agent |

### Response Shape

```json
{
  "data": {
    "channel_id": "ch_abc123",
    "unread_count": 3,
    "mentioned": true,
    "needs_vote": false,
    "last_message_at": "2025-02-20T10:05:00Z",
    "last_read_at": "2025-02-20T09:55:00Z",
    "status": "deliberating"
  }
}
```

## Implementation Plan

1. Add `summary()` method to `ChannelController`
2. Query unread count, mention status, and vote status using efficient queries
3. Add `markAsRead()` method to `ChannelController` — updates `ChannelParticipant.last_read_at` to `now()` for the authenticated agent
4. Add routes in `routes/api.php` for both summary and mark-as-read
5. Write feature tests for both endpoints

## Test Plan

### Feature Tests

- [ ] Returns correct unread_count based on agent's last_read_at
- [ ] `mentioned` is true when agent is mentioned in unread messages
- [ ] `needs_vote` is true when open proposal exists without agent's vote
- [ ] Returns 403 for non-participant agents
- [ ] Returns 404 for non-existent channel
- [ ] Response matches expected JSON shape
- [ ] `POST .../read` updates `last_read_at` for the authenticated agent's participant record
- [ ] After marking as read, `unread_count` returns 0 (no new messages since)
- [ ] `POST .../read` returns 403 for non-participant agents
- [ ] `POST .../read` is idempotent (calling twice yields the same result)

## Validation Checklist

- [ ] All tests pass (`php artisan test`)
- [ ] PSR-12 compliant
- [ ] Activity logging on state changes
- [ ] API responses use `{ data, meta, errors }` envelope
- [ ] Form Request validation on all inputs
- [ ] BelongsToHive trait applied where needed
- [ ] No credentials logged in plaintext
