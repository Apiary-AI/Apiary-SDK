# TASK-247: Wire channel events into EventBus

**Status:** done
**Branch:** `task/247-channel-events-eventbus`
**Depends on:** TASK-202
**Blocks:** TASK-248
**Edition:** shared
**Feature doc:** [FEATURE_CHANNELS.md](../features/list-1/FEATURE_CHANNELS.md) §7.1

## Objective

Publish channel activity events to the EventBus so that agents are notified of channel activity via `/events/poll`. This replaces the need for the dedicated `/channels/poll` endpoint proposed in TASK-204.

## Background

TASK-204 proposed a `GET /channels/poll` endpoint for agents to discover channel activity. With the EventBus unification (TASK-245), channel notifications flow through the EventBus instead. When messages are posted, agents are mentioned, votes are needed, or channel status changes, events are published to the EventBus. Agents subscribe to the event types they care about and poll via the existing `/events/poll` endpoint.

## Requirements

### Functional

- [ ] FR-1: `channel.message.created` — published when a new message is posted to a channel. Payload: `channel_id`, `channel_title`, `message_id`, `author_type`, `author_id`, `message_type`
- [ ] FR-2: `channel.mention` — published when an agent is @mentioned in a channel message. Payload: `channel_id`, `channel_title`, `message_id`, `mentioned_agent_id`. Published once per mentioned agent.
- [ ] FR-3: `channel.vote.needed` — published when a proposal message is posted that requires an agent's vote. Payload: `channel_id`, `channel_title`, `proposal_message_id`, `voter_agent_id`
- [ ] FR-4: `channel.status.changed` — published when a channel's status transitions. Payload: `channel_id`, `channel_title`, `old_status`, `new_status`
- [ ] FR-5: Events are hive-scoped — only agents within the channel's hive can receive them (consistent with `EventBus::dispatch()` which matches subscriptions by event type + hive scope)
- [ ] FR-6: `channel.mention` events include `mentioned_agent_id` in the payload so consuming agents can filter client-side. Note: the EventBus does not currently support agent-targeted delivery — dispatch and poll are keyed only by event type plus hive/apiary scope. All agents subscribed to `channel.mention` in the hive will receive all mention events; agents must check `mentioned_agent_id == self.agent_id` to determine relevance.
- [ ] FR-7: `channel.vote.needed` events include `voter_agent_id` in the payload for client-side filtering. Same limitation as FR-6: all subscribed agents receive all vote-needed events.
- [ ] FR-8: (Optional enhancement) Add agent-targeted delivery to the EventBus. This would require adding a `target_agent_id` column to the `events` table and filtering in `EventBus::poll()` so that targeted events are only returned to the specified agent. This is a separate concern from this task and should be tracked independently if needed. Without it, `channel.mention` and `channel.vote.needed` are broadcast to all subscribers with payload-based filtering.

### Non-Functional

- [ ] NFR-1: Event publishing must not block the HTTP response — use queue dispatch if needed
- [ ] NFR-2: Reuse the existing `EventBus` service (TASK-053)
- [ ] NFR-3: Event type prefix follows convention: `channel.*`
- [ ] NFR-4: No changes to existing broadcast events (ChannelMessagePosted, etc.) — EventBus events are additive

## Architecture & Design

### Shared Service Layer: `ChannelService`

Channel messages are created through multiple paths in `ChannelService`, not just `postMessage()`:

| Entry Point | Service Method | What It Creates |
|-------------|----------------|-----------------|
| Agent API | `ChannelMessageController::store()` → `postMessage()` | User/agent message |
| Dashboard UI | `ChannelDashboardController::storeMessage()` → `postMessage()` | User/agent message |
| Channel creation | `ChannelService::create()` (lines 127–143) | Initial channel message via `ChannelMessage::create()` |
| Adding participant | `ChannelService::addParticipant()` (lines 338–346) | System "joined" message via `ChannelMessage::create()` |
| Removing participant | `ChannelService::removeParticipant()` (lines 417–425) | System "left" message via `ChannelMessage::create()` |

The API and dashboard paths converge on `postMessage()` (`app/Services/ChannelService.php:204–288`), which handles mention detection, participant auto-add, status transitions, and activity logging. However, `create()`, `addParticipant()`, and `removeParticipant()` create messages directly via `ChannelMessage::create()` — EventBus publishing is needed in those paths too.

Similarly, status transitions happen in multiple places within `ChannelService`:

| Method | Transition |
|--------|------------|
| `postMessage()` (lines 228–245) | stale→deliberating, open→deliberating (auto-transitions on new message) |
| `archive()` (lines 301–318) | →archived |

All EventBus publishing must happen at the service layer — not in controllers — so that every path emits events consistently.

### Files to Create / Modify

| Action | Path | Purpose |
|--------|------|---------|
| Modify | `app/Services/ChannelService.php` | Publish `channel.message.created`, `channel.mention`, and `channel.vote.needed` in `postMessage()`, `create()`, `addParticipant()`, and `removeParticipant()`. Publish `channel.status.changed` in `postMessage()` (auto-transitions) and `archive()`. |
| Create | `tests/Feature/ChannelEventBusTest.php` | Test all channel event types |

### Key Design Decisions

- **Publish message events from the service layer**, not from controllers. `postMessage()` is the convergence point for API and dashboard message creation, but `create()`, `addParticipant()`, and `removeParticipant()` also create messages directly via `ChannelMessage::create()`. All four methods need EventBus publishing. The service layer is the correct publish point because it already handles activity logging, mention detection, and status transitions for all callers.
- **Publish `channel.status.changed` from the service layer.** Status transitions happen in two places: `postMessage()` (auto-transitions: stale→deliberating, open→deliberating) and `archive()` (→archived). The service methods should publish the event directly.
- All channel events (`channel.message.created`, `channel.mention`, `channel.vote.needed`, `channel.status.changed`) are broadcast to all hive subscribers. The EventBus does not support agent-targeted delivery — dispatch and poll are keyed only by event type + hive/apiary scope (see `EventBus::dispatch()` and `EventBus::poll()`). Targeted events include the relevant agent ID in the payload (`mentioned_agent_id`, `voter_agent_id`) for client-side filtering.
- Proposal detection for `channel.vote.needed`: trigger when a message with `message_type=proposal` is created, for each participant with `contributor` or `decider` role who hasn't voted

## Implementation Plan

1. In `ChannelService::postMessage()`, after creating the message and processing mentions (within the existing `DB::transaction` closure):
   - Publish `channel.message.created` event via `EventBus::publish()`
   - For each agent in the message's `mentions` array, publish `channel.mention` event
   - If `message_type=proposal`, identify voting participants and publish `channel.vote.needed` for each
   - If a status auto-transition occurs (stale→deliberating, open→deliberating), publish `channel.status.changed`
   - Note: this covers both the API path (`ChannelMessageController::store()`) and the dashboard path (`ChannelDashboardController::storeMessage()`) since both call `postMessage()`
2. In `ChannelService::create()`, after creating the initial channel message, publish `channel.message.created`
3. In `ChannelService::addParticipant()`, after creating the system "joined" message, publish `channel.message.created`
4. In `ChannelService::removeParticipant()`, after creating the system "left" message, publish `channel.message.created`
5. In `ChannelService::archive()`, after transitioning to archived status, publish `channel.status.changed`
6. Write feature tests for each event type, including tests for all message creation paths and all status transition paths

## Test Plan

### Feature Tests

- [ ] Posting a message via `postMessage()` publishes `channel.message.created` to EventBus
- [ ] Creating a channel (`create()`) publishes `channel.message.created` for the initial message
- [ ] Adding a participant (`addParticipant()`) publishes `channel.message.created` for the system "joined" message
- [ ] Removing a participant (`removeParticipant()`) publishes `channel.message.created` for the system "left" message
- [ ] Mentioning an agent publishes `channel.mention` targeted to that agent
- [ ] Posting a proposal publishes `channel.vote.needed` for each eligible voter
- [ ] Auto-transition in `postMessage()` (stale→deliberating, open→deliberating) publishes `channel.status.changed`
- [ ] Archiving a channel (`archive()`) publishes `channel.status.changed` with new_status=archived
- [ ] Events are hive-scoped
- [ ] Targeted events (mention, vote.needed) include correct agent ID in payload (`mentioned_agent_id`, `voter_agent_id`) for client-side filtering
- [ ] Existing broadcast events still fire (no regression)

## Validation Checklist

- [ ] All tests pass (`php artisan test`)
- [ ] PSR-12 compliant
- [ ] Activity logging on state changes
- [ ] API responses use `{ data, meta, errors }` envelope
- [ ] No credentials logged in plaintext
