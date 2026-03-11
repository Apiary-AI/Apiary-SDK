# TASK-041 — Agent-Writable Connectors

**Status:** In Progress
**Branch:** `task/041-agent-writable-connectors`
**Depends On:** TASK-038 (Connector Interface + Base Class)

---

## Objective

Enable agents with the `manage:connectors` permission to register, update, list, and delete custom connectors at runtime via the API. Custom connectors use a `CustomConnector` class that provides configurable HMAC webhook validation and header-based event parsing without requiring PHP code.

## Requirements

### 1. CustomConnector (`app/Connectors/CustomConnector.php`)

- Extends `BaseConnector`
- `type()` and `name()` return values from constructor-injected config
- Configurable webhook validation via HMAC (header name, secret key in auth_config, algorithm)
- Configurable event parsing: extract event type from a configurable header or JSON path
- `supportsWebhooks()` driven by config (defaults to `true`)
- `configurationRules()` returns rules based on config

### 2. Migration: Add `config` column to connectors table

- Add nullable JSON `config` column to `connectors` table
- Stores custom connector settings: `webhook_header`, `signature_header`, `signature_algo`, `event_header`, `event_json_path`

### 3. Connector API Controller (`app/Http/Controllers/Api/ConnectorController.php`)

- `index()` — List all connectors for the apiary (authenticated)
- `store()` — Register a custom connector (requires `manage:connectors`)
- `show()` — Get a single connector by ID (authenticated)
- `update()` — Update a custom connector (requires `manage:connectors`, not builtin)
- `destroy()` — Delete a custom connector (requires `manage:connectors`, not builtin)

### 4. Form Requests

- `StoreConnectorRequest` — Validates type, name, config fields
- `UpdateConnectorRequest` — Validates updatable fields (name, config)

### 5. API Routes

- `GET    /api/v1/connectors` — List connectors
- `POST   /api/v1/connectors` — Create connector
- `GET    /api/v1/connectors/{connector}` — Show connector
- `PUT    /api/v1/connectors/{connector}` — Update connector
- `DELETE /api/v1/connectors/{connector}` — Delete connector

### 6. Model Updates

- Add `config` to Connector model `$fillable` and cast as `array`
- Add `isCustom()` helper

## Test Plan

### Feature Tests (`tests/Feature/ConnectorApiTest.php`)

- List connectors: returns all apiary connectors
- List connectors: requires authentication
- Create connector: succeeds with `manage:connectors` permission
- Create connector: fails without `manage:connectors` permission (403)
- Create connector: validates required fields (422)
- Create connector: rejects duplicate type per apiary (409)
- Create connector: sets `created_by` to agent ID
- Create connector: sets `is_builtin` to false
- Show connector: returns connector details
- Show connector: returns 404 for non-existent connector
- Update connector: succeeds for custom connector
- Update connector: rejects update of builtin connector (403)
- Update connector: rejects update without permission (403)
- Delete connector: succeeds for custom connector
- Delete connector: rejects delete of builtin connector (403)
- Delete connector: rejects delete without permission (403)
- Activity logging on create, update, delete

### Unit Tests (`tests/Unit/CustomConnectorTest.php`)

- `type()` returns configured type
- `name()` returns configured name
- `supportsWebhooks()` returns configured value
- Webhook validation: valid HMAC signature
- Webhook validation: invalid signature
- Webhook validation: missing header
- Event parsing: from header
- Event parsing: from JSON path
- Event parsing: fallback to 'unknown'
- `configurationRules()` returns empty array (agent-defined connectors don't enforce auth_config shape)

## Files Changed

- `app/Connectors/CustomConnector.php` (new)
- `app/Http/Controllers/Api/ConnectorController.php` (new)
- `app/Http/Requests/StoreConnectorRequest.php` (new)
- `app/Http/Requests/UpdateConnectorRequest.php` (new)
- `database/migrations/..._add_config_to_connectors_table.php` (new)
- `app/Models/Connector.php` (edit — add config field, isCustom helper)
- `routes/api.php` (edit — add connector routes)
- `tests/Feature/ConnectorApiTest.php` (new)
- `tests/Unit/CustomConnectorTest.php` (new)
- `docs/tasks/TASK-041-agent-writable-connectors.md` (new)
