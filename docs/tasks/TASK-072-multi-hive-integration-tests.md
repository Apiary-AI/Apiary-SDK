# TASK-072 — Multi-Hive Integration Tests

**Status:** In Progress
**Branch:** `task/072-multi-hive-integration-tests`
**Depends On:** 061, 062, 063, 064, 065, 066, 067, 068, 069

## Objective

Write a comprehensive integration test suite that validates the full multi-hive
platform working end-to-end: cross-hive task lifecycle, event publish/poll/replace
flows, apiary-scoped knowledge sharing, cross-apiary isolation, pagination edge
cases, and denial paths with malformed grants.

## Requirements

1. **Multi-hive task lifecycle** — Agent in Hive A creates a task targeting Hive B,
   agent in Hive B polls and claims it, completes it, verify provenance tracking.
2. **Cross-hive event publish/poll/replace** — Agent publishes apiary.* events,
   agents in other hives subscribe and poll them, replace subscriptions works.
3. **Apiary-scoped knowledge** — Agent writes apiary-scoped knowledge, agents
   in other hives can read it; hive-scoped knowledge stays isolated.
4. **Cross-apiary isolation** — Two apiaries with multiple hives each; agents
   from one apiary cannot see/access anything in the other.
5. **Pagination + realtime edge cases** — Event polling with seq-based cursors,
   has_more pagination, mixed hive/cross-hive event ordering.
6. **Denial paths & malformed grants** — Revoked permissions block access,
   expired cross-hive grants fail closed, malformed permission strings rejected.
7. **Cross-hive task controller** — List outbound/inbound cross-hive tasks,
   cancel pending cross-hive tasks.

## Test Plan

All tests in `tests/Feature/MultiHiveIntegrationTest.php`:

- `test_cross_hive_task_full_lifecycle`
- `test_cross_hive_event_publish_and_poll_flow`
- `test_event_subscription_replace_then_poll`
- `test_apiary_scoped_knowledge_visible_across_hives`
- `test_hive_scoped_knowledge_invisible_across_hives`
- `test_cross_apiary_total_isolation`
- `test_event_pagination_with_cursor_and_has_more`
- `test_revoked_permission_blocks_cross_hive_access`
- `test_malformed_cross_hive_grant_rejected`
- `test_cross_hive_task_list_outbound_inbound`
- `test_cross_hive_task_cancel`
- `test_inactive_hive_blocks_cross_hive_routing`
- `test_wildcard_permission_grants_full_cross_hive_access`

## Validation Checklist

- [ ] All tests pass (`php artisan test --filter=MultiHiveIntegrationTest`)
- [ ] Full suite passes (`php artisan test`)
- [ ] PSR-12 compliant (Pint)
- [ ] No duplicate coverage with existing test files
- [ ] Fail-closed semantics verified on every denial path
