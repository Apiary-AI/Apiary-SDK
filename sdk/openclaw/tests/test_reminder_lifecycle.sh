#!/usr/bin/env bash
# test_reminder_lifecycle.sh — Tests for reminder task lifecycle.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../../shell/tests/test_harness.sh"
source "${SCRIPT_DIR}/../../shell/src/apiary-sdk.sh"
_APIARY_SDK_LOADED=1

_tmp_dir=$(mktemp -d)
trap 'rm -rf "$_tmp_dir"' EXIT

_CLAIM_CALLS=0
_CLAIM_RC=0
_COMPLETE_CALLS=0
_COMPLETE_LAST_TASK=""
_COMPLETE_LAST_RESULT=""
_FAIL_CALLS=0
_FAIL_LAST_TASK=""
_FAIL_LAST_ERROR=""
_SEND_CALLS=0
_SEND_LAST_TARGET=""
_SEND_LAST_CHANNEL=""
_SEND_LAST_MESSAGE=""
_SEND_RC=0

_setup() {
    export APIARY_CONFIG_DIR="$_tmp_dir"
    export APIARY_HIVE_ID="hive-test-reminder"
    export PENDING_DIR="${_tmp_dir}/pending"

    mkdir -p "$PENDING_DIR"
    rm -f "${PENDING_DIR}"/*.json 2>/dev/null || true
    rm -rf "${_tmp_dir}/traces"

    _CLAIM_CALLS=0
    _CLAIM_RC=0
    _COMPLETE_CALLS=0
    _COMPLETE_LAST_TASK=""
    _COMPLETE_LAST_RESULT=""
    _FAIL_CALLS=0
    _FAIL_LAST_TASK=""
    _FAIL_LAST_ERROR=""
    _SEND_CALLS=0
    _SEND_LAST_TARGET=""
    _SEND_LAST_CHANNEL=""
    _SEND_LAST_MESSAGE=""
    _SEND_RC=0

    source "${SCRIPT_DIR}/../bin/apiary-webhook-wake.sh"
    source "${SCRIPT_DIR}/../bin/apiary-task-lifecycle.sh"

    apiary_claim_task() {
        _CLAIM_CALLS=$((_CLAIM_CALLS + 1))
        return $_CLAIM_RC
    }

    apiary_complete_task() {
        local task_id="$2"
        shift 2
        _COMPLETE_CALLS=$((_COMPLETE_CALLS + 1))
        _COMPLETE_LAST_TASK="$task_id"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -r) _COMPLETE_LAST_RESULT="$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        return 0
    }

    apiary_fail_task() {
        local task_id="$2"
        shift 2
        _FAIL_CALLS=$((_FAIL_CALLS + 1))
        _FAIL_LAST_TASK="$task_id"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -e) _FAIL_LAST_ERROR="$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        return 0
    }

    _wake_send_alert() {
        _SEND_CALLS=$((_SEND_CALLS + 1))
        _SEND_LAST_TARGET="${1:-}"
        _SEND_LAST_CHANNEL="${2:-}"
        _SEND_LAST_MESSAGE="${3:-}"
        return $_SEND_RC
    }
}

_make_reminder_task() {
    local task_id="${1:-r-1}"
    local channel="${2:-telegram}"
    local target="${3:-12345}"
    local message="${4:-Test reminder}"

    jq -n \
        --arg tid "$task_id" \
        --arg ch "$channel" \
        --arg tgt "$target" \
        --arg msg "$message" \
        '{id:$tid,type:"reminder",payload:{channel:$ch,target:$tgt,message:$msg}}'
}

_make_reminder_task_nested() {
    local task_id="${1:-r-nested-1}"
    local channel="${2:-telegram}"
    local target="${3:-12345}"
    local message="${4:-Nested reminder}"

    jq -n \
        --arg tid "$task_id" \
        --arg ch "$channel" \
        --arg tgt "$target" \
        --arg msg "$message" \
        '{id:$tid,type:"reminder",payload:{task_payload:{channel:$ch,target:$tgt,message:$msg}}}'
}

describe "Reminder lifecycle — claim + deliver + complete success"

_setup
task_json=$(_make_reminder_task_nested "rem-ok" "telegram" "94650650" "Ship build")
echo "$task_json" > "${PENDING_DIR}/rem-ok.json"

set +e
_lifecycle_process_reminder "$task_json" "rem-ok"
rc=$?
set -e

assert_eq "$rc" "0" "returns 0 on successful reminder delivery"
assert_eq "$_CLAIM_CALLS" "1" "claim called once"
assert_eq "$_SEND_CALLS" "1" "message delivery called once"
assert_eq "$_SEND_LAST_CHANNEL" "telegram" "delivery uses parsed channel"
assert_eq "$_SEND_LAST_TARGET" "94650650" "delivery uses parsed target"
assert_eq "$_SEND_LAST_MESSAGE" "Ship build" "delivery uses parsed message"
assert_eq "$_COMPLETE_CALLS" "1" "complete called once"
assert_eq "$_FAIL_CALLS" "0" "fail not called on success"
assert_contains "$_COMPLETE_LAST_RESULT" "completed" "complete result includes status"
assert_eq "$([ -f "${PENDING_DIR}/rem-ok.json" ] && echo exists || echo removed)" "removed" "pending file removed after success"
assert_eq "$([ -f "${_tmp_dir}/traces/rem-ok.json" ] && echo exists || echo missing)" "exists" "trace file written"


describe "Reminder lifecycle — validation failure fails task"

_setup
task_json=$(jq -n '{id:"rem-bad",type:"reminder",payload:{channel:"telegram",message:"No target"}}')
echo "$task_json" > "${PENDING_DIR}/rem-bad.json"

set +e
_lifecycle_process_reminder "$task_json" "rem-bad"
rc=$?
set -e

assert_eq "$rc" "0" "returns 0 after failing invalid reminder"
assert_eq "$_CLAIM_CALLS" "1" "claim still called before validation"
assert_eq "$_SEND_CALLS" "0" "delivery not attempted for invalid payload"
assert_eq "$_COMPLETE_CALLS" "0" "complete not called on validation failure"
assert_eq "$_FAIL_CALLS" "1" "fail called on validation failure"
assert_contains "$_FAIL_LAST_ERROR" "validation failed" "fail payload includes validation error"
assert_eq "$([ -f "${PENDING_DIR}/rem-bad.json" ] && echo exists || echo removed)" "removed" "pending file removed after validation failure"


describe "Reminder lifecycle — delivery failure fails task"

_setup
_SEND_RC=1
task_json=$(_make_reminder_task "rem-send-fail" "telegram" "777" "Delivery should fail")
echo "$task_json" > "${PENDING_DIR}/rem-send-fail.json"

set +e
_lifecycle_process_reminder "$task_json" "rem-send-fail"
rc=$?
set -e

assert_eq "$rc" "0" "returns 0 after failing delivery"
assert_eq "$_SEND_CALLS" "1" "delivery attempted once"
assert_eq "$_COMPLETE_CALLS" "0" "complete not called when delivery fails"
assert_eq "$_FAIL_CALLS" "1" "fail called when delivery fails"
assert_contains "$_FAIL_LAST_ERROR" "delivery failed" "fail payload includes delivery error"


describe "Retry sweep — processes reminder tasks and skips unrelated types"

_setup
reminder_task=$(_make_reminder_task "rem-retry" "telegram" "999" "Retry reminder")
other_task=$(jq -n '{id:"other-1",type:"code_review",payload:{}}')

echo "$reminder_task" > "${PENDING_DIR}/rem-retry.json"
echo "$other_task" > "${PENDING_DIR}/other-1.json"

_lifecycle_retry_pending_handlers

assert_eq "$_CLAIM_CALLS" "1" "retry sweep claims reminder task"
assert_eq "$_COMPLETE_CALLS" "1" "retry sweep completes reminder task"
assert_eq "$_FAIL_CALLS" "0" "retry sweep does not fail successful reminder"
assert_eq "$([ -f "${PENDING_DIR}/rem-retry.json" ] && echo exists || echo removed)" "removed" "retry sweep removes reminder pending file"
assert_eq "$([ -f "${PENDING_DIR}/other-1.json" ] && echo exists || echo removed)" "exists" "retry sweep leaves unrelated task untouched"


test_summary
