# Agents Dashboard

The agents dashboard page provides a detailed view of all registered agents in
your current hive. It surfaces status information, filtering, search, and task
assignment data — all rendered server-side via Inertia.js.

## URL

```
GET /dashboard/agents
```

## Sections

### Agent Fleet Breakdown

A color-coded status bar and per-status counts, identical to the dashboard home
agent fleet widget:

| Status | Color | Meaning |
|--------|-------|---------|
| Online | Green | Connected and ready |
| Busy | Amber | Currently processing a task |
| Idle | Sky | Connected but not working |
| Offline | Slate | Not connected |
| Error | Red | In error state |

### Filter Bar

Three controls for narrowing and sorting the agent list:

| Control | Type | Options |
|---------|------|---------|
| Status filter | Dropdown | All / Online / Busy / Idle / Offline / Error |
| Search | Text input | Partial name match (case-insensitive) |
| Sort | Dropdown | Newest / Name / Last Heartbeat / Status |

Filters are applied via URL query parameters and trigger a server-side reload:

```
/dashboard/agents?status=online&search=deploy&sort=name
```

### Agent Table

A responsive table with the following columns:

| Column | Description |
|--------|-------------|
| **Name** | Agent name (bold, primary column) |
| **Type** | Agent type badge (hidden on mobile) |
| **Status** | Color-coded status badge |
| **Last Heartbeat** | Relative time (e.g., "2m ago") or "Never" (hidden on mobile) |
| **Tasks** | Count of in-progress tasks claimed by this agent |
| **Created** | Registration date |

### Pagination

Server-side pagination with 15 agents per page. Previous/Next links appear
when there are multiple pages. Page info shows "Page X of Y (N agents)".

### Empty State

When no agents are registered, a centered message reads "No agents registered
yet." instead of an empty table.

## Data Flow

All data is loaded server-side in `AgentDashboardController::index()` and passed
as Inertia props. No client-side API calls are made.

```
AgentDashboardController::index()
  ├── agents          → paginated agent list with tasks_claimed count
  ├── statusBreakdown → grouped count per agent status (all 5 filled)
  └── filters         → echo of current filter values { status, search, sort }
```

## Query Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `status` | string | (none) | Filter by agent status |
| `search` | string | (none) | Partial name search |
| `sort` | string | `created_at` | Sort column |
| `page` | int | 1 | Pagination page number |

## Shared Components

The `StatusBadge`, `StatusBar`, `STATUS_COLORS`, and `STATUS_LABELS` are shared
between the dashboard home page and the agents page. They live in
`resources/js/Components/StatusBadge.jsx`.
