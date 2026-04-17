# TASK-250: Events dashboard page

**Status:** done
**Branch:** `task/250-events-dashboard`
**Depends on:** —
**Edition:** shared
**Feature doc:** —

## Objective

Build a dashboard page for viewing events and managing agent subscriptions. This closes GAP-006 (Events dashboard page) from the gap analysis backlog and provides visibility into the EventBus that becomes central after the unification (TASK-245).

## Background

The EventBus was built in Phase 3 (TASK-051–054) but has no dashboard visibility — events and subscriptions are only accessible via API. With task and channel events now flowing through the EventBus, operators need a way to monitor event flow, debug delivery issues, and manage subscriptions from the dashboard.

## Requirements

### Functional

- [ ] FR-1: Event stream view at `/dashboard/events` — paginated list of recent events
- [ ] FR-2: Filter events by: event type, source agent, time range
- [ ] FR-3: Event detail: click an event to see full payload (JSON viewer)
- [ ] FR-4: Subscription management panel — list all agent subscriptions, create new subscriptions, delete existing ones
- [ ] FR-5: Event type breakdown — summary showing count of events per type in the selected time range
- [ ] FR-6: Real-time updates via WebSocket (Reverb) for new events as they flow in
- [ ] FR-7: Hive-scoped — only shows events within the current hive

### Non-Functional

- [ ] NFR-1: Inertia/React page following existing dashboard patterns
- [ ] NFR-2: Paginated with 50 events per page (consistent with other dashboard pages)
- [ ] NFR-3: Time range defaults to last 24 hours
- [ ] NFR-4: Accessible from main navigation sidebar

## Architecture & Design

### Files to Create / Modify

| Action | Path | Purpose |
|--------|------|---------|
| Create | `app/Http/Controllers/Dashboard/EventDashboardController.php` | Dashboard controller for events |
| Create | `resources/js/Pages/Events/Index.jsx` | Event stream list page |
| Create | `resources/js/Pages/Events/Subscriptions.jsx` | Subscription management page |
| Modify | `resources/js/Layouts/AppLayout.jsx` | Add Events to navigation sidebar |
| Modify | `routes/web.php` | Add dashboard event routes |

### Key Design Decisions

- Two sub-pages: event stream (Index) and subscriptions (Subscriptions), accessible via tabs
- Reuse existing dashboard UI patterns (pagination, filters, data tables) from other dashboard pages
- Event payload displayed in a collapsible JSON viewer component

## Implementation Plan

1. Create `EventDashboardController` with `index()` (event stream) and `subscriptions()` (subscription management) actions
2. Build React pages with filtering, pagination, and JSON payload viewer
3. Add navigation entry and routes
4. Connect WebSocket channel for real-time event updates

## Test Plan

### Feature Tests

- [ ] Event list page loads with events from current hive
- [ ] Filter by event type returns correct subset
- [ ] Filter by source agent returns correct subset
- [ ] Filter by time range returns correct subset
- [ ] Subscription list shows all subscriptions for current hive
- [ ] Create subscription from dashboard works
- [ ] Delete subscription from dashboard works
- [ ] Events from other hives are not visible

## Validation Checklist

- [ ] All tests pass (`php artisan test`)
- [ ] PSR-12 compliant
- [ ] Inertia page renders correctly
- [ ] Navigation link appears in sidebar
- [ ] Responsive layout (mobile-friendly)
- [ ] BelongsToHive scoping enforced
