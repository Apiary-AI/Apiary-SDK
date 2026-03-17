# TASK-125: Persona Versioning API (list, diff, rollback)

## Status
⬜ Pending

## Branch
`task/125-persona-versioning-api`

## PR
_Not yet created_

## Depends On
- TASK-124 ✅ (Persona management API)

## Blocks
- TASK-130: Dashboard version history + diff view

## Edition Scope
Both CE and Cloud (core feature)

## Objective
Add dashboard endpoints for persona version management: list all versions, view a specific version, diff between versions, rollback to a previous version, and promote (activate) a specific version.

## Deliverables
1. Five new methods on PersonaDashboardController: listVersions, showVersion, diff, rollback, promote
2. Routes registered under /dashboard/agents/{agent}/persona/
3. Feature tests covering all endpoints
4. TASKS.md updated with task 124 marked done

## Acceptance Criteria
- [ ] List versions returns all versions in descending order with summary format
- [ ] Show version returns full persona data for a specific version
- [ ] Diff returns document-level changes between two versions
- [ ] Rollback creates a new version with old content (history preserved)
- [ ] Promote activates a specific version and updates agent.persona_version
- [ ] All endpoints use { data, meta, errors } envelope
- [ ] Validation errors return 422, missing versions return 404
- [ ] All tests pass
