# Dashboard Index Page

The root URL (`/`) renders a product-native landing page instead of the
default Laravel welcome page. This ensures a consistent dashboard experience
from the first request.

## Route

```
GET /  →  IndexController  →  Inertia('Index')
```

The route is named `home` and uses a single-action `IndexController`.

## What It Shows

### Quick Stats

Two lightweight summary cards at the top:

| Card | Source |
|------|--------|
| **Active Agents** | Agents with status `online`, `busy`, or `idle` |
| **Pending Tasks** | Tasks with status `pending` |

These are intentionally lighter than the full `/dashboard` payload to keep
the landing page fast.

### Navigation Cards

Five cards linking to the core dashboard sections:

| Card | Route | Description |
|------|-------|-------------|
| Dashboard | `/dashboard` | Operational overview with fleet and pipeline metrics |
| Agents | `/dashboard/agents` | Agent listing and status monitoring |
| Tasks | `/dashboard/tasks` | Kanban board with filtering and search |
| Knowledge | `/dashboard/knowledge` | Knowledge entry explorer with scope breakdown |
| Activity | `/dashboard/activity` | Full audit trail of system events |

## Relationship to `/dashboard`

The index page (`/`) is a lightweight entry point with navigation CTAs.
The dashboard page (`/dashboard`) is the full operational overview with
detailed metrics, status breakdowns, recent activity, and recent tasks.

```
/              → Index page (quick stats + navigation cards)
/dashboard     → Full dashboard (fleet, pipeline, activity, tasks)
/dashboard/*   → Section pages (agents, tasks, knowledge, activity)
```

## Layout

The index page uses the same `AppLayout` wrapper as all other dashboard pages,
providing the sidebar navigation, hive indicator, and edition badge.

## Adding the Index Page

The index page was introduced to replace the Laravel welcome page. The
`welcome.blade.php` template has been removed — the root URL now renders
through Inertia like every other page.
