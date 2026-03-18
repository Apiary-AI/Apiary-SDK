#!/usr/bin/env bash
# test_persona.sh — Persona endpoint tests.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test_harness.sh"
source "${SCRIPT_DIR}/../src/apiary-sdk.sh"

export APIARY_BASE_URL="http://localhost:9999"
export APIARY_TOKEN="test-token"
export APIARY_DEBUG=0

# ── Get persona ──────────────────────────────────────────────────

describe "apiary_get_persona"

mock_reset
mock_response GET "/api/v1/persona" 200 \
    '{"data":{"version":1,"is_active":true,"documents":{"SOUL":{"content":"You are helpful.","locked":true},"AGENT":{"content":"Process tasks.","locked":false}},"config":{"llm":{"model":"claude-sonnet-4-5-20250514","temperature":0.3}},"lock_policy":{},"message":"Initial persona","created_by_type":"human","created_at":"2025-01-01T00:00:00+00:00"},"meta":{},"errors":null}'

result=$(apiary_get_persona)
assert_eq "$(echo "$result" | jq -r '.version')" "1" "get_persona returns version"
assert_eq "$(echo "$result" | jq -r '.is_active')" "true" "get_persona returns is_active"

method=$(mock_last_method)
assert_eq "$method" "GET" "get_persona uses GET method"

url=$(mock_last_url)
assert_contains "$url" "/api/v1/persona" "get_persona URL is correct"

# ── Get persona config ───────────────────────────────────────────

describe "apiary_get_persona_config"

mock_reset
mock_response GET "/api/v1/persona/config" 200 \
    '{"data":{"version":1,"config":{"llm":{"model":"claude-sonnet-4-5-20250514","temperature":0.3}}},"meta":{},"errors":null}'

result=$(apiary_get_persona_config)
assert_eq "$(echo "$result" | jq -r '.version')" "1" "get_persona_config returns version"
assert_eq "$(echo "$result" | jq -r '.config.llm.model')" "claude-sonnet-4-5-20250514" "get_persona_config returns nested config.llm.model"

method=$(mock_last_method)
assert_eq "$method" "GET" "get_persona_config uses GET method"

url=$(mock_last_url)
assert_contains "$url" "/api/v1/persona/config" "get_persona_config URL is correct"

# ── Get persona document ─────────────────────────────────────────

describe "apiary_get_persona_document"

mock_reset
mock_response GET "/api/v1/persona/documents/SOUL" 200 \
    '{"data":{"version":1,"document":"SOUL","content":"You are a helpful agent."},"meta":{},"errors":null}'

result=$(apiary_get_persona_document SOUL)
assert_eq "$(echo "$result" | jq -r '.document')" "SOUL" "get_persona_document returns document name via .document key"
assert_eq "$(echo "$result" | jq -r '.content')" "You are a helpful agent." "get_persona_document returns content"

method=$(mock_last_method)
assert_eq "$method" "GET" "get_persona_document uses GET method"

url=$(mock_last_url)
assert_contains "$url" "/api/v1/persona/documents/SOUL" "get_persona_document URL contains document name"

# ── Get persona assembled ────────────────────────────────────────

describe "apiary_get_persona_assembled"

mock_reset
mock_response GET "/api/v1/persona/assembled" 200 \
    '{"data":{"version":1,"prompt":"You are a helpful agent.\n\nRules:\n- Be concise.","document_count":2},"meta":{},"errors":null}'

result=$(apiary_get_persona_assembled)
assert_eq "$(echo "$result" | jq '.document_count')" "2" "get_persona_assembled returns document_count"

method=$(mock_last_method)
assert_eq "$method" "GET" "get_persona_assembled uses GET method"

url=$(mock_last_url)
assert_contains "$url" "/api/v1/persona/assembled" "get_persona_assembled URL is correct"

# ── Update persona document — with message ───────────────────────

describe "apiary_update_persona_document (with message)"

mock_reset
mock_response PATCH "/api/v1/persona/documents/MEMORY" 200 \
    '{"data":{"version":2,"document":"MEMORY","content":"New content"},"meta":{},"errors":null}'

result=$(apiary_update_persona_document MEMORY -c "New content" -m "update msg")
assert_eq "$(echo "$result" | jq -r '.document')" "MEMORY" "update_persona_document returns document name via .document key"
assert_eq "$(echo "$result" | jq '.version')" "2" "update_persona_document returns new version"

method=$(mock_last_method)
assert_eq "$method" "PATCH" "update_persona_document uses PATCH method"

url=$(mock_last_url)
assert_contains "$url" "/api/v1/persona/documents/MEMORY" "update_persona_document URL contains document name"

body=$(mock_last_body)
assert_eq "$(echo "$body" | jq -r '.content')" "New content" "update_persona_document sends content"
assert_eq "$(echo "$body" | jq -r '.message')" "update msg" "update_persona_document sends message"

# ── Update persona document — without message ────────────────────

describe "apiary_update_persona_document (no message)"

mock_reset
mock_response PATCH "/api/v1/persona/documents/MEMORY" 200 \
    '{"data":{"version":3,"document":"MEMORY","content":"New content"},"meta":{},"errors":null}'

apiary_update_persona_document MEMORY -c "New content" >/dev/null
body=$(mock_last_body)
assert_eq "$(echo "$body" | jq -r '.content')" "New content" "update_persona_document (no msg) sends content"
assert_eq "$(echo "$body" | jq 'has("message")')" "false" "update_persona_document omits message when not provided"

# ── Update persona document — explicit empty message ─────────────

describe "apiary_update_persona_document (explicit empty message)"

mock_reset
mock_response PATCH "/api/v1/persona/documents/MEMORY" 200 \
    '{"data":{"version":4,"document":"MEMORY","content":"New content"},"meta":{},"errors":null}'

apiary_update_persona_document MEMORY -c "New content" -m "" >/dev/null
body=$(mock_last_body)
assert_eq "$(echo "$body" | jq -r '.content')" "New content" "update_persona_document (empty msg) sends content"
assert_eq "$(echo "$body" | jq 'has("message")')" "true" "update_persona_document includes message key when -m '' is passed"
assert_eq "$(echo "$body" | jq -r '.message')" "" "update_persona_document sends empty string for -m ''"

# ── Update persona document — missing -c flag ────────────────────

describe "apiary_update_persona_document (missing -c)"

assert_exit 1 apiary_update_persona_document MEMORY "update_persona_document returns error when -c is missing"

# ── Update persona document — 403 locked document ────────────────

describe "apiary_update_persona_document (403 locked)"

mock_reset
mock_response PATCH "/api/v1/persona/documents/SOUL" 403 \
    '{"data":null,"meta":{},"errors":[{"message":"Document is locked.","code":"forbidden"}]}'

set +e
apiary_update_persona_document SOUL -c "override" >/dev/null 2>/dev/null
rc=$?
set -e
assert_eq "$rc" "$APIARY_ERR_PERMISSION" "update_persona_document returns 403 exit code for locked document"

# ── Update persona document — content starting with '[' ──────────

describe "apiary_update_persona_document (content starting with '[')"

mock_reset
mock_response PATCH "/api/v1/persona/documents/MEMORY" 200 \
    '{"data":{"version":4,"document":"MEMORY","content":"[ ] task"},"meta":{},"errors":null}'

result=$(apiary_update_persona_document MEMORY -c "[ ] task" -m "checklist")
assert_eq "$(echo "$result" | jq -r '.document')" "MEMORY" "bracket content: returns document name"

body=$(mock_last_body)
assert_eq "$(echo "$body" | jq -r '.content')" "[ ] task" "bracket content: sent as string, not raw JSON"
assert_eq "$(echo "$body" | jq -r 'type')" "object" "bracket content: body is a valid JSON object"

# ── Update persona document — content starting with '{' ──────────

describe "apiary_update_persona_document (content starting with '{')"

mock_reset
mock_response PATCH "/api/v1/persona/documents/MEMORY" 200 \
    '{"data":{"version":5,"document":"MEMORY","content":"{\"foo\":1}"},"meta":{},"errors":null}'

result=$(apiary_update_persona_document MEMORY -c '{"foo":1}' -m "json-like content")
assert_eq "$(echo "$result" | jq -r '.document')" "MEMORY" "brace content: returns document name"

body=$(mock_last_body)
assert_eq "$(echo "$body" | jq -r '.content')" '{"foo":1}' "brace content: sent as string, not parsed as object"
assert_eq "$(echo "$body" | jq -r '.content | type')" "string" "brace content: content field is a JSON string"

# ── Update persona document — content is 'true' ──────────────────

describe "apiary_update_persona_document (content is 'true')"

mock_reset
mock_response PATCH "/api/v1/persona/documents/MEMORY" 200 \
    '{"data":{"version":6,"document":"MEMORY","content":"true"},"meta":{},"errors":null}'

result=$(apiary_update_persona_document MEMORY -c "true")
assert_eq "$(echo "$result" | jq -r '.document')" "MEMORY" "true content: returns document name"

body=$(mock_last_body)
assert_eq "$(echo "$body" | jq -r '.content')" "true" "true content: sent as string, not boolean"
assert_eq "$(echo "$body" | jq -r '.content | type')" "string" "true content: content field is a JSON string"

# ── Update persona document — content is 'null' ──────────────────

describe "apiary_update_persona_document (content is 'null')"

mock_reset
mock_response PATCH "/api/v1/persona/documents/MEMORY" 200 \
    '{"data":{"version":7,"document":"MEMORY","content":"null"},"meta":{},"errors":null}'

result=$(apiary_update_persona_document MEMORY -c "null")
assert_eq "$(echo "$result" | jq -r '.document')" "MEMORY" "null content: returns document name"

body=$(mock_last_body)
assert_eq "$(echo "$body" | jq -r '.content')" "null" "null content: sent as string, not JSON null"
assert_eq "$(echo "$body" | jq -r '.content | type')" "string" "null content: content field is a JSON string"

# ── Update persona document — jq unavailable ─────────────────────
#
# When jq is absent, apiary_update_persona_document must fail BEFORE sending
# the PATCH. If the request were sent, the server would create a new persona
# version while the response parsing failed, misleading callers into retrying
# and silently creating duplicate versions.

describe "apiary_update_persona_document (jq unavailable)"

mock_reset

# Hide jq by placing a temporary stub directory at the front of PATH that
# contains a fake `jq` script which exits 127. This makes `command -v jq`
# succeed (finding the stub) but any invocation immediately fail, reliably
# exercising the preflight check regardless of where the real jq is installed
# on the host (e.g. even if it lives in /usr/bin or /bin).
_jq_stub_dir=$(mktemp -d)
printf '#!/bin/sh\nexit 127\n' > "$_jq_stub_dir/jq"
chmod +x "$_jq_stub_dir/jq"
_saved_PATH="$PATH"
PATH="$_jq_stub_dir:$PATH"

rc=0
err_output=$(apiary_update_persona_document MEMORY -c "some content" 2>&1) || rc=$?

PATH="$_saved_PATH"
rm -rf "$_jq_stub_dir"

assert_eq "$rc" "$APIARY_ERR_DEPS" "returns APIARY_ERR_DEPS when jq is unavailable"
assert_contains "$err_output" "jq is required" "prints descriptive error when jq is unavailable"
assert_eq "$(mock_was_called)" "false" \
    "does not send PATCH request when jq is unavailable"

# ── CLI dispatch — help text ─────────────────────────────────────

describe "apiary-cli persona commands in help text"

CLI="${SCRIPT_DIR}/../bin/apiary-cli"
export APIARY_BASE_URL="http://localhost:9999"
export APIARY_TOKEN="test-token"

help_output=$(bash "$CLI" --help 2>&1 || true)

assert_contains "$help_output" "persona-get" \
    "help text includes persona-get command"
assert_contains "$help_output" "persona-get-config" \
    "help text includes persona-get-config command"
assert_contains "$help_output" "persona-get-document" \
    "help text includes persona-get-document command"
assert_contains "$help_output" "persona-get-assembled" \
    "help text includes persona-get-assembled command"
assert_contains "$help_output" "persona-update-document" \
    "help text includes persona-update-document command"

# ── CLI dispatch — argument validation ───────────────────────────

describe "apiary-cli persona-get-document (missing NAME)"

set +e
output=$(bash "$CLI" persona-get-document 2>&1)
rc=$?
set -e

assert_ne "$rc" "0" "persona-get-document without NAME exits non-zero"
assert_contains "$output" "persona-get-document NAME" \
    "persona-get-document without NAME prints usage hint"

describe "apiary-cli persona-update-document (missing NAME)"

set +e
output=$(bash "$CLI" persona-update-document 2>&1)
rc=$?
set -e

assert_ne "$rc" "0" "persona-update-document without NAME exits non-zero"
assert_contains "$output" "persona-update-document NAME" \
    "persona-update-document without NAME prints usage hint"

# ── Summary ──────────────────────────────────────────────────────

test_summary
