# TASK-070: Dashboard Hive Selector

## Status
In Progress

## Description
Add a hive selector dropdown to the dashboard sidebar so users in Cloud mode
can switch between hives. The selected hive is persisted in the session and
re-scopes all dashboard data. In CE mode (single hive) the selector is hidden.

## Depends On
- TASK-062 (Hive management API) — provides hive CRUD
- TASK-022 (Inertia + React layout) — provides AppLayout and Inertia plumbing

## Requirements

### Backend
1. Add `POST /dashboard/switch-hive` route (authenticated, web middleware)
2. Validate that the requested hive belongs to the current apiary and is active
3. Persist selected hive ID in session (`apiary.current_hive_id`)
4. Bind selected hive to container so all downstream code resolves correctly
5. In CE mode, reject switch requests (single hive, no switching)
6. Share `hives` list prop via Inertia to all dashboard pages
7. Validate session hive on every request; clear if no longer valid

### Frontend
1. Create `HiveSelector` component (dropdown in sidebar)
2. Show current hive name, list available hives on click
3. On selection, POST to switch endpoint via Inertia router
4. Hide selector entirely in CE mode (empty hives list)

### Tenant Safety
1. Fail-closed: invalid/missing hive context returns empty data
2. Cross-apiary hive IDs rejected with 403
3. Inactive hives rejected with 403
4. Session values validated on every request

## Test Plan
1. CE mode: switch endpoint returns 403
2. Cloud mode: valid switch persists to session and redirects
3. Cloud mode: cross-apiary hive returns 403
4. Cloud mode: inactive hive returns 403
5. Cloud mode: nonexistent hive returns 403
6. Cloud mode: `hives` prop shared with correct hives
7. Cloud mode: session persistence across requests
8. CE mode: `hives` prop is empty array

## Files
- `app/Http/Controllers/Dashboard/DashboardController.php` (modify)
- `app/Http/Middleware/HandleInertiaRequests.php` (modify)
- `routes/web.php` (modify)
- `resources/js/Components/HiveSelector.jsx` (create)
- `resources/js/Layouts/AppLayout.jsx` (modify)
- `tests/Feature/Dashboard/HiveSelectorTest.php` (create)
