# Agent Authentication

Apiary uses [Laravel Sanctum](https://laravel.com/docs/sanctum) to authenticate
agents via API tokens. Every agent registers with a **secret**, receives a
**bearer token**, and includes that token in subsequent API requests. This page
covers the full auth lifecycle, endpoint reference, security model, and
troubleshooting tips.

## Architecture Overview

```text
Agent (external process)              Apiary Platform
─────────────────────────             ──────────────────
                                      ┌──────────────────┐
  1. POST /register ───────────────►  │ AgentAuthController│
     { name, hive_id, secret }        │   register()      │
                                      │                   │
  ◄─── 201 { agent, token } ────────  │  • bcrypt secret  │
                                      │  • Sanctum token  │
  2. GET /me ──────────────────────►  │   me()            │
     Authorization: Bearer <token>    │  • guard: sanctum │
                                      │  • resolve agent  │
  ◄─── 200 { agent data } ──────────  └──────────────────┘
                                               │
  3. Poll /tasks?status=pending ──►            │
     Authorization: Bearer <token>        (hive-scoped)
```

**Key design decisions:**

| Decision | Rationale |
|----------|-----------|
| Sanctum bearer tokens | Laravel-native, auditable, hashed storage, ability-based scoping |
| Bcrypt for agent secrets | One-way hash; secret never stored in plaintext |
| SHA-256 for bearer tokens | Sanctum default; token in `personal_access_tokens` is a hash |
| No token expiration by default | Agents poll continuously; tokens are revocable on demand |
| Separate `sanctum-agent` guard | Isolates agent auth from dashboard (session) auth |

### Two Layers of Hashing

Apiary stores **two** hashed values per agent:

1. **`agents.api_token_hash`** — bcrypt hash of the agent's registration
   **secret**. Used during `/login` to verify identity.
2. **`personal_access_tokens.token`** — SHA-256 hash of the Sanctum bearer
   **token**. Used on every authenticated request to resolve the agent.

Neither the secret nor the bearer token is ever stored in plaintext.

## Endpoints

All endpoints live under the `/api/v1/agents` prefix.

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `POST` | `/register` | None | Create agent and receive token |
| `POST` | `/login` | None | Authenticate and receive new token |
| `POST` | `/logout` | Bearer | Revoke current token |
| `GET`  | `/me` | Bearer | Return authenticated agent info |

### POST /api/v1/agents/register

Create a new agent in a hive and receive a Sanctum bearer token.

**Request:**

```json
{
  "name": "DeployBot",
  "hive_id": "01JFWXYZ01JFWXYZ01JFWXYZ01",
  "secret": "my-secret-at-least-16-chars",
  "type": "deployment",
  "capabilities": ["deploy", "rollback"],
  "metadata": { "version": "1.0" }
}
```

| Field | Type | Required | Rules |
|-------|------|----------|-------|
| `name` | string | Yes | max 255 characters |
| `hive_id` | string | Yes | 26-character ULID, must exist in `hives` |
| `secret` | string | Yes | 16–255 characters |
| `type` | string | No | max 100 characters (default: `custom`) |
| `capabilities` | string[] | No | array of strings, each max 255 chars |
| `metadata` | object | No | arbitrary key-value pairs |

**Response — 201 Created:**

```json
{
  "data": {
    "agent": {
      "id": "01JFZ123ABC456DEF789GHI012",
      "name": "DeployBot",
      "type": "deployment",
      "hive_id": "01JFWXYZ01JFWXYZ01JFWXYZ01",
      "apiary_id": "01JFQABC01JFQABC01JFQABC01",
      "status": "offline",
      "capabilities": ["deploy", "rollback"]
    },
    "token": "1|abc123def456ghi789..."
  },
  "meta": {},
  "errors": null
}
```

::: tip
Store the `token` value immediately — it is shown only once. Apiary stores
only a SHA-256 hash internally.
:::

### POST /api/v1/agents/login

Authenticate with `agent_id` + `secret` and receive a **new** bearer token.
Each login creates an additional token; previous tokens remain valid until
explicitly revoked.

**Request:**

```json
{
  "agent_id": "01JFZ123ABC456DEF789GHI012",
  "secret": "my-secret-at-least-16-chars"
}
```

| Field | Type | Required | Rules |
|-------|------|----------|-------|
| `agent_id` | string | Yes | 26-character ULID |
| `secret` | string | Yes | string |

**Response — 200 OK:**

```json
{
  "data": {
    "agent": {
      "id": "01JFZ123ABC456DEF789GHI012",
      "name": "DeployBot",
      "type": "deployment",
      "hive_id": "01JFWXYZ01JFWXYZ01JFWXYZ01",
      "apiary_id": "01JFQABC01JFQABC01JFQABC01",
      "status": "offline"
    },
    "token": "2|xyz789uvw012..."
  },
  "meta": {},
  "errors": null
}
```

**Error — 401 Unauthorized** (bad credentials):

```json
{
  "data": null,
  "meta": {},
  "errors": [
    {
      "message": "Invalid credentials.",
      "code": "auth_failed"
    }
  ]
}
```

### GET /api/v1/agents/me

Return profile data for the currently authenticated agent.

**Request:**

```http
GET /api/v1/agents/me
Authorization: Bearer 1|abc123def456ghi789...
```

**Response — 200 OK:**

```json
{
  "data": {
    "id": "01JFZ123ABC456DEF789GHI012",
    "name": "DeployBot",
    "type": "deployment",
    "hive_id": "01JFWXYZ01JFWXYZ01JFWXYZ01",
    "apiary_id": "01JFQABC01JFQABC01JFQABC01",
    "status": "offline",
    "capabilities": ["deploy", "rollback"],
    "metadata": { "version": "1.0" },
    "last_heartbeat": "2026-02-24T00:48:22Z"
  },
  "meta": {},
  "errors": null
}
```

### POST /api/v1/agents/logout

Revoke the token used in the current request. Other tokens for the same agent
remain valid.

**Request:**

```http
POST /api/v1/agents/logout
Authorization: Bearer 1|abc123def456ghi789...
```

**Response — 204 No Content** (empty body)

After logout, the revoked token returns `401` on any subsequent request.

## Auth Flow for Polling Agents

Apiary agents **never receive inbound connections** — they poll outbound.
A typical agent lifecycle looks like this:

```text
1. Agent starts up
2. POST /api/v1/agents/register   (first run)
   — or —
   POST /api/v1/agents/login      (subsequent runs)
3. Store bearer token in memory
4. Loop:
     GET  /api/v1/agents/me         (health check / heartbeat)
     GET  /api/v1/tasks?status=pending  (claim work)
     POST /api/v1/tasks/{id}/claim
     ... perform work ...
     PUT  /api/v1/tasks/{id}/result
5. POST /api/v1/agents/logout      (graceful shutdown)
```

### Example: Python Agent Bootstrap

```python
import requests

BASE = "https://apiary.example.com/api/v1/agents"

# First run — register
resp = requests.post(f"{BASE}/register", json={
    "name": "my-agent",
    "hive_id": "01JFWXYZ01JFWXYZ01JFWXYZ01",
    "secret": "a-very-strong-secret-here",
})
token = resp.json()["data"]["token"]

# Subsequent requests — use bearer token
headers = {"Authorization": f"Bearer {token}"}
me = requests.get(f"{BASE}/me", headers=headers)
print(me.json()["data"]["name"])  # "my-agent"
```

### Example: cURL

```bash
# Register
curl -X POST https://apiary.example.com/api/v1/agents/register \
  -H "Content-Type: application/json" \
  -d '{
    "name": "shell-agent",
    "hive_id": "01JFWXYZ01JFWXYZ01JFWXYZ01",
    "secret": "minimum-sixteen-chars"
  }'

# Use the returned token
TOKEN="1|abc123..."

# Check identity
curl https://apiary.example.com/api/v1/agents/me \
  -H "Authorization: Bearer $TOKEN"

# Logout
curl -X POST https://apiary.example.com/api/v1/agents/logout \
  -H "Authorization: Bearer $TOKEN"
```

## Token Lifecycle

### Creation

Tokens are created during **register** and **login**. Each call produces a new
independent token. An agent can hold multiple valid tokens simultaneously (e.g.
across restarts or parallel instances).

### Storage

| What | Where | Hash |
|------|-------|------|
| Agent secret | `agents.api_token_hash` | bcrypt |
| Bearer token | `personal_access_tokens.token` | SHA-256 |

The plaintext bearer token is returned exactly once in the register/login
response. Apiary never stores or logs it.

### Revocation

- **Single token:** `POST /logout` revokes the token used in the request.
- **All tokens:** Admins can revoke all tokens for an agent via the dashboard or
  by deleting rows from `personal_access_tokens` where `tokenable_id` matches
  the agent's ULID.
- **Immediate effect:** Revoked tokens return `401` on the next request — there
  is no grace period or cache.

### Expiration

By default, Sanctum tokens **do not expire**. This is intentional: agents are
long-running processes that poll continuously. Token validity is managed through
explicit revocation rather than time-based expiry.

To enable expiration, set `expiration` in `config/sanctum.php`:

```php
// Expire tokens after 24 hours (value in minutes)
'expiration' => 1440,
```

## Guard and Provider Configuration

Apiary defines a dedicated Sanctum guard for agents, separate from the
dashboard's session-based web guard.

**config/auth.php:**

```php
'guards' => [
    'web' => [
        'driver' => 'session',
        'provider' => 'users',
    ],
    'sanctum-agent' => [
        'driver' => 'sanctum',
        'provider' => 'agents',
    ],
],

'providers' => [
    'users' => [
        'driver' => 'eloquent',
        'model' => App\Models\User::class,
    ],
    'agents' => [
        'driver' => 'eloquent',
        'model' => App\Models\Agent::class,
    ],
],
```

Protected agent routes use the `auth:sanctum-agent` middleware:

```php
Route::prefix('v1/agents')
    ->middleware('auth:sanctum-agent')
    ->group(function () {
        Route::post('/logout', [AgentAuthController::class, 'logout']);
        Route::get('/me', [AgentAuthController::class, 'me']);
    });
```

The `Agent` model implements `Authenticatable` and uses the `HasApiTokens`
trait from Sanctum, enabling it to create and manage its own tokens.

## CE vs Cloud Behavior

| Aspect | Community Edition | Cloud Edition |
|--------|-------------------|---------------|
| Apiary | Single `default` apiary | Multi-tenant, per-org apiaries |
| Hive scoping | All agents in `default` hive (or explicitly created hives) | Agents scoped to tenant's hives |
| Token isolation | Tokens belong to one agent | Same — tokens belong to one agent |
| Registration | Open (no invite required) | May require org-level invitation (future) |
| Dashboard auth | Session-based (web guard) | Session-based (web guard) |
| Agent auth | Sanctum bearer tokens | Sanctum bearer tokens |

The agent authentication API is **identical** in both editions. The only
difference is the organizational context: CE resolves to a single default
apiary, while Cloud scopes agents to the tenant's apiary.

## Activity Logging

Every authentication event is recorded in the
[activity log](./activity-log.md):

| Action | Logged On | Details |
|--------|-----------|---------|
| `agent.registered` | Register | `{ token_name: "agent-api" }` |
| `agent.login` | Login | `{ token_name: "agent-api" }` |
| `agent.logout` | Logout | `{ token_id: <int> }` |

All entries include `apiary_id`, `hive_id`, and `agent_id` context for
audit filtering. See the
[ActivityLogger Service](./activity-logger.md) guide for the fluent API used
internally.

## Common Pitfalls and Troubleshooting

### 401 Unauthorized on /me or /logout

| Cause | Fix |
|-------|-----|
| Missing `Authorization` header | Add `Authorization: Bearer <token>` to every request |
| Malformed header | Ensure format is exactly `Bearer <token>` (capital B, single space) |
| Token was revoked (logout) | Call `/login` again to obtain a new token |
| Token does not exist in DB | Re-register or re-login; the token may have been manually deleted |
| Wrong guard middleware | Ensure route uses `auth:sanctum-agent`, not `auth:sanctum` |

### 401 on /login — "Invalid credentials"

| Cause | Fix |
|-------|-----|
| Wrong `agent_id` | Verify the ULID is exactly 26 characters and matches the registered agent |
| Wrong `secret` | The secret must match what was provided at registration (case-sensitive) |
| Agent was deleted | Re-register the agent |

### 403 Forbidden

A `403` means the agent authenticated successfully but lacks permission for the
requested action. This is enforced by the policy engine, not by auth. Check:

- Agent permissions in the dashboard
- Hive-scoping — the agent may be in a different hive than the resource
- Cross-hive permissions if accessing resources outside the agent's home hive

### 422 Validation Errors

Registration returns `422` when request data fails validation:

```json
{
  "data": null,
  "meta": {},
  "errors": [
    { "message": "The name field is required.", "code": "validation_error", "field": "name" },
    { "message": "The secret field must be at least 16 characters.", "code": "validation_error", "field": "secret" }
  ]
}
```

Common validation issues:

| Field | Rule | Common Mistake |
|-------|------|----------------|
| `name` | required, max 255 | Empty or missing |
| `hive_id` | 26-char ULID, must exist | Wrong length, non-existent hive |
| `secret` | min 16 characters | Too short — use a strong passphrase or generated key |

### Token Shown Only Once

The plaintext bearer token is returned **only** in the register/login response.
If lost, call `/login` again to generate a new token. The old token remains
valid until revoked.

### Multiple Tokens per Agent

Each `/login` call creates a **new** token without revoking previous ones. This
is by design — it allows parallel agent instances to hold independent tokens.
To clean up stale tokens, revoke them via `/logout` or the admin dashboard.

## Testing and Validation

The test suite for agent authentication is in
`tests/Feature/AgentAuthTest.php`. It covers:

- **Registration flow** — agent creation, token issuance, hashed storage
- **Login flow** — credential verification, new token per login
- **Protected endpoints** — 401 without token, 401 with invalid token
- **Logout and revocation** — token invalidation, isolation between tokens
- **Activity logging** — correct action strings and metadata
- **Response format** — API envelope structure (`{ data, meta, errors }`)
- **Security** — secret bcrypt-hashed in DB, token SHA-256-hashed in DB

Run the auth tests:

```bash
php artisan test --filter=AgentAuthTest
```

Run the full test suite:

```bash
php artisan test
```

### Writing Tests for Authenticated Agent Requests

When writing feature tests that require an authenticated agent, use Sanctum's
`actingAs` helper:

```php
use Laravel\Sanctum\Sanctum;

// Create and authenticate an agent
$agent = Agent::factory()->create();
Sanctum::actingAs($agent, ['*'], 'sanctum-agent');

// Now make authenticated requests
$response = $this->getJson('/api/v1/agents/me');
$response->assertOk();
```

Alternatively, register an agent via the API and use the returned token:

```php
$response = $this->postJson('/api/v1/agents/register', [
    'name' => 'TestBot',
    'hive_id' => $hive->id,
    'secret' => 'test-secret-minimum-16',
]);

$token = $response->json('data.token');

$this->getJson('/api/v1/agents/me', [
    'Authorization' => "Bearer {$token}",
])->assertOk();
```
