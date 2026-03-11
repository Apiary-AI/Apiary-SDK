# TASK-013: Permission Checking Middleware

**Status:** done
**Branch:** `task/013-permission-middleware`
**PR:** —
**Depends on:** TASK-012
**Blocks:** TASK-014, TASK-016, TASK-020, TASK-030

## Objective

Implement permission checking middleware for the API, enabling fine-grained access control based on agent capabilities and roles. This is the enforcement layer for the permission model introduced in TASK-007.

## Requirements

### Functional

- [x] FR-1: Middleware checks agent permissions before API access
- [x] FR-2: Support permission strings (e.g., `tasks.create`, `tasks.claim`, `knowledge.read`)
- [x] FR-3: Support role-based fallback (optional role assignment for agents)
- [x] FR-4: Return proper 403 Forbidden response when permission denied
- [x] FR-5: Log permission denied attempts for audit

### Non-Functional

- [x] NFR-1: Minimal DB queries — cache permissions where possible
- [x] NFR-2: Fast-fail on missing/invalid auth token
- [x] NFR-3: PSR-12 compliant

## Architecture & Design

### Files to Create / Modify

| Action | Path | Purpose |
|--------|------|---------|
| Create | `app/Http/Middleware/CheckAgentPermission.php` | Main permission middleware |
| Create | `app/Http/Middleware/CheckAgentRole.php` | Role-based middleware |
| Create | `app/Services/PolicyService.php` | Permission evaluation logic |
| Modify | `bootstrap/app.php` | Register middleware |
| Modify | `routes/api.php` | Apply middleware to routes |

### Key Design Decisions

- **Permission model**: String-based permissions (`resource.action`) mapped from `agent_permissions` table
- **Caching**: Agent permissions cached in Redis with TTL
- **Policy engine**: Expandable for future deny/require_approval/allow rules

## Implementation Plan

1. Create `PolicyService` for permission evaluation
2. Create `CheckAgentPermission` middleware
3. Create `CheckAgentRole` middleware (optional role-based)
4. Register middleware in `bootstrap/app.php`
5. Apply to API routes
6. Write tests

## Test Plan

### Unit Tests

- [x] PolicyService evaluates permissions correctly
- [x] Permission cache works

### Feature Tests

- [x] Access denied without token returns 401
- [x] Access denied with insufficient permission returns 403
- [x] Access granted with sufficient permission returns 200
- [x] Permission denial is logged

## Validation Checklist

- [x] All tests pass (`php artisan test`)
- [x] PSR-12 compliant
- [x] Activity logging on permission denial
- [x] API responses use `{ data, meta, errors }` envelope
