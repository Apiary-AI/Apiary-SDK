# TASK-060: Dashboard — Webhook Route Builder

## Status
In Progress

## Depends On
- TASK-055 (Webhook routes migration + model) — done (PR #69)
- TASK-056 (Webhook field filters) — done (PR #70)
- TASK-022 (Install Inertia.js + React + layout) — done (PR #24)

## Downstream
- None (leaf task in Phase 3)

## Requirements

1. **WebhookRouteDashboardController** — CRUD controller for webhook routes following the PolicyDashboardController pattern. Methods: `create()`, `store()`, `edit()`, `update()`, `destroy()`, `toggle()`.

2. **WebhookRouteForm.jsx** — React form page for creating/editing webhook routes with:
   - Name, service, event type, action type selection
   - Priority input
   - Active/inactive toggle
   - Dynamic field filter builder (add/remove filters with field, operator, value inputs)
   - Action config editor (task_type for create_task, event_name for publish_event)

3. **Route registration** — Register CRUD routes in web.php under `/dashboard/webhook-routes/*`.

4. **Webhooks.jsx update** — Add "New Route" button and edit/delete/toggle actions on the configured routes list.

5. **Validation** — Server-side validation with scoped exists rules for service_id (apiary-scoped), FieldFilterRule for field_filters, action_type from WebhookRoute::ACTION_TYPES.

6. **Tenant safety** — Fail closed if hive/apiary context is missing. Hive-scope all queries. Verify route belongs to current hive on edit/update/destroy/toggle.

7. **Activity logging** — Log webhook_route.created, webhook_route.updated, webhook_route.deleted, webhook_route.toggled actions.

8. **Duplicate prevention** — Prevent duplicate routes with same name+service+event_type in the same hive.

## New Files

- `app/Http/Controllers/Dashboard/WebhookRouteDashboardController.php`
- `resources/js/Pages/WebhookRouteForm.jsx`
- `tests/Feature/Dashboard/WebhookRouteDashboardTest.php`

## Modified Files

- `routes/web.php` — Add webhook route CRUD routes
- `resources/js/Pages/Webhooks.jsx` — Add route management actions

## Test Plan

### Basic rendering
- Create page returns 200
- Create page renders WebhookRouteForm component with null route

### Store (create)
- Creates route with valid data
- Rejects missing name
- Rejects missing service_id
- Rejects missing event_type
- Rejects missing action_type
- Rejects invalid action_type
- Rejects invalid field_filters (via FieldFilterRule)
- Rejects duplicate name+service+event_type in same hive
- Rejects service from another apiary

### Edit page
- Returns 200 with route data
- Returns 404 for route in another hive

### Update
- Modifies route fields
- Rejects update to duplicate name+service+event_type
- Returns error for route in another hive

### Delete
- Removes route
- Returns error for route in another hive

### Toggle
- Flips active to inactive
- Flips inactive to active
- Returns error for route in another hive

### Fail-closed
- Store fails closed when hive context missing
- Toggle fails closed when hive context missing
- Destroy fails closed when hive context missing
- Store fails closed when apiary context missing
