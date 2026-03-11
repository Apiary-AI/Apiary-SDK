# TASK-NNN: Title

**Status:** pending | in-progress | review | done
**Branch:** `task/NNN-feature-name`
**PR:** —
**Depends on:** TASK-XXX, TASK-YYY
**Blocks:** TASK-ZZZ

## Objective

What and why (1-2 sentences).

## Requirements

### Functional

- [ ] FR-1: Testable requirement

### Non-Functional

- [ ] NFR-1: Convention/perf/security requirement

## Architecture & Design

### Files to Create / Modify

| Action | Path | Purpose |
|--------|------|---------|
| Create | `path/to/file.php` | Description |
| Modify | `path/to/file.php` | Description |

### Key Design Decisions

- Decision and rationale

## Implementation Plan

1. Step-by-step instructions

## Database Changes

_(if applicable)_

```sql
-- Migration SQL or schema description
```

## API Changes

_(if applicable)_

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST   | `/api/v1/...` | Description |

## Test Plan

### Unit Tests

- [ ] Test description

### Feature Tests

- [ ] Test description

## Validation Checklist

- [ ] All tests pass (`php artisan test`)
- [ ] PSR-12 compliant
- [ ] Activity logging on state changes
- [ ] API responses use `{ data, meta, errors }` envelope
- [ ] Form Request validation on all inputs
- [ ] ULIDs for primary keys (except ActivityLog: BIGSERIAL)
- [ ] BelongsToApiary/BelongsToHive traits applied where needed
- [ ] No credentials logged in plaintext
