# TASK-024: Agents Dashboard Page

| Field | Value |
|-------|-------|
| **Status** | done |
| **Priority** | High |
| **Depends On** | TASK-014 (Agent model), TASK-015 (Permissions), TASK-022 (Frontend setup), TASK-023 (Dashboard home) |
| **Branch** | `task/024-agents-dashboard` |

## Requirements

Build a dedicated agents dashboard page at `/dashboard/agents` that provides:

1. **Agent table** — paginated list (15 per page) of all agents in the current hive
2. **Status breakdown** — color-coded bar + per-status counts (same pattern as dashboard home)
3. **Filtering** — filter agents by status via dropdown
4. **Search** — search agents by name (case-insensitive partial match)
5. **Sorting** — sort by created_at (default, desc), name (asc), last_heartbeat (desc), status (desc)
6. **Tasks claimed** — display count of in-progress tasks each agent has claimed
7. **Pagination** — server-side pagination with navigation links
8. **Empty state** — friendly message when no agents exist
9. **Navigation** — sidebar "Agents" link is now active (no longer "Coming Soon")

## Design Decisions

- **Server-side filtering/sorting/pagination** — all via query params, no client-side data manipulation
- **Shared components** — `StatusBadge`, `StatusBar`, `STATUS_COLORS`, `STATUS_LABELS` extracted to `resources/js/Components/StatusBadge.jsx`
- **Agent → Task relationship** — added `claimedTasks(): HasMany` to Agent model for `withCount` support
- **Controller pattern** — follows `DashboardController` structure (Inertia render, no API envelope)

## Files

| File | Action |
|------|--------|
| `app/Http/Controllers/Dashboard/AgentDashboardController.php` | Created |
| `resources/js/Pages/Agents.jsx` | Created |
| `resources/js/Components/StatusBadge.jsx` | Created (extracted from Dashboard.jsx) |
| `tests/Feature/Dashboard/AgentDashboardPageTest.php` | Created |
| `docs/tasks/TASK-024-agents-dashboard.md` | Created |
| `docs/guide/agents-dashboard.md` | Created |
| `app/Models/Agent.php` | Modified — added `claimedTasks()` relationship |
| `routes/web.php` | Modified — added `/dashboard/agents` route |
| `resources/js/Layouts/AppLayout.jsx` | Modified — removed `comingSoon` from Agents nav |
| `resources/js/Pages/Dashboard.jsx` | Modified — imports from shared StatusBadge component |
| `docs/index.md` | Modified — added agents dashboard guide link |

## Test Plan

| Test | Assertion |
|------|-----------|
| `test_agents_page_returns_200` | GET /dashboard/agents → 200 |
| `test_agents_page_renders_inertia_component` | Component is `'Agents'` |
| `test_agents_page_includes_agents_prop` | Has paginated data structure |
| `test_agents_page_includes_status_breakdown` | Has all 5 statuses |
| `test_agents_page_includes_filters_prop` | Has status, search, sort |
| `test_agents_page_lists_agents_from_current_hive` | Agents appear in data |
| `test_agents_page_excludes_agents_from_other_hives` | Cloud scoping test |
| `test_agents_page_filters_by_status` | `?status=online` filters correctly |
| `test_agents_page_filters_by_search` | `?search=deploy` matches names |
| `test_agents_page_sorts_by_name` | `?sort=name` → alphabetical order |
| `test_agents_page_sorts_by_last_heartbeat` | `?sort=last_heartbeat` → newest first |
| `test_agents_page_default_sort_is_created_at_desc` | Default order is newest first |
| `test_agents_page_paginates_results` | 20 agents → 15 on page 1 |
| `test_agents_page_includes_tasks_claimed_count` | In-progress task count correct |
| `test_agents_page_returns_empty_when_no_agents` | Empty data, total=0 |
| `test_agents_page_status_breakdown_counts_are_integers` | Int type enforcement |
| `test_agents_page_agent_data_shape` | All expected fields present |
| `test_agents_page_invalid_sort_falls_back_to_created_at` | Bad sort param → default |
