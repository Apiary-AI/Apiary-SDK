# TASK-126: Persona SDK API (agent-auth, self-fetch)

## Status
⬜ Pending

## Branch
`task/126-persona-sdk-api`

## PR
_Not yet created_

## Depends On
- TASK-123 ✅ (Persona service)
- TASK-012 ✅ (Agent authentication)

## Blocks
- TASK-127: Python SDK persona methods
- TASK-128: Shell SDK persona methods
- TASK-131: Document locking enforcement
- TASK-132: Persona hot reload
- TASK-136: Token counter + cost estimate
- TASK-138: Agent self-update (MEMORY document)

## Edition Scope
Both CE and Cloud (core feature)

## Objective
Add agent-facing SDK API endpoints for persona self-fetch and self-update. These endpoints use agent Sanctum auth (not dashboard session auth) and return the policy-selected persona for the authenticated agent.

## Deliverables
1. `PersonaController` extending `ApiController` with 5 endpoints
2. Routes under /api/v1/persona with sanctum-agent middleware
3. Feature tests with agent token auth

## Acceptance Criteria
- [ ] GET /persona returns full active persona
- [ ] GET /persona/config returns config only
- [ ] GET /persona/documents/{name} returns single document content
- [ ] GET /persona/assembled returns pre-assembled system prompt in correct order
- [ ] PATCH /persona/documents/{name} allows agent self-update of unlocked documents
- [ ] PATCH rejects locked documents with 403
- [ ] All endpoints require agent auth (401 without token)
- [ ] All responses use { data, meta, errors } envelope
- [ ] All tests pass
