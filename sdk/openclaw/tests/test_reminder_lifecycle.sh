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
    export APIARY_AGENT_ID="test-agent-reminder"
    export APIARY_CLAIM_TTL=900
    export PENDING_DIR="${_tmp_dir}/pending"

    mkdir -p "$PENDING_DIR"
    rm -f "${PENDING_DIR}"/*.json 2>/dev/null || true
    rm -f "${PENDING_DIR}"/*.claimed 2>/dev/null || true
    rm -f "${PENDING_DIR}"/*.delivered 2>/dev/null || true
    rm -rf "${PENDING_DIR}/quarantine" 2>/dev/null || true
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
    _TRACE_RC=1
    _TRACE_OUTPUT=""

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

    apiary_get_task_trace() {
        if [[ -n "$_TRACE_OUTPUT" ]]; then
            echo "$_TRACE_OUTPUT"
        fi
        return $_TRACE_RC
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

# Write a JSON .claimed marker matching the production format.
# Arguments: task_id [agent_id]
_write_test_claimed_marker() {
    local task_id="${1:-}"
    local agent_id="${2:-${APIARY_AGENT_ID:-test-agent-reminder}}"
    local ts
    ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%s')
    jq -n --arg tid "$task_id" --arg agent "$agent_id" --arg ts "$ts" \
        '{"task_id":$tid,"agent_id":$agent,"claimed_at":$ts}' \
        > "${PENDING_DIR}/${task_id}.claimed"
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


# ═══════════════════════════════════════════════════════════════
# Crash recovery: 409 + .claimed → re-process and deliver
# ═══════════════════════════════════════════════════════════════

describe "Crash recovery — 409 + verified .claimed re-processes reminder (no drop)"

_setup
_CLAIM_RC=$APIARY_ERR_CONFLICT

# Pre-create JSON .claimed marker with matching ownership evidence
_write_test_claimed_marker "rem-crash"

task_json=$(_make_reminder_task "rem-crash" "telegram" "94650650" "Crash recovery reminder")
echo "$task_json" > "${PENDING_DIR}/rem-crash.json"

set +e
_lifecycle_process_reminder "$task_json" "rem-crash"
rc=$?
set -e

assert_eq "$rc" "0" "crash-recovery: returns 0"
assert_eq "$_SEND_CALLS" "1" "crash-recovery: delivery attempted (re-processed)"
assert_eq "$_SEND_LAST_TARGET" "94650650" "crash-recovery: correct target"
assert_eq "$_SEND_LAST_CHANNEL" "telegram" "crash-recovery: correct channel"
assert_eq "$_SEND_LAST_MESSAGE" "Crash recovery reminder" "crash-recovery: correct message"
assert_eq "$_COMPLETE_CALLS" "1" "crash-recovery: task completed (not dropped)"
assert_eq "$_FAIL_CALLS" "0" "crash-recovery: fail NOT called (no force-fail)"
assert_contains "$_COMPLETE_LAST_RESULT" "completed" "crash-recovery: result confirms completion"
assert_contains "$_COMPLETE_LAST_RESULT" "delivered" "crash-recovery: result confirms delivery"
assert_eq "$([ -f "${PENDING_DIR}/rem-crash.claimed" ] && echo exists || echo removed)" "removed" \
    "crash-recovery: .claimed marker cleaned up"
assert_eq "$([ -f "${PENDING_DIR}/rem-crash.json" ] && echo exists || echo removed)" "removed" \
    "crash-recovery: pending file cleaned up"


# ═══════════════════════════════════════════════════════════════
# Crash recovery: 409 + .claimed with delivery failure → fails task
# ═══════════════════════════════════════════════════════════════

describe "Crash recovery — 409 + verified .claimed with delivery failure still fails task properly"

_setup
_CLAIM_RC=$APIARY_ERR_CONFLICT
_SEND_RC=1

_write_test_claimed_marker "rem-crash-delfail"

task_json=$(_make_reminder_task "rem-crash-delfail" "telegram" "777" "Will fail delivery")
echo "$task_json" > "${PENDING_DIR}/rem-crash-delfail.json"

set +e
_lifecycle_process_reminder "$task_json" "rem-crash-delfail"
rc=$?
set -e

assert_eq "$rc" "0" "crash-delfail: returns 0 (fail-soft)"
assert_eq "$_SEND_CALLS" "1" "crash-delfail: delivery attempted"
assert_eq "$_COMPLETE_CALLS" "0" "crash-delfail: complete NOT called (delivery failed)"
assert_eq "$_FAIL_CALLS" "1" "crash-delfail: fail called (delivery failure)"
assert_contains "$_FAIL_LAST_ERROR" "delivery failed" "crash-delfail: error mentions delivery failure"
assert_eq "$([ -f "${PENDING_DIR}/rem-crash-delfail.claimed" ] && echo exists || echo removed)" "removed" \
    "crash-delfail: .claimed marker cleaned up"


# ═══════════════════════════════════════════════════════════════
# Crash recovery: 409 + .claimed with terminal API failure → artifact saved
# ═══════════════════════════════════════════════════════════════

describe "Crash recovery — 409 + verified .claimed with terminal API failure saves artifact"

_setup
_CLAIM_RC=$APIARY_ERR_CONFLICT

_write_test_claimed_marker "rem-crash-apifail"

# Override complete_task to fail
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
    return 1  # simulate API failure
}

task_json=$(_make_reminder_task "rem-crash-apifail" "telegram" "555" "API will fail")
echo "$task_json" > "${PENDING_DIR}/rem-crash-apifail.json"

set +e
_lifecycle_process_reminder "$task_json" "rem-crash-apifail"
rc=$?
set -e

assert_eq "$rc" "1" "crash-apifail: returns 1 (retryable)"
assert_eq "$_SEND_CALLS" "1" "crash-apifail: delivery was attempted"
assert_eq "$([ -f "${PENDING_DIR}/rem-crash-apifail.result.json" ] && echo exists || echo missing)" "exists" \
    "crash-apifail: result artifact saved for retry"
assert_eq "$([ -f "${PENDING_DIR}/rem-crash-apifail.claimed" ] && echo exists || echo missing)" "exists" \
    "crash-apifail: .claimed marker preserved for next retry"


# ═══════════════════════════════════════════════════════════════
# 409 without .claimed → quarantine (not force-fail)
# ═══════════════════════════════════════════════════════════════

describe "Crash recovery — 409 without .claimed quarantines reminder"

_setup
_CLAIM_RC=$APIARY_ERR_CONFLICT

# No .claimed marker — uncertain ownership
task_json=$(_make_reminder_task "rem-foreign" "telegram" "111" "Foreign claim")
echo "$task_json" > "${PENDING_DIR}/rem-foreign.json"

set +e
_lifecycle_process_reminder "$task_json" "rem-foreign"
rc=$?
set -e

assert_eq "$rc" "0" "foreign: returns 0 (graceful skip)"
assert_eq "$_SEND_CALLS" "0" "foreign: delivery NOT attempted"
assert_eq "$_COMPLETE_CALLS" "0" "foreign: complete NOT called"
assert_eq "$_FAIL_CALLS" "0" "foreign: fail NOT called"
assert_eq "$([ -f "${PENDING_DIR}/rem-foreign.json" ] && echo exists || echo moved)" "moved" \
    "foreign: pending file moved from active"
assert_eq "$([ -f "${PENDING_DIR}/quarantine/rem-foreign.json" ] && echo quarantined || echo missing)" "quarantined" \
    "foreign: pending file quarantined for recovery"


# ═══════════════════════════════════════════════════════════════
# 409 + .claimed but WRONG agent → quarantine (no blind re-delivery)
# ═══════════════════════════════════════════════════════════════

describe "Ownership gate — 409 + .claimed with wrong agent_id quarantines"

_setup
_CLAIM_RC=$APIARY_ERR_CONFLICT

# Write marker with a different agent_id
_write_test_claimed_marker "rem-wrong-agent" "other-agent-999"

task_json=$(_make_reminder_task "rem-wrong-agent" "telegram" "111" "Wrong agent")
echo "$task_json" > "${PENDING_DIR}/rem-wrong-agent.json"

set +e
_lifecycle_process_reminder "$task_json" "rem-wrong-agent"
rc=$?
set -e

assert_eq "$rc" "0" "wrong-agent: returns 0 (graceful quarantine)"
assert_eq "$_SEND_CALLS" "0" "wrong-agent: delivery NOT attempted"
assert_eq "$_COMPLETE_CALLS" "0" "wrong-agent: complete NOT called"
assert_eq "$_FAIL_CALLS" "0" "wrong-agent: fail NOT called"
assert_eq "$([ -f "${PENDING_DIR}/quarantine/rem-wrong-agent.json" ] && echo quarantined || echo missing)" "quarantined" \
    "wrong-agent: pending file quarantined"
assert_eq "$([ -f "${PENDING_DIR}/quarantine/rem-wrong-agent.claimed" ] && echo quarantined || echo missing)" "quarantined" \
    "wrong-agent: .claimed marker quarantined for investigation"


# ═══════════════════════════════════════════════════════════════
# 409 + .claimed but STALE marker → quarantine (no blind re-delivery)
# ═══════════════════════════════════════════════════════════════

describe "Ownership gate — 409 + .claimed with stale marker quarantines"

_setup
_CLAIM_RC=$APIARY_ERR_CONFLICT

# Write a valid marker (correct agent, correct task_id) then backdate it
_write_test_claimed_marker "rem-stale"
touch -d "2 hours ago" "${PENDING_DIR}/rem-stale.claimed"

task_json=$(_make_reminder_task "rem-stale" "telegram" "222" "Stale marker")
echo "$task_json" > "${PENDING_DIR}/rem-stale.json"

set +e
_lifecycle_process_reminder "$task_json" "rem-stale"
rc=$?
set -e

assert_eq "$rc" "0" "stale: returns 0 (graceful quarantine)"
assert_eq "$_SEND_CALLS" "0" "stale: delivery NOT attempted"
assert_eq "$_COMPLETE_CALLS" "0" "stale: complete NOT called"
assert_eq "$_FAIL_CALLS" "0" "stale: fail NOT called"
assert_eq "$([ -f "${PENDING_DIR}/quarantine/rem-stale.json" ] && echo quarantined || echo missing)" "quarantined" \
    "stale: pending file quarantined"
assert_eq "$([ -f "${PENDING_DIR}/quarantine/rem-stale.claimed" ] && echo quarantined || echo missing)" "quarantined" \
    "stale: .claimed marker quarantined"


# ═══════════════════════════════════════════════════════════════
# 409 + legacy plain-text .claimed → quarantine (no structured evidence)
# ═══════════════════════════════════════════════════════════════

describe "Ownership gate — 409 + legacy plain-text .claimed quarantines"

_setup
_CLAIM_RC=$APIARY_ERR_CONFLICT

# Write old-format plain-text marker (pre-P2)
echo "rem-legacy" > "${PENDING_DIR}/rem-legacy.claimed"

task_json=$(_make_reminder_task "rem-legacy" "telegram" "333" "Legacy marker")
echo "$task_json" > "${PENDING_DIR}/rem-legacy.json"

set +e
_lifecycle_process_reminder "$task_json" "rem-legacy"
rc=$?
set -e

assert_eq "$rc" "0" "legacy: returns 0 (graceful quarantine)"
assert_eq "$_SEND_CALLS" "0" "legacy: delivery NOT attempted"
assert_eq "$_COMPLETE_CALLS" "0" "legacy: complete NOT called"
assert_eq "$_FAIL_CALLS" "0" "legacy: fail NOT called"
assert_eq "$([ -f "${PENDING_DIR}/quarantine/rem-legacy.json" ] && echo quarantined || echo missing)" "quarantined" \
    "legacy: pending file quarantined"
assert_eq "$([ -f "${PENDING_DIR}/quarantine/rem-legacy.claimed" ] && echo quarantined || echo missing)" "quarantined" \
    "legacy: .claimed marker quarantined"


# ═══════════════════════════════════════════════════════════════
# 409 + .claimed with mismatched task_id → quarantine
# ═══════════════════════════════════════════════════════════════

describe "Ownership gate — 409 + .claimed with mismatched task_id quarantines"

_setup
_CLAIM_RC=$APIARY_ERR_CONFLICT

# Write marker for a different task_id
_write_test_claimed_marker "rem-other-task"
mv "${PENDING_DIR}/rem-other-task.claimed" "${PENDING_DIR}/rem-mismatch.claimed"

task_json=$(_make_reminder_task "rem-mismatch" "telegram" "444" "Mismatched task")
echo "$task_json" > "${PENDING_DIR}/rem-mismatch.json"

set +e
_lifecycle_process_reminder "$task_json" "rem-mismatch"
rc=$?
set -e

assert_eq "$rc" "0" "mismatch: returns 0 (graceful quarantine)"
assert_eq "$_SEND_CALLS" "0" "mismatch: delivery NOT attempted"
assert_eq "$_COMPLETE_CALLS" "0" "mismatch: complete NOT called"
assert_eq "$_FAIL_CALLS" "0" "mismatch: fail NOT called"
assert_eq "$([ -f "${PENDING_DIR}/quarantine/rem-mismatch.json" ] && echo quarantined || echo missing)" "quarantined" \
    "mismatch: pending file quarantined"


# ═══════════════════════════════════════════════════════════════
# Claim network error → retry (return 1), consistent behavior
# ═══════════════════════════════════════════════════════════════

describe "Reminder lifecycle — claim network error returns 1 for retry"

_setup
_CLAIM_RC=1  # generic error (not conflict)
task_json=$(_make_reminder_task "rem-neterr" "telegram" "888" "Network error")
echo "$task_json" > "${PENDING_DIR}/rem-neterr.json"

set +e
_lifecycle_process_reminder "$task_json" "rem-neterr"
rc=$?
set -e

assert_eq "$rc" "1" "neterr: returns 1 on claim network error"
assert_eq "$_SEND_CALLS" "0" "neterr: delivery NOT attempted"
assert_eq "$_COMPLETE_CALLS" "0" "neterr: complete not called"
assert_eq "$_FAIL_CALLS" "0" "neterr: fail not called"
assert_eq "$([ -f "${PENDING_DIR}/rem-neterr.json" ] && echo exists || echo removed)" "exists" \
    "neterr: pending file preserved for retry"


# ═══════════════════════════════════════════════════════════════
# Full round-trip: claim → crash → 409+.claimed → re-deliver
# ═══════════════════════════════════════════════════════════════

describe "Crash recovery — full round-trip: claim OK, crash, 409+.claimed re-delivers"

_setup

# Phase 1: claim succeeds, delivery succeeds, complete API fails → artifact saved
_complete_call_count=0
apiary_claim_task() {
    _CLAIM_CALLS=$((_CLAIM_CALLS + 1))
    return $_CLAIM_RC
}
apiary_complete_task() {
    local task_id="$2"
    shift 2
    _complete_call_count=$((_complete_call_count + 1))
    _COMPLETE_CALLS=$_complete_call_count
    _COMPLETE_LAST_TASK="$task_id"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r) _COMPLETE_LAST_RESULT="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    if [[ $_complete_call_count -eq 1 ]]; then
        return 1  # first: API failure
    fi
    return 0  # subsequent: success
}

task_json=$(_make_reminder_task "rem-roundtrip" "telegram" "42" "Round-trip reminder")
echo "$task_json" > "${PENDING_DIR}/rem-roundtrip.json"

set +e
_lifecycle_process_reminder "$task_json" "rem-roundtrip"
r1=$?
set -e

assert_eq "$r1" "1" "roundtrip-r1: returns 1 (terminal API failed)"
assert_eq "$_SEND_CALLS" "1" "roundtrip-r1: delivery was attempted"
assert_eq "$([ -f "${PENDING_DIR}/rem-roundtrip.result.json" ] && echo exists || echo missing)" "exists" \
    "roundtrip-r1: result artifact saved"
assert_eq "$([ -f "${PENDING_DIR}/rem-roundtrip.claimed" ] && echo exists || echo missing)" "exists" \
    "roundtrip-r1: .claimed marker preserved"

# Phase 2: result artifact found → completion retried → succeeds
set +e
_lifecycle_process_reminder "$task_json" "rem-roundtrip"
r2=$?
set -e

assert_eq "$r2" "0" "roundtrip-r2: returns 0 (artifact retry succeeded)"
assert_eq "$([ -f "${PENDING_DIR}/rem-roundtrip.result.json" ] && echo exists || echo removed)" "removed" \
    "roundtrip-r2: result artifact cleaned up"
assert_eq "$([ -f "${PENDING_DIR}/rem-roundtrip.json" ] && echo exists || echo removed)" "removed" \
    "roundtrip-r2: pending file cleaned up"
assert_eq "$([ -f "${PENDING_DIR}/rem-roundtrip.claimed" ] && echo exists || echo removed)" "removed" \
    "roundtrip-r2: .claimed marker cleaned up"


# ═══════════════════════════════════════════════════════════════
# .claimed marker written on successful claim, cleaned on success
# ═══════════════════════════════════════════════════════════════

describe "Reminder — .claimed marker written as JSON on claim, cleaned on success"

_setup
_CLAIM_RC=0
task_json=$(_make_reminder_task "rem-marker" "telegram" "333" "Marker test")
echo "$task_json" > "${PENDING_DIR}/rem-marker.json"

# Override complete_task to capture but also check marker before cleanup
_marker_content=""
apiary_complete_task() {
    local task_id="$2"
    shift 2
    _COMPLETE_CALLS=$((_COMPLETE_CALLS + 1))
    _COMPLETE_LAST_TASK="$task_id"
    # Capture marker content while it still exists (before cleanup in Step 5)
    _marker_content=$(cat "${PENDING_DIR}/rem-marker.claimed" 2>/dev/null) || _marker_content=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r) _COMPLETE_LAST_RESULT="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    return 0
}

_lifecycle_process_reminder "$task_json" "rem-marker"

assert_eq "$_COMPLETE_CALLS" "1" "marker: task completed"
assert_eq "$([ -f "${PENDING_DIR}/rem-marker.claimed" ] && echo exists || echo removed)" "removed" \
    "marker: .claimed cleaned up after success"
assert_eq "$([ -f "${PENDING_DIR}/rem-marker.json" ] && echo exists || echo removed)" "removed" \
    "marker: pending file cleaned up after success"

# Verify JSON marker format with ownership evidence
marker_tid=$(echo "$_marker_content" | jq -r '.task_id // ""' 2>/dev/null) || marker_tid=""
marker_agent=$(echo "$_marker_content" | jq -r '.agent_id // ""' 2>/dev/null) || marker_agent=""
assert_eq "$marker_tid" "rem-marker" "marker: JSON marker contains correct task_id"
assert_eq "$marker_agent" "$APIARY_AGENT_ID" "marker: JSON marker contains correct agent_id"


# ═══════════════════════════════════════════════════════════════
# P2: Duplicate delivery prevention — local trace exists
# Crash after delivery+complete+trace but before cleanup
# ═══════════════════════════════════════════════════════════════

describe "Duplicate prevention — local trace blocks re-delivery on 409+.claimed"

_setup
_CLAIM_RC=$APIARY_ERR_CONFLICT

# Simulate: prior run completed fully but crashed before cleanup.
# .claimed marker exists (verified), local trace exists.
_write_test_claimed_marker "rem-dup-trace"
mkdir -p "${_tmp_dir}/traces" 2>/dev/null
echo '{"task_id":"rem-dup-trace","status":"completed"}' > "${_tmp_dir}/traces/rem-dup-trace.json"

task_json=$(_make_reminder_task "rem-dup-trace" "telegram" "94650650" "Should NOT re-deliver")
echo "$task_json" > "${PENDING_DIR}/rem-dup-trace.json"

set +e
_lifecycle_process_reminder "$task_json" "rem-dup-trace"
rc=$?
set -e

assert_eq "$rc" "0" "dup-trace: returns 0 (reconciled)"
assert_eq "$_SEND_CALLS" "0" "dup-trace: delivery NOT attempted (duplicate prevented)"
assert_eq "$_COMPLETE_CALLS" "0" "dup-trace: complete NOT called (already done)"
assert_eq "$_FAIL_CALLS" "0" "dup-trace: fail NOT called"
assert_eq "$([ -f "${PENDING_DIR}/rem-dup-trace.json" ] && echo exists || echo removed)" "removed" \
    "dup-trace: pending file cleaned up"
assert_eq "$([ -f "${PENDING_DIR}/rem-dup-trace.claimed" ] && echo exists || echo removed)" "removed" \
    "dup-trace: .claimed marker cleaned up"


# ═══════════════════════════════════════════════════════════════
# P2: Duplicate delivery prevention — .delivered marker exists
# Crash after delivery but before local cleanup
# ═══════════════════════════════════════════════════════════════

describe "Duplicate prevention — .delivered marker reconciles without re-send"

_setup
_CLAIM_RC=$APIARY_ERR_CONFLICT

# Simulate: prior run delivered but crashed before cleanup.
# .claimed and .delivered markers exist, no trace, no .result.json.
_write_test_claimed_marker "rem-dup-delivered"
echo "rem-dup-delivered" > "${PENDING_DIR}/rem-dup-delivered.delivered"

task_json=$(_make_reminder_task "rem-dup-delivered" "telegram" "94650650" "Should NOT re-deliver")
echo "$task_json" > "${PENDING_DIR}/rem-dup-delivered.json"

set +e
_lifecycle_process_reminder "$task_json" "rem-dup-delivered"
rc=$?
set -e

assert_eq "$rc" "0" "dup-delivered: returns 0 (reconciled)"
assert_eq "$_SEND_CALLS" "0" "dup-delivered: delivery NOT attempted (duplicate prevented)"
assert_eq "$_COMPLETE_CALLS" "1" "dup-delivered: complete called (reconciliation)"
assert_eq "$_FAIL_CALLS" "0" "dup-delivered: fail NOT called"
assert_contains "$_COMPLETE_LAST_RESULT" "reconciled" "dup-delivered: result mentions reconciliation"
assert_eq "$([ -f "${PENDING_DIR}/rem-dup-delivered.json" ] && echo exists || echo removed)" "removed" \
    "dup-delivered: pending file cleaned up"
assert_eq "$([ -f "${PENDING_DIR}/rem-dup-delivered.claimed" ] && echo exists || echo removed)" "removed" \
    "dup-delivered: .claimed marker cleaned up"
assert_eq "$([ -f "${PENDING_DIR}/rem-dup-delivered.delivered" ] && echo exists || echo removed)" "removed" \
    "dup-delivered: .delivered marker cleaned up"
assert_eq "$([ -f "${_tmp_dir}/traces/rem-dup-delivered.json" ] && echo exists || echo missing)" "exists" \
    "dup-delivered: trace written on reconciliation"


# ═══════════════════════════════════════════════════════════════
# P2: Duplicate prevention — .delivered marker with API failure
# Reconciliation API fails → saves artifact (fail-soft)
# ═══════════════════════════════════════════════════════════════

describe "Duplicate prevention — .delivered reconciliation API failure saves artifact"

_setup
_CLAIM_RC=$APIARY_ERR_CONFLICT

_write_test_claimed_marker "rem-dup-apifail"
echo "rem-dup-apifail" > "${PENDING_DIR}/rem-dup-apifail.delivered"

# Override complete_task to fail
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
    return 1  # simulate API failure
}

task_json=$(_make_reminder_task "rem-dup-apifail" "telegram" "555" "API will fail")
echo "$task_json" > "${PENDING_DIR}/rem-dup-apifail.json"

set +e
_lifecycle_process_reminder "$task_json" "rem-dup-apifail"
rc=$?
set -e

assert_eq "$rc" "1" "dup-apifail: returns 1 (retryable)"
assert_eq "$_SEND_CALLS" "0" "dup-apifail: delivery NOT attempted (duplicate prevented)"
assert_eq "$_COMPLETE_CALLS" "1" "dup-apifail: complete attempted (reconciliation)"
assert_eq "$([ -f "${PENDING_DIR}/rem-dup-apifail.result.json" ] && echo exists || echo missing)" "exists" \
    "dup-apifail: result artifact saved for retry"


# ═══════════════════════════════════════════════════════════════
# P2: Remote reconciliation prevents duplicate when local evidence missing
# ═══════════════════════════════════════════════════════════════

describe "Duplicate prevention — remote trace terminal blocks re-delivery"

_setup
_CLAIM_RC=$APIARY_ERR_CONFLICT

# Simulate: prior run delivered+completed remotely, but no local evidence
# (.delivered not written or lost). Remote trace shows completed.
_write_test_claimed_marker "rem-dup-remote"

# Mock remote trace to return completed status
_TRACE_RC=0
_TRACE_OUTPUT='{"data":{"task_id":"rem-dup-remote","status":"completed"}}'
apiary_get_task_trace() {
    if [[ -n "$_TRACE_OUTPUT" ]]; then
        echo "$_TRACE_OUTPUT"
    fi
    return $_TRACE_RC
}

task_json=$(_make_reminder_task "rem-dup-remote" "telegram" "94650650" "Should NOT re-deliver")
echo "$task_json" > "${PENDING_DIR}/rem-dup-remote.json"

set +e
_lifecycle_process_reminder "$task_json" "rem-dup-remote"
rc=$?
set -e

assert_eq "$rc" "0" "dup-remote: returns 0 (reconciled)"
assert_eq "$_SEND_CALLS" "0" "dup-remote: delivery NOT attempted (duplicate prevented)"
assert_eq "$_COMPLETE_CALLS" "0" "dup-remote: complete NOT called (remote already terminal)"
assert_eq "$([ -f "${PENDING_DIR}/rem-dup-remote.json" ] && echo exists || echo removed)" "removed" \
    "dup-remote: pending file cleaned up"
assert_eq "$([ -f "${PENDING_DIR}/rem-dup-remote.claimed" ] && echo exists || echo removed)" "removed" \
    "dup-remote: .claimed marker cleaned up"
assert_eq "$([ -f "${_tmp_dir}/traces/rem-dup-remote.json" ] && echo exists || echo missing)" "exists" \
    "dup-remote: trace written from remote reconciliation"


# ═══════════════════════════════════════════════════════════════
# P2: Remote reconciliation treats cancelled as terminal
# ═══════════════════════════════════════════════════════════════

describe "Duplicate prevention — remote trace cancelled blocks re-delivery"

_setup
_CLAIM_RC=$APIARY_ERR_CONFLICT

_write_test_claimed_marker "rem-dup-cancelled"

_TRACE_RC=0
_TRACE_OUTPUT='{"data":{"task_id":"rem-dup-cancelled","status":"cancelled"}}'
apiary_get_task_trace() {
    if [[ -n "$_TRACE_OUTPUT" ]]; then
        echo "$_TRACE_OUTPUT"
    fi
    return $_TRACE_RC
}

task_json=$(_make_reminder_task "rem-dup-cancelled" "telegram" "94650650" "Should NOT re-deliver (cancelled)")
echo "$task_json" > "${PENDING_DIR}/rem-dup-cancelled.json"

set +e
_lifecycle_process_reminder "$task_json" "rem-dup-cancelled"
rc=$?
set -e

assert_eq "$rc" "0" "dup-cancelled: returns 0 (reconciled)"
assert_eq "$_SEND_CALLS" "0" "dup-cancelled: delivery NOT attempted (duplicate prevented)"
assert_eq "$_COMPLETE_CALLS" "0" "dup-cancelled: complete NOT called (remote already terminal)"
assert_eq "$([ -f "${PENDING_DIR}/rem-dup-cancelled.json" ] && echo exists || echo removed)" "removed" \
    "dup-cancelled: pending file cleaned up"
assert_eq "$([ -f "${PENDING_DIR}/rem-dup-cancelled.claimed" ] && echo exists || echo removed)" "removed" \
    "dup-cancelled: .claimed marker cleaned up"
assert_eq "$([ -f "${_tmp_dir}/traces/rem-dup-cancelled.json" ] && echo exists || echo missing)" "exists" \
    "dup-cancelled: trace written from remote reconciliation"


# ═══════════════════════════════════════════════════════════════
# P2: Remote reconciliation treats dead_letter as terminal
# ═══════════════════════════════════════════════════════════════

describe "Duplicate prevention — remote trace dead_letter blocks re-delivery"

_setup
_CLAIM_RC=$APIARY_ERR_CONFLICT

_write_test_claimed_marker "rem-dup-deadletter"

_TRACE_RC=0
_TRACE_OUTPUT='{"data":{"task_id":"rem-dup-deadletter","status":"dead_letter"}}'
apiary_get_task_trace() {
    if [[ -n "$_TRACE_OUTPUT" ]]; then
        echo "$_TRACE_OUTPUT"
    fi
    return $_TRACE_RC
}

task_json=$(_make_reminder_task "rem-dup-deadletter" "telegram" "94650650" "Should NOT re-deliver (dead_letter)")
echo "$task_json" > "${PENDING_DIR}/rem-dup-deadletter.json"

set +e
_lifecycle_process_reminder "$task_json" "rem-dup-deadletter"
rc=$?
set -e

assert_eq "$rc" "0" "dup-deadletter: returns 0 (reconciled)"
assert_eq "$_SEND_CALLS" "0" "dup-deadletter: delivery NOT attempted (duplicate prevented)"
assert_eq "$_COMPLETE_CALLS" "0" "dup-deadletter: complete NOT called (remote already terminal)"
assert_eq "$([ -f "${PENDING_DIR}/rem-dup-deadletter.json" ] && echo exists || echo removed)" "removed" \
    "dup-deadletter: pending file cleaned up"
assert_eq "$([ -f "${PENDING_DIR}/rem-dup-deadletter.claimed" ] && echo exists || echo removed)" "removed" \
    "dup-deadletter: .claimed marker cleaned up"
assert_eq "$([ -f "${_tmp_dir}/traces/rem-dup-deadletter.json" ] && echo exists || echo missing)" "exists" \
    "dup-deadletter: trace written from remote reconciliation"


# ═══════════════════════════════════════════════════════════════
# P2: Remote reconciliation treats expired as terminal
# ═══════════════════════════════════════════════════════════════

describe "Duplicate prevention — remote trace expired blocks re-delivery"

_setup
_CLAIM_RC=$APIARY_ERR_CONFLICT

_write_test_claimed_marker "rem-dup-expired"

_TRACE_RC=0
_TRACE_OUTPUT='{"data":{"task_id":"rem-dup-expired","status":"expired"}}'
apiary_get_task_trace() {
    if [[ -n "$_TRACE_OUTPUT" ]]; then
        echo "$_TRACE_OUTPUT"
    fi
    return $_TRACE_RC
}

task_json=$(_make_reminder_task "rem-dup-expired" "telegram" "94650650" "Should NOT re-deliver (expired)")
echo "$task_json" > "${PENDING_DIR}/rem-dup-expired.json"

set +e
_lifecycle_process_reminder "$task_json" "rem-dup-expired"
rc=$?
set -e

assert_eq "$rc" "0" "dup-expired: returns 0 (reconciled)"
assert_eq "$_SEND_CALLS" "0" "dup-expired: delivery NOT attempted (duplicate prevented)"
assert_eq "$_COMPLETE_CALLS" "0" "dup-expired: complete NOT called (remote already terminal)"
assert_eq "$([ -f "${PENDING_DIR}/rem-dup-expired.json" ] && echo exists || echo removed)" "removed" \
    "dup-expired: pending file cleaned up"
assert_eq "$([ -f "${PENDING_DIR}/rem-dup-expired.claimed" ] && echo exists || echo removed)" "removed" \
    "dup-expired: .claimed marker cleaned up"
assert_eq "$([ -f "${_tmp_dir}/traces/rem-dup-expired.json" ] && echo exists || echo missing)" "exists" \
    "dup-expired: trace written from remote reconciliation"


# ═══════════════════════════════════════════════════════════════
# P2: Pre-delivery crash still re-delivers (fix doesn't break recovery)
# ═══════════════════════════════════════════════════════════════

describe "Duplicate prevention — pre-delivery crash still re-delivers correctly"

_setup
_CLAIM_RC=$APIARY_ERR_CONFLICT

# Simulate: genuine pre-delivery crash. Only .claimed exists,
# no .delivered, no trace, remote trace fails (non-terminal).
_write_test_claimed_marker "rem-precrash"

# Remote trace returns failure (no trace available)
_TRACE_RC=1
_TRACE_OUTPUT=""
apiary_get_task_trace() {
    if [[ -n "$_TRACE_OUTPUT" ]]; then
        echo "$_TRACE_OUTPUT"
    fi
    return $_TRACE_RC
}

task_json=$(_make_reminder_task "rem-precrash" "telegram" "42" "Pre-delivery crash reminder")
echo "$task_json" > "${PENDING_DIR}/rem-precrash.json"

set +e
_lifecycle_process_reminder "$task_json" "rem-precrash"
rc=$?
set -e

assert_eq "$rc" "0" "precrash: returns 0 (delivered successfully)"
assert_eq "$_SEND_CALLS" "1" "precrash: delivery attempted (correct for pre-delivery crash)"
assert_eq "$_SEND_LAST_TARGET" "42" "precrash: correct target"
assert_eq "$_SEND_LAST_CHANNEL" "telegram" "precrash: correct channel"
assert_eq "$_SEND_LAST_MESSAGE" "Pre-delivery crash reminder" "precrash: correct message"
assert_eq "$_COMPLETE_CALLS" "1" "precrash: task completed"
assert_eq "$_FAIL_CALLS" "0" "precrash: fail NOT called"
assert_eq "$([ -f "${PENDING_DIR}/rem-precrash.json" ] && echo exists || echo removed)" "removed" \
    "precrash: pending file cleaned up"
assert_eq "$([ -f "${PENDING_DIR}/rem-precrash.claimed" ] && echo exists || echo removed)" "removed" \
    "precrash: .claimed marker cleaned up"


# ═══════════════════════════════════════════════════════════════
# P2: .delivered marker written on delivery, cleaned on success
# ═══════════════════════════════════════════════════════════════

describe "Reminder — .delivered marker written on delivery, cleaned on success"

_setup
_CLAIM_RC=0
task_json=$(_make_reminder_task "rem-dmarker" "telegram" "333" "Delivered marker test")
echo "$task_json" > "${PENDING_DIR}/rem-dmarker.json"

# Override complete_task to check .delivered exists before cleanup
_delivered_exists_before_cleanup=""
apiary_complete_task() {
    local task_id="$2"
    shift 2
    _COMPLETE_CALLS=$((_COMPLETE_CALLS + 1))
    _COMPLETE_LAST_TASK="$task_id"
    # Check .delivered marker while it still exists (before Step 5 cleanup)
    _delivered_exists_before_cleanup=$([ -f "${PENDING_DIR}/rem-dmarker.delivered" ] && echo exists || echo missing)
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r) _COMPLETE_LAST_RESULT="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    return 0
}

_lifecycle_process_reminder "$task_json" "rem-dmarker"

assert_eq "$_COMPLETE_CALLS" "1" "dmarker: task completed"
assert_eq "$_delivered_exists_before_cleanup" "exists" "dmarker: .delivered exists during complete (before cleanup)"
assert_eq "$([ -f "${PENDING_DIR}/rem-dmarker.delivered" ] && echo exists || echo removed)" "removed" \
    "dmarker: .delivered cleaned up after success"
assert_eq "$([ -f "${PENDING_DIR}/rem-dmarker.json" ] && echo exists || echo removed)" "removed" \
    "dmarker: pending file cleaned up"


test_summary
