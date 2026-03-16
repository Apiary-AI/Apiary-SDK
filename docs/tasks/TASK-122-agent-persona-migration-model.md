# TASK-122: Agent Persona Migration + Model

## Status
⬜ Pending

## Branch
`task/122-agent-persona-migration-model`

## PR
_Not yet created_

## Depends On
- TASK-121 ✅ (Phase 5C task breakdown)

## Blocks
- TASK-123: PersonaService (CRUD + versioning logic)
- TASK-124: Persona API endpoints
- TASK-125: Persona dashboard editor
- All tasks 126–138

## Edition Scope
Both CE and Cloud (core feature)

## Objective
Create the `agent_personas` database table, `AgentPersona` Eloquent model, update the `Agent` model with persona relationships, and provide a factory for testing. This is the data foundation for the entire Agent Persona feature (Phase 5C).

## Architecture Fit
- Uses ULID primary keys (HasUlid trait)
- Uses BelongsToHive trait for hive/apiary scoping
- Persona versions are immutable snapshots (no updated_at)
- Follows existing model patterns (Agent, Task, etc.)

## Deliverables
1. Migration: `agent_personas` table with JSONB documents, config, lock_policy
2. Migration: Add `persona_version`, `persona_update_policy`, `persona_pinned_version` to `agents`
3. `AgentPersona` model with constants, casts, relationships, scopes, helpers
4. `AgentPersonaFactory` with state builders
5. Updated `Agent` model with persona relationships and constants
6. Feature tests covering model, relationships, scopes, constraints, factory

## Acceptance Criteria
- [ ] Migrations run without errors
- [ ] `agent_personas` table has all columns per spec §11
- [ ] Unique constraint on `(agent_id, version)` enforced
- [ ] Cascade delete: deleting agent removes all persona versions
- [ ] `AgentPersona` model uses BelongsToHive + HasUlid traits
- [ ] Document helpers (`getDocument`, `getDocumentNames`, `isDocumentLocked`) work correctly
- [ ] `Agent` model has `personas()`, `activePersona()` relationships
- [ ] Factory creates valid persona records with all state builders
- [ ] All tests pass: `php artisan test --filter=AgentPersonaModelTest`
- [ ] Full test suite passes: `php artisan test`
- [ ] Code follows PSR-12 standards
