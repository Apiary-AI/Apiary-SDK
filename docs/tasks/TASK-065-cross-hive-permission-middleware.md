# TASK-065: Cross-Hive Permission Middleware

## Status
In Progress

## Depends On
- TASK-064 (Cross-hive permission model) ✅

## Summary

Harden and enhance the `CheckCrossHivePermission` middleware with request
decoration, fail-closed tenant-safe behavior, and comprehensive test coverage.
TASK-064 created the basic middleware; this task adds production-quality
features that downstream controllers and future cross-hive tasks depend on.

## Requirements

1. **Request decoration** — middleware sets `is_cross_hive` (bool) and
   `source_hive_id` (string|null) on `$request->attributes` so downstream
   controllers can consume cross-hive metadata without recomputing it.

2. **Fail-closed behavior** — already present in base middleware (missing
   agent → 403, missing resolved hive → 403); verified via dedicated tests.

3. **Controller simplification** — `TaskController`, `EventController`, and
   `KnowledgeController` consume `$request->attributes->get('is_cross_hive')`
   instead of recomputing `$agent->hive_id !== $targetHive->id`.

4. **Comprehensive middleware test suite** — dedicated
   `CrossHivePermissionMiddlewareTest.php` covering:
   - Same-hive passthrough + attributes set to false/null
   - Cross-hive denied without permission
   - Cross-hive allowed with specific permission
   - Cross-hive allowed with wildcard `cross_hive:*`
   - Cross-hive allowed with `admin:*`
   - Cross-apiary always denied (tenant boundary)
   - Fail-closed: missing resolved hive → 403
   - Denial logged to activity_log
   - Request attributes (is_cross_hive, source_hive_id) verified
   - API envelope format on denial
   - Real route integration (cross-hive task creation)
   - Specific permission grants access to one hive but not others

## Design Decisions

- **Defense-in-depth preserved**: controllers keep their
  `crossHiveService->canAccessHive()` checks as a second line of defense.
- **Attribute convention**: `is_cross_hive` and `source_hive_id` follow the
  same `$request->attributes` pattern used by `ResolveHive` (`hive` attribute).
- **No new migration**: uses existing `agent_permissions` table.

## Files

| File | Action |
|------|--------|
| `app/Http/Middleware/CheckCrossHivePermission.php` | Edit |
| `app/Http/Controllers/Api/TaskController.php` | Edit |
| `app/Http/Controllers/Api/EventController.php` | Edit |
| `tests/Feature/CrossHivePermissionMiddlewareTest.php` | Create |
| `docs/tasks/TASK-065-cross-hive-permission-middleware.md` | Create |

## Test Plan

- Same-hive access: `is_cross_hive` = false, `source_hive_id` = null
- Cross-hive access with permission: `is_cross_hive` = true, `source_hive_id` set
- Cross-hive denied without permission: 403, logged
- Wildcard `cross_hive:*` grants all hives in apiary
- `admin:*` grants cross-hive access
- Cross-apiary always denied regardless of permissions
- Fail-closed: no resolved hive → 403
- Real route integration: cross-hive task creation succeeds with permission
- API envelope on all error responses
