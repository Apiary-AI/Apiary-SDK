#!/usr/bin/env bash
# test_load_agent.sh — Tests for _apiary_oc_load_agent fail-soft behaviour.
#
# Validates that malformed agent.json does not abort the CLI under set -e,
# while valid agent.json still populates env vars correctly.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Reuse the Shell SDK test harness
source "${SCRIPT_DIR}/../../shell/tests/test_harness.sh"

# We need the SDK loaded (provides _apiary_debug, APIARY_OK, etc.)
source "${SCRIPT_DIR}/../../shell/src/apiary-sdk.sh"
_APIARY_SDK_LOADED=1

# Source auth module (defines _apiary_oc_load_agent)
source "${SCRIPT_DIR}/../bin/apiary-auth.sh"

# ── helpers ──────────────────────────────────────────────────────

_tmp_config_dir=$(mktemp -d)
trap 'rm -rf "$_tmp_config_dir"' EXIT

_setup() {
    # Reset env vars between tests
    unset APIARY_AGENT_ID APIARY_HIVE_ID APIARY_AGENT_NAME 2>/dev/null || true
    export APIARY_CONFIG_DIR="$_tmp_config_dir"
    rm -f "${_tmp_config_dir}/agent.json"
}

# ── Test: malformed JSON does not abort ──────────────────────────

describe "Malformed agent.json"

_setup
echo "NOT VALID JSON{{{" > "${_tmp_config_dir}/agent.json"

set +e
_apiary_oc_load_agent
rc=$?
set -e

assert_eq "$rc" "0" "returns 0 on malformed agent.json"
assert_eq "${APIARY_AGENT_ID:-}" "" "APIARY_AGENT_ID stays empty on malformed file"
assert_eq "${APIARY_HIVE_ID:-}" "" "APIARY_HIVE_ID stays empty on malformed file"
assert_eq "${APIARY_AGENT_NAME:-}" "" "APIARY_AGENT_NAME stays empty on malformed file"

# ── Test: empty file does not abort ──────────────────────────────

describe "Empty agent.json"

_setup
: > "${_tmp_config_dir}/agent.json"

set +e
_apiary_oc_load_agent
rc=$?
set -e

assert_eq "$rc" "0" "returns 0 on empty agent.json"
assert_eq "${APIARY_AGENT_ID:-}" "" "APIARY_AGENT_ID stays empty on empty file"

# ── Test: truncated JSON does not abort ──────────────────────────

describe "Truncated JSON agent.json"

_setup
echo '{"id": "abc-123", "hive_id":' > "${_tmp_config_dir}/agent.json"

set +e
_apiary_oc_load_agent
rc=$?
set -e

assert_eq "$rc" "0" "returns 0 on truncated JSON"
assert_eq "${APIARY_AGENT_ID:-}" "" "APIARY_AGENT_ID stays empty on truncated JSON"

# ── Test: valid JSON loads correctly ─────────────────────────────

describe "Valid agent.json"

_setup
jq -n '{id: "agent-001", hive_id: "hive-42", name: "test-agent"}' \
    > "${_tmp_config_dir}/agent.json"

set +e
_apiary_oc_load_agent
rc=$?
set -e

assert_eq "$rc" "0" "returns 0 on valid agent.json"
assert_eq "${APIARY_AGENT_ID}" "agent-001" "loads APIARY_AGENT_ID from valid file"
assert_eq "${APIARY_HIVE_ID}" "hive-42" "loads APIARY_HIVE_ID from valid file"
assert_eq "${APIARY_AGENT_NAME}" "test-agent" "loads APIARY_AGENT_NAME from valid file"

# ── Test: env vars take precedence over file ─────────────────────

describe "Env vars take precedence"

_setup
export APIARY_AGENT_ID="env-id-999"
export APIARY_HIVE_ID="env-hive-99"
jq -n '{id: "file-id", hive_id: "file-hive", name: "file-agent"}' \
    > "${_tmp_config_dir}/agent.json"

set +e
_apiary_oc_load_agent
rc=$?
set -e

assert_eq "$rc" "0" "returns 0 when env vars already set"
assert_eq "${APIARY_AGENT_ID}" "env-id-999" "keeps env APIARY_AGENT_ID over file"
assert_eq "${APIARY_HIVE_ID}" "env-hive-99" "keeps env APIARY_HIVE_ID over file"
assert_eq "${APIARY_AGENT_NAME}" "file-agent" "loads APIARY_AGENT_NAME when not in env"

# ── Test: missing file is fine ───────────────────────────────────

describe "Missing agent.json"

_setup
# No file created

set +e
_apiary_oc_load_agent
rc=$?
set -e

assert_eq "$rc" "0" "returns 0 when agent.json does not exist"
assert_eq "${APIARY_AGENT_ID:-}" "" "APIARY_AGENT_ID stays empty when file missing"

# ── Test: malformed JSON + env vars = env vars preserved ─────────

describe "Malformed JSON with env vars set"

_setup
export APIARY_AGENT_ID="env-agent-id"
export APIARY_TOKEN="test-token-123"
echo "CORRUPT!!!" > "${_tmp_config_dir}/agent.json"

set +e
_apiary_oc_load_agent
rc=$?
set -e

assert_eq "$rc" "0" "returns 0 with malformed file and env vars"
assert_eq "${APIARY_AGENT_ID}" "env-agent-id" "preserves APIARY_AGENT_ID from env on malformed file"
assert_eq "${APIARY_TOKEN}" "test-token-123" "preserves APIARY_TOKEN on malformed file"

# ── Summary ──────────────────────────────────────────────────────

test_summary
