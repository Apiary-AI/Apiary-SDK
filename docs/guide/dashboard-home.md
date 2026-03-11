# Dashboard Home Page

The dashboard home page provides an at-a-glance operational overview of your
hive. It surfaces key health metrics, agent fleet status, task pipeline state,
and recent activity — all rendered server-side via Inertia.js.

## Sections

### Summary Cards

Four top-level stat cards show the most important numbers:

| Card | Source |
|------|--------|
| **Active Agents** | Agents with status `online`, `busy`, or `idle` |
| **Pending Tasks** | Tasks with status `pending` |
| **In Progress** | Tasks with status `in_progress` |
| **Knowledge Entries** | Total knowledge entry count |

### Agent Fleet Breakdown

A color-coded status bar and per-status counts for the full agent fleet:

| Status | Color | Meaning |
|--------|-------|---------|
| Online | Green | Connected and ready |
| Busy | Amber | Currently processing a task |
| Idle | Sky | Connected but not working |
| Offline | Slate | Not connected |
| Error | Red | In error state |

### Task Pipeline Breakdown

A color-coded status bar and per-status counts for all tasks:

| Status | Color | Meaning |
|--------|-------|---------|
| Pending | Amber | Awaiting claim |
| In Progress | Sky | Being processed |
| Completed | Green | Successfully finished |
| Failed | Red | Execution failed |
| Cancelled | Slate | Manually cancelled |

### Recent Activity

The latest 10 activity log entries showing:

- **Action** — the event that occurred (e.g., `task.created`, `agent.registered`)
- **Agent** — the agent that triggered the action (if applicable)
- **Task** — the related task type (if applicable)
- **Timestamp** — when the event occurred

### Recent Tasks

The latest 5 tasks in a compact table showing:

- **Type** — the task type
- **Status** — current status with color-coded badge
- **Priority** — numeric priority value
- **Assigned To** — the agent that claimed the task, or "Unclaimed"
- **Created** — when the task was created

## Data Flow

All dashboard data is loaded server-side in `DashboardController::index()`
and passed as Inertia props. There are no client-side API calls — the page
renders with complete data on first load.

```
DashboardController::index()
  ├── agentCount          → Agent::whereIn(status, ACTIVE_STATUSES)->count()
  ├── taskCounts          → { pending, in_progress }
  ├── knowledgeCount      → KnowledgeEntry::count()
  ├── agentStatusBreakdown → grouped count per agent status
  ├── taskStatusBreakdown  → grouped count per task status
  ├── recentActivity       → latest 10 activity_log with agent/task names
  └── recentTasks          → latest 5 tasks with claimed_by agent name
```

## Empty States

When no data exists, each section displays a friendly empty-state message
instead of an empty container. The summary cards show `0` values.

## Responsive Layout

The page uses a responsive grid that adapts to screen width:

- **Mobile** — single column, stacked sections
- **Tablet** — 2-column stat cards, stacked breakdowns
- **Desktop** — 4-column stat cards, 2-column breakdowns and feeds

## Adding Data to the Dashboard

To add a new section or metric:

1. Add the query to `DashboardController::index()` as a new Inertia prop
2. Destructure the prop in `Dashboard.jsx`
3. Create a component to render the data
4. Add a test in `DashboardPageTest.php` to verify the prop shape
