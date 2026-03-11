# TASK-077 — Retry with Exponential Backoff (RetryBackoffService)

**Status:** Done
**Depends On:** TASK-074
**Branch:** `task/077-retry-backoff-service`

## Summary

Extract retry backoff calculation from `Task::retryBackoffSeconds()` into a
dedicated stateless `RetryBackoffService`, add configurable jitter support
(±25%), and integrate it back into the existing retry flow.

## What Changed

### New: `RetryBackoffService`

Stateless service at `app/Services/RetryBackoffService.php` with:

- **Strategies:** `none`, `fixed`, `exponential` (matches existing constants)
- **Parameters:** `strategy`, `retryCount`, `base`, `max`, `factor` (default 2.0), `jitter`
- **Jitter:** ±25% uniform random when enabled; always >= 1 when input > 0

### Integration

`Task::retryBackoffSeconds()` now delegates to `RetryBackoffService`:

- **Legacy tasks** (no `failure_policy`): exponential with config `retry_backoff`,
  no jitter, no cap — preserves original deterministic behavior.
- **Failure-policy tasks**: uses policy `retry_delay` / `retry_delay_base` /
  `retry_delay_max` / `retry_jitter` with jitter enabled by default.

### New: `retry_jitter` failure_policy key

- Type: `boolean`, optional
- Default: `true` for failure_policy tasks
- When `false`, backoff is deterministic (useful for testing / predictable scheduling)
- Accepted in both `CreateTaskRequest` and `RequeueTaskRequest`

### SDK Parity

- [x] API contract change assessed — `retry_jitter` added as optional boolean
- [x] Shell SDK — no changes needed (backoff is server-side)
- [x] Python SDK — no changes needed (backoff is server-side)
- [x] Validation updated in CreateTaskRequest and RequeueTaskRequest

## Files Changed

| File | Change |
|------|--------|
| `app/Services/RetryBackoffService.php` | New service |
| `app/Models/Task.php` | Delegates to RetryBackoffService |
| `app/Http/Requests/CreateTaskRequest.php` | Added `retry_jitter` validation + allowlist |
| `app/Http/Requests/RequeueTaskRequest.php` | Added `retry_jitter` validation + allowlist |
| `tests/Unit/RetryBackoffServiceTest.php` | 23 unit tests |
| `tests/Feature/TaskFailurePolicyTest.php` | Updated 4 tests with `retry_jitter: false` |

## Test Coverage

- Strategy: none / fixed / exponential progression
- Max cap enforcement
- Custom factor support
- Jitter bounds (±25%)
- Jitter toggle (enabled/disabled)
- Edge cases (zero base, zero max, unknown strategy)
- Backward compatibility with legacy `Task::retryBackoffSeconds()`
- Full test suite passes (3295 tests)
