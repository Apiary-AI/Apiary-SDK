# TASK-064: Cross-Hive Permission Model

## Status
In Progress

## Depends On
- TASK-007 (Agent migration + model + permissions) ✅
- TASK-061 (Activate BelongsToHive global scopes) ⬜

## Summary

Implement the cross-hive permission model that gates agent access to hives
other than their home hive. Cross-hive permissions use the format
`cross_hive:{target_hive_id}` or `cross_hive:*` and are stored as regular
entries in the existing `agent_permissions` table.

No new migration is required — the existing `agent_permissions` table already
supports arbitrary permission strings.

## Requirements

1. **CrossHivePermissionService** — encapsulates cross-hive permission logic:
   - Same-hive access always allowed (bypass cross-hive check)
   - Cross-apiary access always denied (tenant boundary, fail closed)
   - Checks `cross_hive:{target_hive_id}` via PolicyService
   - Inherits `cross_hive:*` wildcard and `admin:*` super-admin access
   - Activity logging on permission denials

2. **CheckCrossHivePermission middleware** — route middleware for hive-scoped endpoints:
   - Applied after `ResolveHive` middleware
   - Passes same-hive requests through
   - Checks cross-hive permission for foreign hive requests
   - Returns 403 with standard API envelope on denial
   - Fails closed on missing agent or hive context

3. **Agent model helpers** — convenience methods:
   - `hasCrossHiveAccess(Hive): bool`
   - `grantCrossHiveAccess(Hive|string, ?grantedBy): void`
   - `revokeCrossHiveAccess(Hive|string): void`

## Permission Format

| Permission | Meaning |
|------------|---------|
| `cross_hive:{hive_id}` | Access to specific target hive |
| `cross_hive:*` | Access to all hives in same apiary |
| `admin:*` | Full access (inherited from PolicyService) |

## Design Decisions

- **No new migration**: cross-hive permissions are stored as regular permission
  strings in `agent_permissions`, leveraging the existing infrastructure.
- **Hive ID over slug**: permission strings use hive ULID for precision
  (slugs can be renamed).
- **Fail closed**: missing context (no agent, no hive) returns 403.
- **Same-hive bypass**: when agent's hive_id matches target hive, no
  cross-hive permission is needed.

## Test Plan

- Same-hive access always allowed
- Specific hive permission grants access to that hive only
- Wildcard `cross_hive:*` grants access to all hives in same apiary
- `admin:*` grants cross-hive access
- Cross-apiary access always denied
- Denial without any cross-hive permission
- Denial logged to activity_log
- Grant/revoke via Agent model helpers
- Middleware: 403 on unauthorized cross-hive access
- Middleware: 200 on authorized cross-hive access
- Middleware passes through for same-hive requests
- Fail-closed: missing agent → 403
- Fail-closed: missing resolved hive → 403

## Files

| File | Action |
|------|--------|
| `app/Services/CrossHivePermissionService.php` | Create |
| `app/Http/Middleware/CheckCrossHivePermission.php` | Create |
| `app/Models/Agent.php` | Edit |
| `bootstrap/app.php` | Edit |
| `tests/Feature/CrossHivePermissionTest.php` | Create |
