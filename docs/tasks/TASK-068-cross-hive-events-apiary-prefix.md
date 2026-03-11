# TASK-068: Cross-Hive Events (apiary.* prefix)

**Status:** In Progress
**Branch:** `task/068-cross-hive-events-apiary-prefix`
**Depends On:** 053 (Event bus service) ✅, 065 (Cross-hive permission middleware) ✅

## Requirements

Enforce explicit cross-hive event semantics for the `apiary.*` event type prefix:

1. **Publishing** — Only agents with `cross_hive` permission can emit `apiary.*` events
2. **Subscribing** — Only agents with `cross_hive` permission can create `apiary`-scoped subscriptions
3. **Polling** — Defense-in-depth: filter cross-hive events from poll results for agents without `cross_hive` permission
4. **Cross-apiary isolation** — Events never leak across apiary boundaries
5. **Backward compatibility** — Hive-scoped events remain unaffected

## Design

### Permission Check

A new `hasAnyCrossHivePermission(Agent)` method on `CrossHivePermissionService` checks whether the agent holds any `cross_hive:*` permission (specific hive or wildcard). This is used for apiary-wide operations (events, subscriptions) where no specific target hive is involved.

### Enforcement Points

| Layer | Check | Behavior on Failure |
|-------|-------|---------------------|
| EventController::publish() | `apiary.*` type requires cross_hive permission | 403 Forbidden |
| EventController::subscribe() | scope=apiary requires cross_hive permission | 403 Forbidden |
| EventController::replaceSubscriptions() | any scope=apiary entry requires cross_hive | 403 Forbidden |
| EventController::poll() | defense-in-depth: strip cross-hive events if no permission | Silent filter |
| EventBus::poll() | unchanged (data layer, no HTTP concerns) | — |

### Activity Logging

Denied cross-hive event publish attempts are logged with action `cross_hive.event_denied`.

## Files Changed

- `app/Services/CrossHivePermissionService.php` — add `hasAnyCrossHivePermission()`
- `app/Http/Controllers/Api/EventController.php` — enforce cross-hive permission on publish/subscribe/replace/poll
- `tests/Feature/CrossHiveEventPermissionTest.php` — new test file for cross-hive event permission enforcement

## Test Plan

1. Agent without cross_hive permission denied from publishing `apiary.*` event
2. Agent with cross_hive permission allowed to publish `apiary.*` event
3. Agent without cross_hive permission denied from subscribing with scope=apiary
4. Agent with cross_hive permission allowed to subscribe with scope=apiary
5. Agent without cross_hive permission denied from replacing with scope=apiary entries
6. Defense-in-depth: poll filters cross-hive events for agent without permission
7. Cross-apiary isolation: events from apiary A not visible to agents in apiary B
8. Hive-scoped events unaffected by cross-hive permission checks
9. Activity log created on denied cross-hive event publish
10. Agent with admin:* wildcard can publish cross-hive events
