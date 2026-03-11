# TASK-054: Event API (publish/subscribe/poll endpoints)

**Status:** In Progress
**Branch:** `task/054-event-api`
**Depends On:** 053 (Event bus service), 012 (Agent authentication), 013 (Permission middleware)

## Requirements

Create the REST API endpoints that expose the EventBus service to agents. Agents need to publish events, manage subscriptions, and poll for events matching their subscriptions.

### Endpoints

1. **POST /api/v1/hives/{hive}/events** — Publish an event
   - Permission: `events.publish`
   - Body: `{ type, payload? }`
   - Cross-hive events (`apiary.*` prefix) allowed, sets `hive_id=null`
   - Source agent set automatically from authenticated agent
   - Activity logging via EventBus service

2. **GET /api/v1/hives/{hive}/events/poll** — Poll events for the authenticated agent
   - Permission: `events.poll`
   - Query params: `since?` (ISO 8601 timestamp), `last_event_id?` (cursor), `limit?` (1-100)
   - Returns events matching agent's subscriptions (hive + cross-hive)
   - Sorted by `seq` (insertion order)

3. **POST /api/v1/agents/subscriptions** — Subscribe to an event type
   - Auth: `auth:sanctum-agent` (no specific permission beyond auth)
   - Body: `{ event_type, scope? }` (scope defaults to `hive`)
   - Idempotent — duplicate subscription returns existing record

4. **DELETE /api/v1/agents/subscriptions/{eventType}** — Unsubscribe from an event type
   - Auth: `auth:sanctum-agent`
   - Returns 204 on success, 404 if subscription not found

5. **PUT /api/v1/agents/subscriptions** — Replace all subscriptions
   - Auth: `auth:sanctum-agent`
   - Body: `{ subscriptions: [{ event_type, scope? }] }`
   - Atomic replace — deletes all existing, creates new set

6. **GET /api/v1/agents/subscriptions** — List agent's subscriptions
   - Auth: `auth:sanctum-agent`
   - Returns all subscriptions for the authenticated agent

### Key Design Decisions

- Publish and poll are hive-scoped routes (under `/hives/{hive}`) with same resolveHive pattern as Knowledge/Task controllers
- Subscribe/unsubscribe are agent-scoped (under `/agents/`) — subscriptions belong to the agent, not a hive
- EventBus service handles all business logic; controller is thin
- Cross-hive publish: agent can publish `apiary.*` events from any hive in their apiary
- Form Request validation on all POST/PUT inputs
- Standard API envelope responses

## Test Plan

### Publish
- Publish hive-scoped event returns 201 with event data
- Publish cross-hive event (apiary.* prefix) succeeds
- Publish without auth returns 401
- Publish without events.publish permission returns 403
- Publish to non-existent hive returns 404
- Publish to hive in different apiary returns 403
- Publish with missing type returns 422
- Publish with invalid type (too long) returns 422
- Activity log created on successful publish

### Poll
- Poll returns matching events for agent's subscriptions
- Poll with since parameter filters by timestamp
- Poll with last_event_id uses seq-based cursor
- Poll without auth returns 401
- Poll without events.poll permission returns 403
- Poll returns empty array when no subscriptions
- Poll respects limit parameter
- Poll returns events in insertion order (by seq)

### Subscribe
- Subscribe creates subscription and returns 201
- Subscribe is idempotent — duplicate returns existing (200)
- Subscribe with invalid scope returns 422
- Subscribe without auth returns 401
- List subscriptions returns all agent's subscriptions

### Unsubscribe
- Unsubscribe returns 204 on success
- Unsubscribe non-existent subscription returns 404

### Replace Subscriptions
- Replace creates new set and deletes old
- Replace with empty array clears all subscriptions
- Replace with invalid scope returns 422

### Cross-hive
- Agent in different hive (same apiary) can poll cross-hive events
- Agent from different apiary cannot access hive

## Validation Checklist

- [ ] EventController implements all six endpoints
- [ ] Form Request validation on publish, subscribe, replace
- [ ] Permission middleware on publish (events.publish) and poll (events.poll)
- [ ] Hive resolution + access control on publish/poll
- [ ] API envelope format on all responses
- [ ] Activity logging on event publication (handled by EventBus)
- [ ] All tests pass
- [ ] PSR-12 compliant (Pint)
