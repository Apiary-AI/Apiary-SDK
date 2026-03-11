# TASK-003: API response envelope & base controller

**Status:** done
**Branch:** `task/003-api-envelope`
**PR:** —
**Depends on:** TASK-001
**Blocks:** TASK-014, TASK-016, TASK-020, TASK-030

## Objective

Establish the standard `{ data, meta, errors }` JSON response envelope and an
`ApiController` base class so all future API endpoints produce consistent
responses without duplicating formatting logic.

## Requirements

### Functional

- [ ] FR-1: Create `ApiController` base class extending `Controller` with helper methods for success, created, error, and validation-error responses
- [ ] FR-2: All helpers produce the canonical `{ data, meta, errors }` envelope
- [ ] FR-3: Success responses include `data` (any), optional `meta` (object), and `errors` as `null`
- [ ] FR-4: Error responses include `data` as `null`, `errors` as an array of `{ code, message, field? }` objects, and optional `meta`
- [ ] FR-5: HTTP status codes: 200 (ok), 201 (created), 204 (no content), 422 (validation), 404 (not found), 403 (forbidden), 500 (server error)

### Non-Functional

- [ ] NFR-1: PSR-12 compliant
- [ ] NFR-2: No external dependencies beyond Laravel
- [ ] NFR-3: Focused unit test coverage for all envelope shapes

## Architecture & Design

### Files to Create / Modify

| Action | Path | Purpose |
|--------|------|---------|
| Create | `app/Http/Controllers/Api/ApiController.php` | Base API controller with response envelope helpers |
| Create | `tests/Unit/ApiControllerTest.php` | Unit tests for envelope format and status codes |

### Key Design Decisions

- **Thin helper methods**: each method returns a `JsonResponse` with the standard envelope. Controllers call `$this->success(...)`, `$this->created(...)`, `$this->error(...)`, etc.
- **No middleware/trait split**: envelope logic lives in the base controller since it's only relevant to API routes. Future API controllers extend `ApiController`.
- **`errors` is always present**: `null` on success, array on failure — consumers can always check without guessing the shape.
- **`meta` is always present**: defaults to empty object `{}` so consumers don't need null-checks.

## Implementation Plan

1. Create `app/Http/Controllers/Api/ApiController.php` with response helpers
2. Write unit tests covering all envelope shapes and status codes
3. Run tests and validate

## Database Changes

_None._

## API Changes

_None (foundational class only; no routes added)._

## Test Plan

### Unit Tests

- [ ] `success()` returns 200 with `{ data, meta, errors: null }`
- [ ] `success()` merges custom meta into response
- [ ] `created()` returns 201 with `{ data, meta, errors: null }`
- [ ] `noContent()` returns 204 with empty body
- [ ] `error()` returns given status with `{ data: null, meta, errors: [...] }`
- [ ] `validationError()` returns 422 with field-level errors
- [ ] `notFound()` returns 404 with error message
- [ ] `forbidden()` returns 403 with error message

## Validation Checklist

- [ ] All tests pass (`php artisan test`)
- [x] PSR-12 compliant
- [ ] Activity logging on state changes — N/A
- [x] API responses use `{ data, meta, errors }` envelope
- [ ] Form Request validation on all inputs — N/A
- [ ] ULIDs for primary keys — N/A
- [ ] BelongsToApiary/BelongsToHive traits applied where needed — N/A
- [x] No credentials logged in plaintext
