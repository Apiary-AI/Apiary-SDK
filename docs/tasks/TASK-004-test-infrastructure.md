# TASK-004: Test Infrastructure

**Status:** done
**Branch:** `task/004-test-infrastructure`
**PR:** —
**Depends on:** —
**Blocks:** TASK-035

## Objective

Establish a minimal but real test infrastructure baseline that eliminates existing test warnings/failures and provides reusable helpers for all upcoming tasks.

## Requirements

### Functional

- [x] FR-1: Tests run warning-free (no missing .env warnings)
- [x] FR-2: All existing tests pass without modification to their assertions
- [x] FR-3: Base TestCase auto-cleans apiary container context between tests
- [x] FR-4: Reusable trait for creating the trait_test_models table in feature tests
- [x] FR-5: Reusable trait for API envelope assertions
- [x] FR-6: Helper methods for switching CE/Cloud mode in tests

### Non-Functional

- [x] NFR-1: Zero new composer dependencies
- [x] NFR-2: Backward-compatible — existing tests refactored, not broken
- [x] NFR-3: Infrastructure itself is tested

## Architecture & Design

### Files to Create / Modify

| Action | Path | Purpose |
|--------|------|---------|
| Create | `.env.testing` | Testing environment with APP_KEY |
| Modify | `tests/TestCase.php` | Add apiary context cleanup + edition helpers |
| Create | `tests/Traits/CreatesTraitTestTable.php` | Reusable Schema create/drop for trait tests |
| Create | `tests/Traits/AssertsApiEnvelope.php` | Custom assertions for API response envelope |
| Modify | `tests/Feature/BelongsToApiaryTest.php` | Use new traits instead of manual setup |
| Modify | `tests/Feature/BelongsToHiveTest.php` | Use new traits instead of manual setup |
| Modify | `tests/Feature/ConfigApiaryTest.php` | Use base TestCase env cleanup |
| Create | `tests/Feature/TestInfrastructureTest.php` | Validate infrastructure behavior |

### Key Design Decisions

- Stick with PHPUnit (no Pest) — matches existing test style
- `.env.testing` over phpunit.xml env additions — Laravel loads it automatically
- Auto-cleanup in base TestCase tearDown — prevents context leaking between tests
- Traits over base class inheritance — composable, opt-in per test class

## Implementation Plan

1. Create `.env.testing` with APP_KEY and minimal test config
2. Enrich `tests/TestCase.php` with `resetApiaryContext()` auto-teardown and edition helpers
3. Create `tests/Traits/CreatesTraitTestTable.php` for Schema helpers
4. Create `tests/Traits/AssertsApiEnvelope.php` for API assertions
5. Refactor Feature tests to use new infrastructure
6. Add `tests/Feature/TestInfrastructureTest.php` to validate the infrastructure
7. Run all tests, verify zero failures and zero warnings

## Database Changes

_(none — test-only changes)_

## API Changes

_(none — test-only changes)_

## Test Plan

### Unit Tests

- [x] Existing unit tests continue to pass unchanged

### Feature Tests

- [x] Existing feature tests pass after refactoring to use new traits
- [x] TestInfrastructureTest validates: edition helpers, context cleanup, trait test table, API envelope assertions

## Validation Checklist

- [x] All tests pass (`php artisan test`)
- [x] PSR-12 compliant
- [ ] Activity logging on state changes — N/A (no state changes)
- [ ] API responses use `{ data, meta, errors }` envelope — N/A (no new endpoints)
- [ ] Form Request validation on all inputs — N/A
- [ ] ULIDs for primary keys — N/A
- [ ] BelongsToApiary/BelongsToHive traits — N/A
- [x] No credentials logged in plaintext

## Test Evidence

```
  Tests:    96 passed (218 assertions)
  Duration: 0.91s
```

Before TASK-004: 34 passed, 1 failed, 50 warnings.
After TASK-004: 96 passed, 0 failed, 0 warnings.

New tests added: 11 (TestInfrastructureTest)
Tests refactored: Feature/BelongsToApiaryTest, Feature/BelongsToHiveTest, Unit/BelongsToApiaryTest, Unit/BelongsToHiveTest
