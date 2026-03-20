# TASK-131: Document Locking Enforcement

## Status
⬜ Pending

## Branch
`task/131-document-locking-enforcement`

## PR
_Not yet created_

## Depends On
- TASK-124 ✅ (Persona Management API)
- TASK-126 ✅ (Persona SDK API)

## Blocks
- TASK-138: Agent self-update (MEMORY document)

## Edition Scope
Both CE and Cloud (core feature)

## Objective
Complete the document locking enforcement surface by adding lock checks to the
rollback operation. Tasks 124 and 126 implement locking for CRUD and single-document
updates; this task closes the remaining bypass vector: `PersonaService::rollback()`
currently calls `createPersona()` directly without checking whether the target
version would modify any locked documents in the current active persona.

## Deliverables
1. `PersonaService::assertRollbackLocks()` private helper — mirrors the three
   checks from `PersonaDashboardController::enforceFullUpdateLocks()` but applied
   to the current-active → target-version transition
2. Call `assertRollbackLocks()` inside `PersonaService::rollback()` within the
   transaction, after `$previousActive` is fetched, before `createPersona()` runs
3. `PersonaDashboardController::rollback()` catches `PersonaDocumentLockedException`
   and returns 403 with `document_locked` error code
4. `PersonaServiceTest` — `test_rollback_enforces_lock_for_changed_document()`
5. `PersonaVersioningDashboardTest` — `test_rollback_blocked_by_document_lock()`

## Acceptance Criteria
- [ ] Rollback to a version with different content for a locked document returns 403
      when the editor type is excluded by `editable_by`
- [ ] Rollback to a version that removes a locked document returns 403
- [ ] Rollback to a version with different `lock_policy` for a locked document returns 403
- [ ] Rollback that does not touch any locked document succeeds as before
- [ ] Humans can rollback locked documents by default (only blocked when `editable_by`
      explicitly excludes `human`)
- [ ] `PersonaDocumentLockedException` is caught in the controller and returns
      `{ errors: [{ code: "document_locked" }] }` with HTTP 403
- [ ] All tests pass

## Test Plan
- Service-level: `test_rollback_enforces_lock_for_changed_document` —
  create persona with `RULES` locked and `editable_by: ['agent']`, create v2 with
  different RULES content, rollback to v1 as human → expect `PersonaDocumentLockedException`
- Service-level: `test_rollback_allows_when_no_locked_docs_change` —
  rollback where only unlocked documents differ → succeeds
- Dashboard-level: `test_rollback_blocked_by_document_lock` —
  POST /dashboard/agents/{id}/persona/rollback → expects 403 with `document_locked`
