# TASK-124: Persona Management API (CRUD)

## Status
⬜ Pending

## Branch
`task/124-persona-management-api`

## PR
_Not yet created_

## Depends On
- TASK-123 ✅ (Persona service)
- TASK-012 ✅ (Agent authentication)
- TASK-013 ✅ (Permission middleware)

## Blocks
- TASK-125: Persona versioning API (list, diff, rollback)
- TASK-129: Dashboard persona editor page
- TASK-131: Document locking enforcement

## Edition Scope
Both CE and Cloud (core feature)

## Objective
Add dashboard-facing HTTP endpoints for persona CRUD: get active persona, create/update full persona, update single document, update config. Uses the { data, meta, errors } JSON envelope pattern.

## Deliverables
1. `PersonaDashboardController` with show, update, updateDocument, updateConfig methods
2. Routes registered under /dashboard/agents/{agent}/persona
3. Request validation for all endpoints
4. Feature tests covering CRUD, validation, change tracking, auth, and envelope format

## Acceptance Criteria
- [ ] GET returns active persona with full data envelope
- [ ] PUT creates new persona version with change summary
- [ ] PATCH document updates single document, preserves others
- [ ] PATCH config updates config only, preserves documents
- [ ] Invalid document names return 422
- [ ] Missing active persona returns appropriate error
- [ ] created_by_type set to 'human' on all dashboard endpoints
- [ ] Activity log entries created
- [ ] All tests pass
