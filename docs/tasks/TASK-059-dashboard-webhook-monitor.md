# TASK-059: Dashboard — Webhook Monitor

## Status
In Progress

## Depends On
- TASK-057 (Webhook receiver controller) — done (PR #71)
- TASK-022 (Install Inertia.js + React + layout) — done (PR #24)

## Downstream
- None (leaf task in Phase 3)

## Requirements

1. **WebhookDashboardController** — New `App\Http\Controllers\Dashboard\WebhookDashboardController` following the same pattern as ActivityDashboardController and ProxyDashboardController. Single `index()` method returning Inertia response with paginated webhook activity entries, event-type breakdown, and filters.

2. **Data source** — Webhook events are tracked via `activity_log` entries with `webhook.*` actions (`webhook.received`, `webhook.route_matched`, `webhook.processed`). The controller queries ActivityLog filtered to `webhook.%` actions, scoped to the current hive.

3. **Route configuration list** — Also includes a list of configured WebhookRoute records for the current hive (name, event_type, action_type, is_active, priority, service name).

4. **Filtering** — Filter by webhook action type (received/route_matched/processed), search across action, route name (via details JSON), and event type. Sort by created_at (default, desc) or action (asc).

5. **Pagination** — 20 entries per page with query string preservation.

6. **Event-type breakdown** — Breakdown bar showing counts per webhook action (webhook.received, webhook.route_matched, webhook.processed).

7. **Real-time updates** — Listen for `webhook.processed` events via useHiveChannel hook. Show live update banner with refresh button.

8. **Tenant safety** — Fail closed if hive context is missing (return empty data). Hive scoping on both ActivityLog queries and WebhookRoute queries.

9. **Navigation** — Add "Webhooks" entry to AppLayout sidebar navigation between "Proxy" and "Approvals".

10. **Route registration** — Register `GET /dashboard/webhooks` in web.php.

## New Files

- `app/Http/Controllers/Dashboard/WebhookDashboardController.php` — Dashboard controller
- `resources/js/Pages/Webhooks.jsx` — React page component
- `tests/Feature/Dashboard/WebhookDashboardPageTest.php` — Feature tests

## Modified Files

- `routes/web.php` — Add webhook dashboard route
- `resources/js/Layouts/AppLayout.jsx` — Add nav entry

## Props Passed to Inertia

```json
{
  "entries": {
    "data": [
      {
        "id": "...",
        "action": "webhook.received",
        "event_type": "push",
        "service_name": "GitHub",
        "route_name": "Deploy on push",
        "routes_matched": 2,
        "details": {},
        "created_at": "2026-03-02T..."
      }
    ],
    "current_page": 1,
    "last_page": 1,
    "per_page": 20,
    "total": 0,
    "next_page_url": null,
    "prev_page_url": null
  },
  "actionBreakdown": {
    "webhook.received": 10,
    "webhook.route_matched": 8,
    "webhook.processed": 5
  },
  "routes": [
    {
      "id": "...",
      "name": "Deploy on push",
      "event_type": "push",
      "action_type": "create_task",
      "is_active": true,
      "priority": 0,
      "service_name": "GitHub"
    }
  ],
  "filters": {
    "action": null,
    "search": null,
    "sort": "created_at"
  }
}
```

## Test Plan

### Feature Tests (WebhookDashboardPageTest)

**Basic rendering:**
- Page returns 200
- Renders Webhooks Inertia component

**Props structure:**
- Includes entries prop with pagination fields
- Includes actionBreakdown prop
- Includes routes prop
- Includes filters prop with action, search, sort

**Entry data shape:**
- Entry includes id, action, details, created_at
- Entry extracts event_type from details
- Entry extracts service info from details

**Filtering:**
- Filters by webhook action type
- Searches by action
- Only shows webhook.* actions (not task.created, agent.online, etc.)

**Sorting:**
- Default sort is newest first (created_at desc)
- Sorts by action ascending

**Pagination:**
- Paginates to 20 per page

**Empty state:**
- Returns empty entries when none exist

**Input sanitization:**
- Invalid sort falls back to created_at
- Array search param is ignored
- Array action param is ignored

**Hive scoping:**
- Entries scoped to current hive
- Breakdown scoped to current hive
- Routes scoped to current hive

**Tenant isolation (cloud mode):**
- Cloud mode list excludes other apiary entries
- Cloud mode routes exclude other apiary routes

**Routes list:**
- Includes active routes for current hive
- Route data includes service name
