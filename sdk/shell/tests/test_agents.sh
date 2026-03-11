#!/usr/bin/env bash
# test_agents.sh — Agent auth and lifecycle endpoint tests.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test_harness.sh"
source "${SCRIPT_DIR}/../src/apiary-sdk.sh"

export APIARY_BASE_URL="http://localhost:9999"
export APIARY_DEBUG=0

HIVE="HHHHHHHHHHHHHHHHHHHHHHHHHH"

# ── Register ─────────────────────────────────────────────────────

describe "apiary_register"

mock_reset
mock_response POST "/api/v1/agents/register" 200 \
    '{"data":{"agent":{"id":"agent-1","name":"my-bot","type":"custom","hive_id":"'"$HIVE"'"},"token":"tok-123"},"meta":{},"errors":null}'

APIARY_TOKEN=""
result=$(apiary_register -n "my-bot" -h "$HIVE" -s "ssssssssssssssss" -t "custom")
assert_eq "$(echo "$result" | jq -r '.agent.name')" "my-bot" "register returns agent name"
assert_eq "$(echo "$result" | jq -r '.token')" "tok-123" "register returns token"

body=$(mock_last_body)
assert_eq "$(echo "$body" | jq -r '.name')" "my-bot" "register sends name in body"
assert_eq "$(echo "$body" | jq -r '.hive_id')" "$HIVE" "register sends hive_id in body"
assert_eq "$(echo "$body" | jq -r '.secret')" "ssssssssssssssss" "register sends secret in body"

method=$(mock_last_method)
assert_eq "$method" "POST" "register uses POST method"

# Register with optional fields
mock_reset
mock_response POST "/api/v1/agents/register" 200 \
    '{"data":{"agent":{"id":"agent-2"},"token":"tok-456"},"meta":{},"errors":null}'

APIARY_TOKEN=""
apiary_register -n "bot2" -h "$HIVE" -s "ssssssssssssssss" \
    -c '["code","summarize"]' -m '{"version":"1.0"}' >/dev/null

body=$(mock_last_body)
assert_eq "$(echo "$body" | jq '.capabilities | length')" "2" "register sends capabilities array"
assert_eq "$(echo "$body" | jq -r '.metadata.version')" "1.0" "register sends metadata object"

# ── Login ────────────────────────────────────────────────────────

describe "apiary_login"

mock_reset
mock_response POST "/api/v1/agents/login" 200 \
    '{"data":{"agent":{"id":"agent-1"},"token":"tok-login"},"meta":{},"errors":null}'

APIARY_TOKEN=""
result=$(apiary_login -i "agent-1" -s "secret123456789a")
assert_eq "$(echo "$result" | jq -r '.token')" "tok-login" "login returns token"

# Token storage must be tested without $() subshell
APIARY_TOKEN=""
apiary_login -i "agent-1" -s "secret123456789a" >/dev/null
assert_eq "$APIARY_TOKEN" "tok-login" "login stores token"

body=$(mock_last_body)
assert_eq "$(echo "$body" | jq -r '.agent_id')" "agent-1" "login sends agent_id"
assert_eq "$(echo "$body" | jq -r '.secret')" "secret123456789a" "login sends secret"

# Login with a numeric-looking secret — must stay a string
mock_reset
mock_response POST "/api/v1/agents/login" 200 \
    '{"data":{"agent":{"id":"agent-1"},"token":"tok-num"},"meta":{},"errors":null}'

APIARY_TOKEN=""
apiary_login -i "agent-1" -s "9999999999999999" >/dev/null
body=$(mock_last_body)
assert_eq "$(echo "$body" | jq -r '.secret')" "9999999999999999" "numeric-looking secret value preserved"
assert_eq "$(echo "$body" | jq -r '.secret | type')" "string" "numeric-looking secret stays JSON string type"

# ── Me ───────────────────────────────────────────────────────────

describe "apiary_me"

mock_reset
mock_response GET "/api/v1/agents/me" 200 \
    '{"data":{"id":"agent-1","name":"bot","status":"online","type":"custom","hive_id":"'"$HIVE"'","capabilities":["code"]},"meta":{},"errors":null}'

APIARY_TOKEN="test-token"
result=$(apiary_me)
assert_eq "$(echo "$result" | jq -r '.id')" "agent-1" "me returns agent id"
assert_eq "$(echo "$result" | jq -r '.status')" "online" "me returns agent status"
assert_eq "$(echo "$result" | jq -r '.capabilities[0]')" "code" "me returns capabilities"

method=$(mock_last_method)
assert_eq "$method" "GET" "me uses GET method"

# ── Heartbeat ────────────────────────────────────────────────────

describe "apiary_heartbeat"

mock_reset
mock_response POST "/api/v1/agents/heartbeat" 200 \
    '{"data":{"id":"agent-1","status":"online","last_heartbeat":"2026-02-26T12:00:00Z"},"meta":{},"errors":null}'

APIARY_TOKEN="test-token"
result=$(apiary_heartbeat)
assert_eq "$(echo "$result" | jq -r '.status')" "online" "heartbeat returns status"

method=$(mock_last_method)
assert_eq "$method" "POST" "heartbeat uses POST method"

# Heartbeat with metadata
mock_reset
mock_response POST "/api/v1/agents/heartbeat" 200 \
    '{"data":{"id":"agent-1","status":"online","metadata":{"cpu":42}},"meta":{},"errors":null}'

apiary_heartbeat -m '{"cpu":42}' >/dev/null
body=$(mock_last_body)
assert_eq "$(echo "$body" | jq '.metadata.cpu')" "42" "heartbeat sends metadata in body"

# ── Update status ────────────────────────────────────────────────

describe "apiary_update_status"

mock_reset
mock_response PATCH "/api/v1/agents/status" 200 \
    '{"data":{"id":"agent-1","status":"busy","status_changed_at":"2026-02-26T12:00:00Z"},"meta":{},"errors":null}'

APIARY_TOKEN="test-token"
result=$(apiary_update_status "busy")
assert_eq "$(echo "$result" | jq -r '.status')" "busy" "update_status returns new status"

body=$(mock_last_body)
assert_eq "$(echo "$body" | jq -r '.status')" "busy" "update_status sends status in body"

method=$(mock_last_method)
assert_eq "$method" "PATCH" "update_status uses PATCH method"

# ── Summary ──────────────────────────────────────────────────────

test_summary
