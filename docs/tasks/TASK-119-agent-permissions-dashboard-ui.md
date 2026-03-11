# TASK-119: Agent Permissions Management in Dashboard UI

**Status:** In Progress
**Branch:** `task/119-agent-permissions-dashboard-ui`
**Depends On:** TASK-024 (Agents dashboard), TASK-116 (Dashboard auth)

## Requirements

Add a permissions editor to the dashboard agent detail page so admins can
view and update the permissions granted to each agent.

### Functional

1. Agent detail page (`Agents/Show`) displays current permissions for the agent.
2. Admin can add new permissions from a catalog of known valid permissions.
3. Admin can remove existing permissions.
4. Unknown/invalid permissions are rejected (fail-closed).
5. Permission updates are validated server-side against an allowed catalog.
6. All permission changes are logged to the activity log.
7. Tenant isolation: agents from other hives cannot be modified (existing global scopes).

### Non-Functional

- Follow existing dashboard controller patterns (JSON response for mutations).
- Use existing UI components (Card, Badge, Button, Select, Dialog).
- PSR-12 compliant.
- Form Request validation on all inputs.

## Implementation Plan

### Backend

1. **`UpdateAgentPermissionsRequest`** — Form Request with permission catalog validation.
2. **`AgentDashboardController::updatePermissions()`** — Sync endpoint: accepts `{ permissions: string[] }`, diffs against current, grants/revokes as needed.
3. **Route:** `PUT /dashboard/agents/{agent}/permissions`
4. **Activity logging:** Log `agent.permissions.updated` with before/after diff.
5. **Show method update:** Include `permissions` in agent detail Inertia props.

### Frontend

1. **Permissions card** on `Agents/Show.jsx`:
   - Display current permissions as removable badges.
   - Select dropdown to add from catalog.
   - Save button to submit changes.
   - Optimistic UI with error handling.

### Permission Catalog

Known valid base permissions (category:action format):
- `admin:*`
- `tasks:create`, `tasks:claim`, `tasks:manage`, `tasks:*`
- `knowledge:read`, `knowledge:write`, `knowledge:*`
- `services:github`, `services:slack`, `services:*`
- `events:publish`, `events:subscribe`, `events:*`
- `webhooks:manage`, `webhooks:*`

## Test Plan

1. **Successful update** — Grant and revoke permissions, verify DB state.
2. **Invalid permission rejection** — Submit unknown permission, expect 422.
3. **Unauthorized rejection** — Unauthenticated request returns 401.
4. **Tenant isolation** — Cannot update permissions for agent in different hive (cloud mode).
5. **Activity logging** — Verify activity_log entry on permission change.
6. **Show page includes permissions** — Verify Inertia props include permissions array.
7. **Empty permissions** — Submit empty array clears all permissions.

## Files Changed

- `app/Http/Controllers/Dashboard/AgentDashboardController.php`
- `app/Http/Requests/UpdateAgentPermissionsRequest.php` (new)
- `resources/js/Pages/Agents/Show.jsx`
- `routes/web.php`
- `tests/Feature/Dashboard/AgentPermissionsDashboardTest.php` (new)
- `docs/tasks/TASK-119-agent-permissions-dashboard-ui.md` (new)
- `TASKS.md`
