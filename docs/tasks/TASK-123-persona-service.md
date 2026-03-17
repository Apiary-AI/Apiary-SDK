# TASK-123: Persona Service (create, version, activate)

## Status
⬜ Pending

## Branch
`task/123-persona-service`

## PR
_Not yet created_

## Depends On
- TASK-122 ✅ (Agent persona migration + model)

## Blocks
- TASK-124: Persona management API (CRUD)
- TASK-126: Persona SDK API (agent-auth, self-fetch)
- TASK-133: Persona templates (built-in starter templates)

## Edition Scope
Both CE and Cloud (core feature)

## Objective
Create the `PersonaService` that encapsulates all business logic for persona lifecycle management: creating personas with automatic versioning, activating specific versions, rolling back, updating single documents and config, enforcing document lock policies, and computing diffs between versions.

## Deliverables
1. `PersonaService` with methods: createPersona, activateVersion, rollback, updateSingleDocument, updateConfig, assertDocumentEditable, diffVersions, getActivePersona, getVersion, listVersions
2. `PersonaDocumentLockedException` for lock policy enforcement
3. Feature tests covering all service methods, change tracking, locking, activity logging, and edge cases

## Acceptance Criteria
- [ ] Creating a persona auto-increments version numbers
- [ ] Only one active persona per agent at any time (atomic switch in transaction)
- [ ] Changes array correctly tracks created/modified/removed/unchanged documents
- [ ] Agent.persona_version updated for auto policy, not for manual policy
- [ ] Rollback creates a new version with old content (history preserved)
- [ ] Document lock enforcement respects lock_policy and editable_by
- [ ] Activity log entries created for version_created, version_activated, rollback
- [ ] All tests pass
- [ ] Code follows PSR-12 standards
