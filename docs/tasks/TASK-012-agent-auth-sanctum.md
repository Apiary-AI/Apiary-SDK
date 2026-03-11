# TASK-012: Agent Authentication (Sanctum)

**Status:** done
**Branch:** `task/012-agent-auth-sanctum`
**PR:** —
**Depends on:** TASK-007
**Blocks:** TASK-013, TASK-014, TASK-016, TASK-020

## Objective

Implement Agent authentication using Laravel Sanctum, enabling agents to authenticate via API tokens for secure outbound polling. Agents never receive inbound connections — they authenticate once and poll for work.

## Requirements

### Functional

- [ ] FR-1: Agents can obtain API token via registration/login endpoint
- [ ] FR-2: Tokens are stored securely (hashed) and revocable
- [ ] FR-3: Authenticated agents can access only their hive-scoped resources
- [ ] FR-4: Token expiration support (optional long-lived tokens for agents)
- [ ] FR-5: Agents can revoke their own tokens

### Non-Functional

- [ ] NFR-1: No credentials logged in plaintext
- [ ] NFR-2: Token format: secure random (Sanctum default or custom)
- [ ] NFR-3: Rate limiting on auth endpoints to prevent abuse

## Architecture & Design

### Files to Create / Modify

| Action | Path | Purpose |
|--------|------|---------|
| Modify | `app/Models/Agent.php` | Add HasApiTokens trait |
| Create | `app/Http/Requests/AgentAuthRequest.php` | Form request validation |
| Create | `app/Http/Controllers/Api/AgentAuthController.php` | Auth endpoints |
| Modify | `routes/api.php` | Add auth routes |
| Modify | `config/auth.php` | Add agent guard/provider |
| Create | `database/migrations/*_add_sanctum_to_agents_table.php` | Token columns |

### Key Design Decisions

- **Sanctum for agents**: Laravel Sanctum provides simple token management with hashed tokens stored in `personal_access_tokens` table
- **Hive-scoped tokens**: Each token is associated with an agent, and agents are already hive-scoped via `BelongsToHive` trait
- **Token abilities**: Future-proof with ability system for granular permissions (read tasks, write tasks, etc.)
- **No inbound connections**: Agents authenticate once and poll — tokens never expire by default (agent lifecycle manages validity)

## Implementation Plan

1. Install Sanctum if not present: `composer require laravel/sanctum`
2. Publish Sanctum config and migrations
3. Add `HasApiTokens` trait to `Agent` model
4. Create `AgentAuthController` with `register` and `login` endpoints
5. Create `AgentAuthRequest` for input validation
6. Configure `auth.php` with agent guard
7. Add API routes for agent auth
8. Add token revocation endpoint
9. Write tests

## API Changes

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/agents/register` | Register new agent, returns token |
| POST | `/api/v1/agents/login` | Login existing agent, returns token |
| POST | `/api/v1/agents/logout` | Revoke current token |
| GET | `/api/v1/agents/me` | Returns authenticated agent info |

## Test Plan

### Unit Tests

- [ ] Agent can generate API token
- [ ] Token is hashed (not stored plaintext)

### Feature Tests

- [ ] Registration creates agent and returns token
- [ ] Login with valid credentials returns token
- [ ] Login with invalid credentials fails
- [ ] Authenticated request with token accesses hive-scoped data
- [ ] Revoked token cannot access API

## Validation Checklist

- [ ] All tests pass (`php artisan test`)
- [ ] PSR-12 compliant
- [ ] Activity logging on token creation/revocation
- [ ] API responses use `{ data, meta, errors }` envelope
- [ ] Form Request validation on all inputs
- [ ] No credentials logged in plaintext
