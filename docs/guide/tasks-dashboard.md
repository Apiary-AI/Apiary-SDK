# Tasks Dashboard (Kanban Board)

The tasks dashboard page provides a Kanban board view of all tasks in your
current hive, grouped by status. It surfaces priority, progress, and assignment
data — all rendered server-side via Inertia.js.

## URL

```
GET /dashboard/tasks
```

## Sections

### Task Pipeline Breakdown

A color-coded status bar and per-status counts for all tasks:

| Status | Color | Meaning |
|--------|-------|---------|
| Pending | Amber | Awaiting claim |
| In Progress | Sky | Being processed by an agent |
| Completed | Green | Successfully finished |
| Failed | Red | Execution failed |
| Cancelled | Slate | Manually cancelled |

### Filter Bar

Three controls for narrowing and sorting across all columns:

| Control | Type | Options |
|---------|------|---------|
| Priority filter | Dropdown | All / Critical / High / Default / Normal / Low |
| Search | Text input | Partial match on type and status message |
| Sort | Dropdown | Newest / Priority / Type |

Filters are applied via URL query parameters and trigger a server-side reload:

```
/dashboard/tasks?priority=4&search=deploy&sort=priority
```

### Kanban Board

Five columns, one per task status, displayed in a horizontally scrollable
container. Each column shows up to 20 tasks ordered by the selected sort.

#### Column Header

- Color dot matching the status color
- Status label
- Total task count for that status

#### Task Cards

Each card displays:

| Field | Description |
|-------|-------------|
| **Type** | Task type (bold, primary text) |
| **Priority** | Priority badge (Low / Normal / Default / High / Critical) |
| **Progress** | Progress bar shown for in-progress tasks with progress > 0 |
| **Status message** | Truncated status message (if set) |
| **Claimed by** | Agent name or "Unclaimed" |
| **Created** | Relative time (e.g., "2m ago") |

#### Overflow Indicator

When a column has more tasks than the 20-task limit, a footer shows
"Showing 20 of N".

### Empty State

When no tasks exist, each column displays "No tasks" in the card area.
The pipeline breakdown bar shows "No tasks registered yet."

## Data Flow

All data is loaded server-side in `TaskDashboardController::index()` and passed
as Inertia props. No client-side API calls are made.

```
TaskDashboardController::index()
  ├── columns          → { status: { tasks: [...], total, showing } } per status
  ├── statusBreakdown  → grouped count per task status (all 5 filled)
  └── filters          → echo of current filter values { search, sort, priority }
```

## Query Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `search` | string | (none) | Partial match on type and status_message |
| `sort` | string | `created_at` | Sort column (created_at, priority, type) |
| `priority` | int | (none) | Filter by priority level (0-4) |

## Shared Components

The `StatusBar`, `STATUS_COLORS`, and `STATUS_LABELS` are shared between the
dashboard home page, agents page, and tasks page. They live in
`resources/js/Components/StatusBadge.jsx`.
