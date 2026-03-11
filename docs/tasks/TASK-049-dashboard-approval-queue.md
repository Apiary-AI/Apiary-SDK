# TASK-049: Dashboard — Approval Queue

**Phase:** 2 — Service Proxy & Security
**Status:** in progress
**Depends On:** TASK-046 (Approval API), TASK-022 (Inertia.js + React + layout)
**Branch:** `task/049-dashboard-approval-queue`

---

## Objective

Create a dashboard page that displays pending (and historical) approval requests with the ability to approve or deny them directly from the UI. Integrates with the existing ApprovalRequest model, ApprovalManager service, and ApprovalStatusChanged WebSocket event from TASK-045/046/047.

## Requirements

### Dashboard Controller

Create `ApprovalDashboardController` with:

- `index(Request)` — renders `Approvals` Inertia page
- Filters: status (pending/approved/denied/expired), search (path, agent, service)
- Sorting: created_at (default desc), status, request_method
- Pagination: 20 per page
- Status breakdown: grouped counts for summary bar
- Hive-scoped via `resolveCurrentHiveId()` helper
- Input sanitization (reject non-scalar query values)
- Eager loading: agent, service relationships

### Approve/Deny Actions

- `POST /dashboard/approvals/{approval}/approve` — approve via ApprovalManager
- `POST /dashboard/approvals/{approval}/deny` — deny with optional reason via ApprovalManager
- Proper error handling for LogicException (409 Conflict equivalent)
- Redirect back with flash messages

### React Page (Approvals.jsx)

- Page header: "Approval Queue"
- Status breakdown bar (color-coded: pending=amber, approved=emerald, denied=red, expired=neutral)
- Filter bar: status select, search input, sort dropdown
- Main table: status badge, method + path, service, agent, reason, decided_by, expires_at, created_at
- Action buttons on pending rows: Approve (green) and Deny (red with optional reason)
- Pagination
- Live updates via `useHiveChannel` listening for `approval.status_changed`
- Live banner showing new/updated approvals with refresh button
- Empty state with ShieldCheck icon

### Navigation

- Add "Approvals" nav item to AppLayout sidebar

### Routes

- `GET /dashboard/approvals` → ApprovalDashboardController@index
- `POST /dashboard/approvals/{approval}/approve` → ApprovalDashboardController@approve
- `POST /dashboard/approvals/{approval}/deny` → ApprovalDashboardController@deny

## Test Plan

1. Page returns 200
2. Page renders Inertia `Approvals` component
3. Props include entries, statusBreakdown, filters
4. Entry data shape (all expected fields)
5. Filter by status
6. Search by path
7. Search by agent name
8. Default sort is newest first
9. Sort by status
10. Pagination (20 per page)
11. Empty state
12. Hive scoping
13. Status breakdown scoped to hive
14. Invalid sort falls back to created_at
15. Array params are sanitized
16. Approve action transitions pending → approved
17. Deny action transitions pending → denied
18. Approve/deny non-pending returns error
19. Entry includes agent_name and service_name

## Design Decisions

- Follows ProxyDashboardController pattern exactly for consistency
- Dashboard approve/deny uses ApprovalManager service (same as API) for atomic transitions + activity logging + broadcasting
- decided_by set to authenticated user's name (dashboard user, not agent)
- Real-time updates via existing ApprovalStatusChanged event on hive.{hiveId} channel
