#!/usr/bin/env bash
# test_auth_refresh.sh — Tests refresh-token auth recovery path for OpenClaw auth.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../../shell/tests/test_harness.sh"
source "${SCRIPT_DIR}/../../shell/src/apiary-sdk.sh"
_APIARY_SDK_LOADED=1
source "${SCRIPT_DIR}/../bin/apiary-auth.sh"

_tmp_config_dir=$(mktemp -d)
_tmp_out="${_tmp_config_dir}/output.txt"
trap 'rm -rf "$_tmp_config_dir"' EXIT

_setup() {
    unset APIARY_AGENT_ID APIARY_HIVE_ID APIARY_AGENT_NAME APIARY_TOKEN APIARY_AGENT_SECRET APIARY_AGENT_REFRESH_TOKEN 2>/dev/null || true
    export APIARY_BASE_URL="http://localhost:9999"
    export APIARY_CONFIG_DIR="$_tmp_config_dir"
    rm -f "${_tmp_config_dir}/agent.json" "${_tmp_config_dir}/token" "${_tmp_config_dir}/refresh-token" "$_tmp_out"
    mock_reset
}

describe "ensure_auth refreshes using APIARY_AGENT_REFRESH_TOKEN without secret"

_setup
export APIARY_AGENT_ID="agent-r-01"
export APIARY_AGENT_NAME="daemon-bot"
export APIARY_HIVE_ID="hive-r-1"
export APIARY_TOKEN="expired-token"
export APIARY_AGENT_REFRESH_TOKEN="refresh-old-123"

mock_response GET "/api/v1/agents/me" 401 \
  '{"data":null,"meta":{},"errors":[{"message":"Unauthenticated.","code":"auth_failed"}]}'
mock_response POST "/api/v1/agents/token/refresh" 200 \
  '{"data":{"agent":{"id":"agent-r-01","name":"daemon-bot","hive_id":"hive-r-1"},"token":"tok-new-abc","refresh_token":"refresh-new-xyz"},"meta":{},"errors":null}'

set +e
apiary_oc_ensure_auth >"$_tmp_out" 2>&1
rc=$?
set -e

assert_eq "$rc" "0" "ensure_auth succeeds via refresh token"
assert_eq "${APIARY_TOKEN:-}" "tok-new-abc" "APIARY_TOKEN updated from refresh"
assert_eq "${APIARY_AGENT_REFRESH_TOKEN:-}" "refresh-new-xyz" "refresh token rotated and exported"
assert_eq "$(cat "${_tmp_config_dir}/token")" "tok-new-abc" "token persisted to disk"
assert_eq "$(cat "${_tmp_config_dir}/refresh-token")" "refresh-new-xyz" "refresh token persisted to disk"

log="$(mock_url_log)"
assert_contains "$log" "GET http://localhost:9999/api/v1/agents/me" "me endpoint called first"
assert_contains "$log" "POST http://localhost:9999/api/v1/agents/token/refresh" "refresh endpoint called"
assert_not_contains "$log" "/api/v1/agents/login" "login endpoint not called when refresh succeeds"

describe "ensure_auth preserves persisted token on transient apiary_me failures"

_setup
export APIARY_AGENT_ID="agent-r-02"
export APIARY_AGENT_NAME="daemon-bot-2"
export APIARY_HIVE_ID="hive-r-2"
export APIARY_TOKEN="still-valid-token"
export APIARY_AGENT_REFRESH_TOKEN="refresh-still-valid"
printf 'still-valid-token\n' > "${_tmp_config_dir}/token"

mock_response GET "/api/v1/agents/me" 500 \
  '{"data":null,"meta":{},"errors":[{"message":"Server error","code":"server_error"}]}'

set +e
apiary_oc_ensure_auth >"$_tmp_out" 2>&1
rc=$?
set -e

assert_eq "$rc" "1" "ensure_auth returns non-zero on transient me failure"
assert_eq "${APIARY_TOKEN:-}" "still-valid-token" "in-memory token is preserved"
assert_eq "$(cat "${_tmp_config_dir}/token")" "still-valid-token" "persisted token file is preserved"

log="$(mock_url_log)"
assert_contains "$log" "GET http://localhost:9999/api/v1/agents/me" "me endpoint called"
assert_not_contains "$log" "/api/v1/agents/token/refresh" "refresh endpoint not called on transient me failure"
assert_not_contains "$log" "/api/v1/agents/login" "login endpoint not called on transient me failure"

test_summary
