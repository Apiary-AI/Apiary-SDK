# Activity Feed

The activity feed page provides a paginated, filterable view of the immutable
audit trail. Every state change recorded by the ActivityLogger service is
surfaced here with agent and task context.

## URL

```
GET /dashboard/activity
```

## Sections

### Action Breakdown

A color-coded bar and per-action counts showing the distribution of activity
across action types. Only actions with at least one entry are displayed. The
breakdown is scoped to the current hive.

### Filter Bar

Three controls for narrowing and sorting the activity list:

| Control | Type | Options |
|---------|------|---------|
| Action filter | Dropdown | All / dynamic list from recorded actions |
| Search | Text input | Partial match on action, agent name, or task type |
| Sort | Dropdown | Newest (default) / Action |

Filters are applied via URL query parameters and trigger a server-side reload:

```
/dashboard/activity?action=task.created&search=deploy&sort=action
```

### Activity Table

A responsive table with the following columns:

| Column | Description |
|--------|-------------|
| **Action** | Color-coded action badge (e.g., `task.created`, `agent.online`) |
| **Agent** | Name of the agent that performed the action (hidden on mobile) |
| **Task** | Task type badge if the entry relates to a task (hidden on mobile) |
| **Details** | Truncated JSON preview of the details payload (hidden on small screens) |
| **Time** | Relative timestamp (e.g., "5m ago") |

### Pagination

Server-side pagination with 20 entries per page. Previous/Next links appear
when there are multiple pages. Page info shows "Page X of Y (N entries)".

### Empty State

When no activity entries exist, a centered message reads "No activity recorded
yet." instead of an empty table.

## Data Flow

All data is loaded server-side in `ActivityDashboardController::index()` and
passed as Inertia props. No client-side API calls are made.

```
ActivityDashboardController::index()
  ├── entries         → paginated entry list with agent + task relationships
  ├── actionBreakdown → grouped count per action type
  └── filters         → echo of current filter values { action, search, sort }
```

## Query Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `action` | string | (none) | Filter by exact action string |
| `search` | string | (none) | Partial match on action, agent name, or task type |
| `sort` | string | `created_at` | Sort column: `created_at` or `action` |
| `page` | int | 1 | Pagination page number |

## Scoping

- **CE mode**: scoped to the default hive via `resolveCurrentHiveId()`
- **Cloud mode**: `BelongsToApiary` global scope enforces tenant isolation;
  additionally scoped to current hive via `forHive()` query scope
- **Fail closed**: returns an empty feed if hive context is missing

## Input Sanitization

Non-scalar query parameters (e.g., `?search[]=foo`) are silently rejected and
treated as if not provided. Invalid sort values fall back to `created_at`.
