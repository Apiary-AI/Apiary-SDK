# TASK-057: Webhook Receiver Controller

## Status
In Progress

## Depends On
- TASK-055 (Webhook routes migration + model) — done (PR #69)
- TASK-056 (Webhook field filters) — done (PR #70)

## Downstream
- TASK-058 (Webhook route evaluator + async processing) — depends on 057, 008
- TASK-059 (Dashboard: webhook monitor) — depends on 057, 022

## Requirements

1. **WebhookController** — Public API controller at `POST /api/v1/webhooks/{service}` that receives inbound webhooks from external services (GitHub, Slack, custom). No agent auth required.

2. **Connector resolution** — Resolve the `ConnectorInterface` implementation from the `ServiceConnection` → `Connector` (via `connector_id`) → `class_path` to instantiate the correct connector.

3. **Signature validation** — Delegate to `ConnectorInterface::validateWebhook()`. Fail-closed: invalid/missing signature → 401 Unauthorized.

4. **Payload parsing** — Delegate to `ConnectorInterface::parseWebhook()` to extract normalized `{event, payload}`.

5. **Route matching** — Query active `WebhookRoute`s for the service connection's apiary, filtered by `event_type`, ordered by priority. For each route, evaluate `matchesPayload()` against the parsed payload.

6. **Action execution** — For each matching route:
   - `create_task`: Create a `Task` in the route's hive with type/priority/payload from `action_config`
   - `publish_event`: Publish an `Event` via `EventBus` in the route's hive

7. **Activity logging** — Log `webhook.received` at the apiary level with service/event details. Log per-route `webhook.route_matched` with action results.

8. **Response** — Return 200 OK with summary: event type, routes matched, actions taken. Return 401 for signature failures. Return 404 for unknown service.

9. **Tenant safety** — Service connections are apiary-scoped. Routes are hive-scoped. Tasks/events are created in the route's hive. All queries use explicit apiary/hive scoping (withoutGlobalScopes + manual WHERE).

10. **Fail-closed** — Missing connector, inactive service, parse errors → reject. Never silently accept an invalid webhook.

## Route

```
POST /api/v1/webhooks/{service}   — public, no auth middleware
```

Where `{service}` is the `ServiceConnection` ID.

## Response Format

```json
{
  "data": {
    "event_type": "push",
    "routes_evaluated": 3,
    "routes_matched": 2,
    "actions": [
      {"route_id": "...", "action": "create_task", "task_id": "..."},
      {"route_id": "...", "action": "publish_event", "event_id": "..."}
    ]
  },
  "meta": {},
  "errors": null
}
```

## Test Plan

### Feature Tests (WebhookControllerTest)
- Valid GitHub webhook with matching route → task created, 200 response
- Valid Slack webhook with matching route → task created, 200 response
- Valid webhook with publish_event action → event published, 200 response
- Valid webhook with multiple matching routes → multiple actions, 200 response
- Valid webhook with no matching routes → 200 with empty actions
- Invalid signature → 401 Unauthorized
- Unknown service connection → 404
- Inactive service connection → 404
- Service connection with no connector → 404
- Connector that doesn't support webhooks → 400
- Inactive webhook routes are skipped
- Route event_type mismatch → not matched
- Route field filter mismatch → not matched
- Cross-hive: routes in different hives all create tasks in their own hive
- Activity log entry created for webhook.received
- Activity log entry created for each webhook.route_matched
- Malformed action_config → fail-closed, skip route
- Tenant isolation: service from apiary A can't match routes from apiary B
