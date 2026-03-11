# TASK-067: Cross-Hive Router Service

## Status
In Progress

## Depends On
- TASK-066 (Cross-hive task controller) ✅

## Summary

Extract and centralize cross-hive task routing logic into a dedicated
`CrossHiveRouter` service. Currently, cross-hive task creation logic is
inline in `TaskController::store()` — the router encapsulates target hive
resolution, permission validation, provenance tracking, activity logging,
and task dispatch into a reusable service.

## Requirements

1. **CrossHiveRouter service** (`app/Services/CrossHiveRouter.php`)
   - `route(Agent, Hive, array): CrossHiveRoutingResult` — full cross-hive
     task dispatch: validates permissions, checks target hive is active,
     creates task with `source_hive_id`, logs activity, broadcasts event.
   - `resolveTargetHive(string $hiveId, string $apiaryId): ?Hive` — resolves
     and validates target hive (exists, same apiary, active).
   - `canRoute(Agent, Hive): bool` — permission-only check with no side effects.
   - `getRoutableHiveIds(Agent): array` — returns hive IDs the agent can
     route to (delegates to CrossHivePermissionService).

2. **CrossHiveRoutingResult** (`app/Services/CrossHiveRoutingResult.php`)
   - Value object with `success`, `task`, `error`, `errorCode` fields.
   - Named constructors: `ok()`, `denied()`, `notFound()`, `inactive()`.

3. **Refactor TaskController::store()** — delegate cross-hive task creation
   to the router service, keeping same-hive path unchanged.

4. **Fail-closed behavior** — missing permissions, unknown hives, inactive
   hives, cross-apiary attempts all result in denial.

5. **Activity logging** — all routing decisions (success and failure) logged
   with cross-hive context.

6. **Backward-safe** — same-hive task creation unchanged; existing API
   contracts preserved.

## Design Decisions

- Router returns a result object instead of throwing exceptions, keeping
  the service HTTP-agnostic and testable.
- Same-hive task creation stays in the controller — the router is only
  invoked for cross-hive cases.
- Router delegates permission checks to `CrossHivePermissionService` (no
  duplication).
- Target hive validation includes `is_active` check — tasks cannot be
  routed to deactivated hives.

## Files

| File | Action |
|------|--------|
| `app/Services/CrossHiveRouter.php` | Create |
| `app/Services/CrossHiveRoutingResult.php` | Create |
| `app/Http/Controllers/Api/TaskController.php` | Edit |
| `tests/Feature/CrossHiveRouterTest.php` | Create |
| `docs/tasks/TASK-067-cross-hive-router-service.md` | Create |

## Test Plan

- Route: successful cross-hive task creation with correct provenance
- Route: returns denied when agent lacks cross-hive permission
- Route: returns not_found for nonexistent target hive
- Route: returns inactive for deactivated target hive
- Route: returns denied for cross-apiary target hive
- Route: same-hive routing not treated as cross-hive
- Route: activity logged on success with cross_hive flag
- Route: activity logged on permission denial
- Route: broadcasts TaskStatusChanged on success
- Route: task fields (type, priority, payload, etc.) correctly propagated
- resolveTargetHive: returns hive for valid same-apiary hive
- resolveTargetHive: returns null for nonexistent hive
- resolveTargetHive: returns null for different-apiary hive
- resolveTargetHive: returns null for inactive hive
- canRoute: returns true with proper permissions
- canRoute: returns false without permissions
- canRoute: returns true for same-hive (always allowed)
- getRoutableHiveIds: delegates to permission service
- TaskController integration: cross-hive store uses router
- TaskController integration: same-hive store unchanged
- Cross-apiary isolation verified end-to-end
