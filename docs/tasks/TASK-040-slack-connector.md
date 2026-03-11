# TASK-040 — Slack Connector

**Status:** In Progress
**Branch:** `task/040-slack-connector`
**Depends On:** TASK-038 (Connector Interface + Base Class)

---

## Objective

Implement a concrete `SlackConnector` class that extends `BaseConnector`, providing Slack webhook signature validation (HMAC-SHA256 with `v0=` prefix and timestamp), webhook parsing for Slack Events API payloads, and `auth_config` validation rules for Slack service connections.

## Requirements

### 1. SlackConnector (`app/Connectors/SlackConnector.php`)

- Extends `BaseConnector`
- `type()` returns `'slack'`
- `name()` returns `'Slack'`
- `supportsWebhooks()` inherits default `true` from `BaseConnector`

### 2. Webhook Validation

- Validates `X-Slack-Signature` header using HMAC-SHA256
- Constructs signature base string: `v0:{timestamp}:{body}`
- Reads timestamp from `X-Slack-Request-Timestamp` header
- Rejects requests with stale timestamps (older than 5 minutes) to prevent replay attacks
- Secret sourced from `ServiceConnection->auth_config['signing_secret']` with fallback to legacy `webhook_secret` column
- Constant-time comparison via `hash_equals()`
- Returns `false` when headers are missing, signature mismatches, or secret is unavailable

### 3. Webhook Parsing

- Reads event type from JSON body: `event.type` for Events API, `type` for top-level payloads
- Normalizes into dot-notation where applicable (e.g., `event_callback.message`)
- Returns `['event' => string, 'payload' => array]` per interface contract
- Extracts common fields: `team_id`, `event.user`, `event.channel` into payload
- Falls back gracefully when optional fields are missing
- Handles `url_verification` challenge events

### 4. Configuration Rules

- `configurationRules()` returns Laravel validation rules for:
  - `bot_token` — required string (Slack bot OAuth token)
  - `signing_secret` — required string (for webhook signature verification)

## Test Plan

### Unit Tests (`tests/Unit/SlackConnectorTest.php`)

- `type()` returns `'slack'`
- `name()` returns `'Slack'`
- `supportsWebhooks()` returns `true`
- `configurationRules()` returns expected validation shape
- Webhook validation: valid HMAC-SHA256 signature → `true`
- Webhook validation: valid signature via legacy webhook_secret → `true`
- Webhook validation: prefers auth_config over legacy field
- Webhook validation: invalid signature → `false`
- Webhook validation: missing signature header → `false`
- Webhook validation: missing timestamp header → `false`
- Webhook validation: missing signing_secret → `false`
- Webhook validation: stale timestamp → `false`
- Webhook parsing: `event_callback` with `message` event type
- Webhook parsing: `event_callback` with `app_mention` event type
- Webhook parsing: `url_verification` challenge
- Webhook parsing: missing event header defaults to `unknown`
- Webhook parsing: extracts team_id, user, channel fields
- Webhook parsing: preserves full body
- Webhook parsing: returns required keys
- Webhook parsing: ignores query parameters

## Files Changed

- `app/Connectors/SlackConnector.php` (new)
- `tests/Unit/SlackConnectorTest.php` (new)
- `docs/tasks/TASK-040-slack-connector.md` (new)
