# TASK-058: Webhook Route Evaluator + Async Processing

## Status
In Progress

## Depends On
- TASK-057 (Webhook receiver controller) — done (PR #71)
- TASK-008 (Task migration + model) — done (PR #8)

## Downstream
- TASK-059 (Dashboard: webhook monitor) — depends on 057, 022

## Requirements

1. **WebhookRouteEvaluator service** — Extract route matching and field-filter evaluation from WebhookController into a dedicated `App\Services\WebhookRouteEvaluator` service. Evaluates all active routes for a given apiary+service+event_type, applies field filters, and returns an `EvaluationResult` DTO with matched routes and diagnostics.

2. **EvaluationResult DTO** — Immutable result object from the evaluator containing: routes evaluated count, matched routes collection, per-route diagnostics (filter results, match/no-match reason).

3. **Action execution** — The evaluator also provides an `executeActions()` method that, for each matched route, creates tasks or publishes events in the correct hive context. Uses `withRouteContext()` for tenant-safe execution.

4. **ProcessWebhook job** — Queued job (`App\Jobs\ProcessWebhook`) that runs the evaluator + action execution asynchronously. Uses the `apiary-webhooks` queue. Serializes only the service_connection_id, event_type, and payload (no Eloquent models on the wire). Includes retry logic and fail-closed behavior.

5. **Controller refactor** — WebhookController dispatches ProcessWebhook after validation + parsing instead of evaluating routes inline. Returns 200 immediately with event_type and processing status. Signature validation and payload parsing remain synchronous (must reject invalid webhooks before accepting).

6. **Activity logging** — `webhook.received` logged synchronously in the controller (before dispatch). `webhook.route_matched` logged per-route inside the job. `webhook.processing_failed` logged if the job fails.

7. **Tenant safety** — Job runs outside HTTP request context. Must explicitly bind apiary/hive context per route using `withRouteContext()`. All queries use `withoutGlobalScopes()` + manual WHERE clauses.

8. **Fail-closed** — Job failure → failed_jobs table (Laravel default). Evaluator errors caught and logged per-route; one route failure doesn't block other routes. Missing service connection in job → logged and abandoned (no retry).

## New Files

- `app/Services/WebhookRouteEvaluator.php` — Route evaluation service
- `app/Services/EvaluationResult.php` — DTO for evaluation results
- `app/Jobs/ProcessWebhook.php` — Async queue job

## Modified Files

- `app/Http/Controllers/Api/WebhookController.php` — Dispatch to queue

## Response Format (updated)

```json
{
  "data": {
    "event_type": "push",
    "status": "accepted",
    "service_id": "..."
  },
  "meta": {},
  "errors": null
}
```

## Test Plan

### Unit Tests (WebhookRouteEvaluatorTest)
- Evaluates matching routes for event_type + field filters
- Returns correct routesEvaluated and matchedRoutes counts
- Inactive routes are excluded
- Routes from different apiaries are excluded (tenant isolation)
- Routes for different services are excluded
- Routes for different event types are excluded
- Empty field filters = match all
- Field filter mismatch = no match
- EvaluationResult contains correct diagnostics
- executeActions creates tasks in correct hive
- executeActions publishes events in correct hive
- executeActions binds hive context per route (tenant safety)
- executeActions with malformed action_config skips route
- executeActions with unknown action_type skips route

### Unit Tests (ProcessWebhookTest)
- Job dispatches on correct queue (apiary-webhooks)
- Job handles successful evaluation + action execution
- Job handles missing service connection gracefully
- Job handles evaluator exceptions gracefully
- Job logs activity on processing

### Feature Tests (WebhookControllerTest updates)
- Valid webhook dispatches ProcessWebhook job
- Controller returns 200 with event_type and status=accepted
- Signature validation still synchronous (401 on invalid)
- Parse errors still synchronous (400 on parse failure)
- Service resolution still synchronous (404 on missing)
- Slack url_verification still handled synchronously
- Processing the job creates tasks (end-to-end with Queue::fake disabled)
