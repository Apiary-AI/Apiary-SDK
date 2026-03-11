# TASK-050 — Dashboard: Policy Editor

**Status:** In Progress
**Branch:** `task/050-dashboard-policy-editor`
**Depends On:** TASK-044 (Policy engine service), TASK-022 (Inertia.js + React)

## Objective

Build a dashboard page for managing action policies (CRUD). Operators can
list, create, edit, toggle, and delete per-agent per-service firewall rules
directly from the web UI.

## Requirements

1. **List view** — paginated table of action policies with filters (agent, service, active/inactive) and search.
2. **Create** — form to create a new policy: select agent, select service, define rules (allow/deny/require_approval with method+path pairs), set active state.
3. **Edit** — form pre-populated with existing policy; update rules, toggle active.
4. **Delete** — soft-confirm deletion of a policy.
5. **Toggle** — quick activate/deactivate from the list view.
6. **Hive scoping** — all queries scoped to the current hive (fail-closed pattern).
7. **Cache invalidation** — flush PolicyEngine cache after create/update/delete.
8. **Activity logging** — log policy create/update/delete events.
9. **Validation** — validate rules JSONB structure (each rule must have valid action, method, path).

## Files

| File | Purpose |
|------|---------|
| `app/Http/Controllers/Dashboard/PolicyDashboardController.php` | Dashboard controller (index, create, store, edit, update, destroy, toggle) |
| `resources/js/Pages/Policies.jsx` | React page: list + inline create/edit |
| `resources/js/Pages/PolicyForm.jsx` | React page: create/edit form |
| `routes/web.php` | Add policy CRUD routes |
| `tests/Feature/Dashboard/PolicyDashboardPageTest.php` | Feature tests |

## Test Plan

- Page returns 200, renders Inertia `Policies` component
- Props structure: entries (paginated), filters, agents, services
- Entry data shape includes id, agent_name, service_name, rules, is_active, rule_count, created_at
- Filtering by active status
- Search by agent name / service name
- Hive scoping (policies from other hives hidden)
- Store creates policy with valid rules
- Store rejects invalid rules structure
- Store rejects duplicate agent+service pair
- Update modifies existing policy rules
- Delete removes policy
- Toggle flips is_active
- Fail-closed when hive context missing
