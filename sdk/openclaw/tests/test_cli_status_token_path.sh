#!/usr/bin/env bash
# test_cli_status_token_path.sh — Status command should respect APIARY_CONFIG_DIR token path.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../shell/tests/test_harness.sh"

_tmp_config_dir=$(mktemp -d)
trap 'rm -rf "$_tmp_config_dir"' EXIT

_setup() {
    unset APIARY_TOKEN APIARY_AGENT_ID APIARY_AGENT_NAME APIARY_HIVE_ID APIARY_AGENT_REFRESH_TOKEN APIARY_BASE_URL APIARY_TOKEN_FILE 2>/dev/null || true
    export APIARY_CONFIG_DIR="$_tmp_config_dir"
    rm -f "${_tmp_config_dir}/agent.json" "${_tmp_config_dir}/token" "${_tmp_config_dir}/refresh-token"
}

describe "apiary-cli status loads token from APIARY_CONFIG_DIR before reporting status"

_setup
printf 'token-from-custom-config\n' > "${_tmp_config_dir}/token"
jq -n '{id:"agent-status-1", name:"status-bot", hive_id:"hive-status-1"}' > "${_tmp_config_dir}/agent.json"

set +e
output="$("${SCRIPT_DIR}/../bin/apiary-cli.sh" status 2>&1)"
rc=$?
set -e

assert_eq "$rc" "0" "status command succeeds"
assert_contains "$output" "Agent ID:    agent-status-1" "status loads agent metadata from APIARY_CONFIG_DIR"
assert_contains "$output" "Token:       <set> (masked)" "status reports token loaded from APIARY_CONFIG_DIR token file"
assert_contains "$output" "Auth:        unknown (APIARY_BASE_URL not set)" "status avoids network auth check when base URL is unset"

test_summary
