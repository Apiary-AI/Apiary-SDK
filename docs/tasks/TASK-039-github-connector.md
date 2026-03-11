# TASK-039 — GitHub Connector

**Status:** In Progress
**Branch:** `task/039-github-connector`
**Depends On:** TASK-038 (Connector Interface + Base Class)

---

## Objective

Implement a concrete `GitHubConnector` class that extends `BaseConnector`, providing GitHub webhook validation (HMAC-SHA256), webhook parsing for common GitHub events, and `auth_config` validation rules for GitHub service connections.

## Requirements

### 1. GitHubConnector (`app/Connectors/GitHubConnector.php`)

- Extends `BaseConnector`
- `type()` returns `'github'`
- `name()` returns `'GitHub'`
- `supportsWebhooks()` inherits default `true` from `BaseConnector`

### 2. Webhook Validation

- Validates `X-Hub-Signature-256` header using HMAC-SHA256
- Secret sourced from `ServiceConnection->auth_config['webhook_secret']`
- Constant-time comparison via `hash_equals()`
- Returns `false` when header is missing or signature mismatch

### 3. Webhook Parsing

- Reads `X-GitHub-Event` header for event type
- Normalizes event + action into dot-notation (e.g., `pull_request.opened`)
- Returns `['event' => string, 'payload' => array]` per interface contract
- Extracts common fields: `repository`, `sender`, `action` into payload
- Falls back gracefully when optional fields are missing

### 4. Configuration Rules

- `configurationRules()` returns Laravel validation rules for:
  - `token` — required string (personal access token or app token)
  - `webhook_secret` — nullable string (for webhook signature verification)

### 5. Seeder Registration

- Register the GitHub connector as a built-in connector in the connectors table via a seeder or the existing database seeder.

## Test Plan

### Unit Tests (`tests/Unit/GitHubConnectorTest.php`)

- `type()` returns `'github'`
- `name()` returns `'GitHub'`
- `supportsWebhooks()` returns `true`
- `configurationRules()` returns expected validation shape
- Webhook validation: valid HMAC-SHA256 signature → `true`
- Webhook validation: invalid signature → `false`
- Webhook validation: missing header → `false`
- Webhook validation: missing `webhook_secret` in auth_config → `false`
- Webhook parsing: push event → `['event' => 'push', 'payload' => ...]`
- Webhook parsing: pull_request event with action → `['event' => 'pull_request.opened', ...]`
- Webhook parsing: missing event header → `['event' => 'unknown', ...]`
- Webhook parsing: extracts repository, sender, action fields

## Files Changed

- `app/Connectors/GitHubConnector.php` (new)
- `tests/Unit/GitHubConnectorTest.php` (new)
- `docs/tasks/TASK-039-github-connector.md` (new)
