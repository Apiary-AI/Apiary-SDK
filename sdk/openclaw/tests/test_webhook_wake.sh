#!/usr/bin/env bash
# test_webhook_wake.sh — Tests for webhook-wake bridge.
#
# Validates:
#   - PR comment payload parsing (GitHub formats)
#   - Severity hint extraction
#   - Idempotency / deduplication
#   - Wake invocation conditions (enabled/disabled, session set/unset)
#   - Fail-soft on malformed payloads

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Reuse the Shell SDK test harness
source "${SCRIPT_DIR}/../../shell/tests/test_harness.sh"

# We need the SDK loaded (provides APIARY_OK, etc.)
source "${SCRIPT_DIR}/../../shell/src/apiary-sdk.sh"
_APIARY_SDK_LOADED=1

# ── helpers ──────────────────────────────────────────────────────

_tmp_dir=$(mktemp -d)
trap 'rm -rf "$_tmp_dir"' EXIT

_setup() {
    export APIARY_CONFIG_DIR="$_tmp_dir"
    export APIARY_WAKE_ENABLED="true"
    export APIARY_WAKE_SESSION="test-session-123"
    export APIARY_WAKE_LOG="${_tmp_dir}/wake.log"
    export APIARY_WAKE_DEBOUNCE_SECS="5"
    rm -f "${_tmp_dir}/wake_seen.json"
    rm -f "${_tmp_dir}/wake.log"
    _WAKE_INVOCATIONS=0
    _WAKE_LAST_MESSAGE=""
    _WAKE_LAST_SESSION=""

    # Re-source to pick up env changes
    source "${SCRIPT_DIR}/../bin/apiary-webhook-wake.sh"
}

# Mock openclaw CLI
openclaw() {
    if [[ "${1:-}" == "sessions_send" ]]; then
        shift
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --session) _WAKE_LAST_SESSION="$2"; shift 2 ;;
                --text) _WAKE_LAST_MESSAGE="$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        _WAKE_INVOCATIONS=$((_WAKE_INVOCATIONS + 1))
        return 0
    fi
    return 0
}
export -f openclaw 2>/dev/null || true

# Build a realistic GitHub PR comment webhook task payload.
# Matches the real shape produced by GitHubConnector::parseWebhook() →
# WebhookRouteEvaluator::executeCreateTask():
#   task.payload.event_payload = { action, repository, sender, body: { <raw github json> } }
_make_pr_comment_task() {
    local task_id="${1:-task-001}"
    local comment_id="${2:-42}"
    local repo="${3:-octocat/hello-world}"
    local pr_num="${4:-7}"
    local comment_body="${5:-Please fix the tests}"
    local action="${6:-created}"

    jq -n \
        --arg tid "$task_id" \
        --arg action "$action" \
        --argjson cid "$comment_id" \
        --arg repo "$repo" \
        --argjson pr "$pr_num" \
        --arg cbody "$comment_body" \
        --arg curl "https://github.com/${repo}/pull/${pr_num}#issuecomment-${comment_id}" \
        --arg purl "https://github.com/${repo}/pull/${pr_num}" \
        '{
            id: $tid,
            type: "webhook_handler",
            payload: {
                webhook_route_id: "route-001",
                service_id: "svc-001",
                event_payload: {
                    action: $action,
                    repository: { full_name: $repo },
                    sender: { login: "test-user" },
                    body: {
                        action: $action,
                        comment: {
                            id: $cid,
                            html_url: $curl,
                            body: $cbody
                        },
                        issue: {
                            number: $pr,
                            pull_request: {
                                html_url: $purl
                            }
                        },
                        repository: {
                            full_name: $repo
                        }
                    }
                }
            }
        }'
}

# Build a legacy/flat payload (no .body wrapper) for backwards-compat testing
_make_pr_comment_task_flat() {
    local task_id="${1:-task-flat-001}"
    local comment_id="${2:-42}"
    local repo="${3:-octocat/hello-world}"
    local pr_num="${4:-7}"
    local comment_body="${5:-Please fix the tests}"
    local action="${6:-created}"

    jq -n \
        --arg tid "$task_id" \
        --arg action "$action" \
        --argjson cid "$comment_id" \
        --arg repo "$repo" \
        --argjson pr "$pr_num" \
        --arg cbody "$comment_body" \
        --arg curl "https://github.com/${repo}/pull/${pr_num}#issuecomment-${comment_id}" \
        --arg purl "https://github.com/${repo}/pull/${pr_num}" \
        '{
            id: $tid,
            type: "webhook_handler",
            payload: {
                webhook_route_id: "route-001",
                service_id: "svc-001",
                event_payload: {
                    action: $action,
                    comment: {
                        id: $cid,
                        html_url: $curl,
                        body: $cbody
                    },
                    issue: {
                        number: $pr,
                        pull_request: {
                            html_url: $purl
                        }
                    },
                    repository: {
                        full_name: $repo
                    }
                }
            }
        }'
}

# Build a PR review comment payload (pull_request_review_comment event)
# Real shape: event_payload.body contains the raw GitHub JSON
_make_pr_review_comment_task() {
    local task_id="${1:-task-002}"
    local comment_id="${2:-99}"

    jq -n \
        --arg tid "$task_id" \
        --argjson cid "$comment_id" \
        '{
            id: $tid,
            type: "webhook_handler",
            payload: {
                webhook_route_id: "route-002",
                service_id: "svc-002",
                event_payload: {
                    action: "created",
                    repository: { full_name: "acme/repo" },
                    sender: { login: "reviewer" },
                    body: {
                        action: "created",
                        comment: {
                            id: $cid,
                            html_url: "https://github.com/acme/repo/pull/5#discussion_r99",
                            body: "Looks good to me"
                        },
                        pull_request: {
                            number: 5,
                            html_url: "https://github.com/acme/repo/pull/5"
                        },
                        repository: {
                            full_name: "acme/repo"
                        }
                    }
                }
            }
        }'
}

# ═══════════════════════════════════════════════════════════════
# Parser tests
# ═══════════════════════════════════════════════════════════════

describe "Parser — GitHub issue comment on PR"

_setup
task_json=$(_make_pr_comment_task "t1" 42 "octocat/hello" 7 "Fix the bug")

set +e
parsed=$(_wake_parse_pr_comment "$task_json" 2>/dev/null)
rc=$?
set -e

assert_eq "$rc" "0" "parses issue_comment payload successfully"
assert_eq "$(echo "$parsed" | jq -r '.comment_id')" "42" "extracts comment_id"
assert_eq "$(echo "$parsed" | jq -r '.repo')" "octocat/hello" "extracts repo"
assert_eq "$(echo "$parsed" | jq -r '.pr_number')" "7" "extracts pr_number"
assert_contains "$(echo "$parsed" | jq -r '.comment_url')" "issuecomment-42" "extracts comment URL"
assert_eq "$(echo "$parsed" | jq -r '.severity')" "normal" "default severity is normal"

# ── Parser: PR review comment ──────────────────────────────────

describe "Parser — GitHub PR review comment"

_setup
task_json=$(_make_pr_review_comment_task "t2" 99)

set +e
parsed=$(_wake_parse_pr_comment "$task_json" 2>/dev/null)
rc=$?
set -e

assert_eq "$rc" "0" "parses pull_request_review_comment payload"
assert_eq "$(echo "$parsed" | jq -r '.comment_id')" "99" "extracts comment_id from review comment"
assert_eq "$(echo "$parsed" | jq -r '.pr_number')" "5" "extracts pr_number from pull_request object"
assert_eq "$(echo "$parsed" | jq -r '.repo')" "acme/repo" "extracts repo from review comment"

# ── Parser: severity hints ─────────────────────────────────────

describe "Parser — severity hints"

_setup
task_json=$(_make_pr_comment_task "t3" 50 "org/repo" 1 "[URGENT] Deploy is broken")
parsed=$(_wake_parse_pr_comment "$task_json" 2>/dev/null)
assert_eq "$(echo "$parsed" | jq -r '.severity')" "urgent" "detects [urgent] severity"

task_json=$(_make_pr_comment_task "t4" 51 "org/repo" 1 "[Critical] Production down")
parsed=$(_wake_parse_pr_comment "$task_json" 2>/dev/null)
assert_eq "$(echo "$parsed" | jq -r '.severity')" "urgent" "detects [critical] severity"

task_json=$(_make_pr_comment_task "t5" 52 "org/repo" 1 "[HIGH] needs attention")
parsed=$(_wake_parse_pr_comment "$task_json" 2>/dev/null)
assert_eq "$(echo "$parsed" | jq -r '.severity')" "high" "detects [high] severity"

task_json=$(_make_pr_comment_task "t6" 53 "org/repo" 1 "[low] minor nit")
parsed=$(_wake_parse_pr_comment "$task_json" 2>/dev/null)
assert_eq "$(echo "$parsed" | jq -r '.severity')" "low" "detects [low] severity"

task_json=$(_make_pr_comment_task "t7" 54 "org/repo" 1 "Just a regular comment")
parsed=$(_wake_parse_pr_comment "$task_json" 2>/dev/null)
assert_eq "$(echo "$parsed" | jq -r '.severity')" "normal" "no severity hint defaults to normal"

# ── Parser: non-comment payloads return failure ────────────────

describe "Parser — non-comment payloads"

_setup

# Push event (no comment object)
push_task=$(jq -n '{
    id: "t-push",
    type: "webhook_handler",
    payload: {
        event_payload: {
            action: "push",
            ref: "refs/heads/main",
            repository: { full_name: "org/repo" }
        }
    }
}')

set +e
parsed=$(_wake_parse_pr_comment "$push_task" 2>/dev/null)
rc=$?
set -e

assert_ne "$rc" "0" "returns non-zero for push event (no comment)"

# Empty payload
empty_task='{"id":"t-empty","type":"webhook_handler","payload":{}}'
set +e
parsed=$(_wake_parse_pr_comment "$empty_task" 2>/dev/null)
rc=$?
set -e

assert_ne "$rc" "0" "returns non-zero for empty payload"

# Regular issue comment (NOT on a PR — no .issue.pull_request key)
issue_comment_task=$(jq -n '{
    id: "t-issue",
    type: "webhook_handler",
    payload: {
        event_payload: {
            action: "created",
            repository: { full_name: "org/repo" },
            sender: { login: "commenter" },
            body: {
                action: "created",
                comment: {
                    id: 999,
                    html_url: "https://github.com/org/repo/issues/3#issuecomment-999",
                    body: "This is a regular issue comment"
                },
                issue: {
                    number: 3,
                    title: "Bug report"
                },
                repository: { full_name: "org/repo" }
            }
        }
    }
}')

set +e
parsed=$(_wake_parse_pr_comment "$issue_comment_task" 2>/dev/null)
rc=$?
set -e

assert_ne "$rc" "0" "rejects issue_comment on regular issue (no pull_request marker)"

# Also test flat format (no .body wrapper) for regular issue comment
issue_comment_flat=$(jq -n '{
    id: "t-issue-flat",
    type: "webhook_handler",
    payload: {
        event_payload: {
            action: "created",
            comment: {
                id: 998,
                html_url: "https://github.com/org/repo/issues/3#issuecomment-998",
                body: "Flat issue comment"
            },
            issue: {
                number: 3,
                title: "Bug report"
            },
            repository: { full_name: "org/repo" }
        }
    }
}')

set +e
parsed=$(_wake_parse_pr_comment "$issue_comment_flat" 2>/dev/null)
rc=$?
set -e

assert_ne "$rc" "0" "rejects flat issue_comment on regular issue (no pull_request marker)"

# ── Parser: backwards-compat flat payload (no .body wrapper) ──

describe "Parser — backwards-compat flat payload (no body wrapper)"

_setup
task_json=$(_make_pr_comment_task_flat "t-flat" 77 "flat/repo" 10 "Flat payload comment")

set +e
parsed=$(_wake_parse_pr_comment "$task_json" 2>/dev/null)
rc=$?
set -e

assert_eq "$rc" "0" "parses flat (legacy) payload successfully"
assert_eq "$(echo "$parsed" | jq -r '.comment_id')" "77" "extracts comment_id from flat payload"
assert_eq "$(echo "$parsed" | jq -r '.repo')" "flat/repo" "extracts repo from flat payload"
assert_eq "$(echo "$parsed" | jq -r '.pr_number')" "10" "extracts pr_number from flat payload"

# ── Parser: real GitHubConnector payload (event_payload.body) ─

describe "Parser — real GitHubConnector nested payload (event_payload.body)"

_setup
task_json=$(_make_pr_comment_task "t-real" 88 "real/repo" 15 "Real nested comment")

set +e
parsed=$(_wake_parse_pr_comment "$task_json" 2>/dev/null)
rc=$?
set -e

assert_eq "$rc" "0" "parses real nested payload successfully"
assert_eq "$(echo "$parsed" | jq -r '.comment_id')" "88" "extracts comment_id from body-nested payload"
assert_eq "$(echo "$parsed" | jq -r '.repo')" "real/repo" "extracts repo from body-nested payload"
assert_eq "$(echo "$parsed" | jq -r '.pr_number')" "15" "extracts pr_number from body-nested payload"
assert_eq "$(echo "$parsed" | jq -r '.comment_body')" "Real nested comment" "extracts comment body from body-nested payload"

# ── Wake: full round-trip with real nested payload ────────────

describe "Wake — full round-trip with real GitHubConnector payload"

_setup
_WAKE_INVOCATIONS=0
task_json=$(_make_pr_comment_task "wake-real" 500 "org/real-project" 42 "[urgent] Production broken")

apiary_webhook_wake "$task_json" "wake-real"

assert_eq "$_WAKE_INVOCATIONS" "1" "sends wake for real nested payload"
assert_contains "$_WAKE_LAST_MESSAGE" "org/real-project" "wake message includes repo from nested payload"
assert_contains "$_WAKE_LAST_MESSAGE" "#42" "wake message includes PR number from nested payload"
assert_contains "$_WAKE_LAST_MESSAGE" "urgent" "wake message includes severity from nested payload"

# ═══════════════════════════════════════════════════════════════
# Deduplication tests
# ═══════════════════════════════════════════════════════════════

describe "Deduplication — prevents duplicate wakes"

_setup

# First call should not be seen
set +e
_wake_is_seen "task1:comment1"
seen1=$?
set -e
assert_ne "$seen1" "0" "first check returns not-seen"

# Mark it
_wake_mark_seen "task1:comment1"

# Now it should be seen
set +e
_wake_is_seen "task1:comment1"
seen2=$?
set -e
assert_eq "$seen2" "0" "second check returns seen (within debounce)"

# Different key should not be seen
set +e
_wake_is_seen "task2:comment2"
seen3=$?
set -e
assert_ne "$seen3" "0" "different key is not seen"

# ── Deduplication: expired entries are not seen ────────────────

describe "Deduplication — expired debounce"

_setup
export APIARY_WAKE_DEBOUNCE_SECS=0
source "${SCRIPT_DIR}/../bin/apiary-webhook-wake.sh"

_wake_mark_seen "task-old:comment-old"
sleep 1

set +e
_wake_is_seen "task-old:comment-old"
seen=$?
set -e

assert_ne "$seen" "0" "expired entry is not seen (debounce=0)"

# ═══════════════════════════════════════════════════════════════
# Wake invocation tests
# ═══════════════════════════════════════════════════════════════

describe "Wake — invokes openclaw sessions_send"

_setup
_WAKE_INVOCATIONS=0
task_json=$(_make_pr_comment_task "wake-t1" 100 "org/repo" 3 "Please review")

apiary_webhook_wake "$task_json" "wake-t1"

assert_eq "$_WAKE_INVOCATIONS" "1" "sends exactly one wake"
assert_eq "$_WAKE_LAST_SESSION" "test-session-123" "targets correct session"
assert_contains "$_WAKE_LAST_MESSAGE" "wake-t1" "message includes task ID"
assert_contains "$_WAKE_LAST_MESSAGE" "org/repo" "message includes repo"
assert_contains "$_WAKE_LAST_MESSAGE" "#3" "message includes PR number"

# ── Wake: disabled does not invoke ─────────────────────────────

describe "Wake — disabled skips invocation"

_setup
export APIARY_WAKE_ENABLED="false"
source "${SCRIPT_DIR}/../bin/apiary-webhook-wake.sh"
_WAKE_INVOCATIONS=0

task_json=$(_make_pr_comment_task "wake-t2" 101)
apiary_webhook_wake "$task_json" "wake-t2"

assert_eq "$_WAKE_INVOCATIONS" "0" "does not invoke when disabled"

# ── Wake: missing session skips invocation ─────────────────────

describe "Wake — missing session skips invocation"

_setup
export APIARY_WAKE_SESSION=""
source "${SCRIPT_DIR}/../bin/apiary-webhook-wake.sh"
_WAKE_INVOCATIONS=0

task_json=$(_make_pr_comment_task "wake-t3" 102)
apiary_webhook_wake "$task_json" "wake-t3"

assert_eq "$_WAKE_INVOCATIONS" "0" "does not invoke without session"

# ── Wake: dedup prevents second invocation ─────────────────────

describe "Wake — dedup prevents duplicate wake"

_setup
_WAKE_INVOCATIONS=0
task_json=$(_make_pr_comment_task "wake-t4" 200 "org/repo" 5 "Review please")

apiary_webhook_wake "$task_json" "wake-t4"
assert_eq "$_WAKE_INVOCATIONS" "1" "first wake succeeds"

# Second call with same task+comment should be deduped
apiary_webhook_wake "$task_json" "wake-t4"
assert_eq "$_WAKE_INVOCATIONS" "1" "second wake is deduped"

# ── Wake: non-PR-comment task does not invoke ──────────────────

describe "Wake — non-PR-comment task is skipped gracefully"

_setup
_WAKE_INVOCATIONS=0

push_task=$(jq -n '{
    id: "wake-push",
    type: "webhook_handler",
    payload: {
        event_payload: {
            action: "push",
            ref: "refs/heads/main",
            repository: { full_name: "org/repo" }
        }
    }
}')

apiary_webhook_wake "$push_task" "wake-push"

assert_eq "$_WAKE_INVOCATIONS" "0" "does not wake for non-comment webhook"

# ── Wake: empty/null task JSON does not crash ──────────────────

describe "Wake — fail-soft on empty input"

_setup
_WAKE_INVOCATIONS=0

set +e
apiary_webhook_wake "" "wake-empty"
rc=$?
set -e

assert_eq "$rc" "0" "returns 0 on empty task JSON"
assert_eq "$_WAKE_INVOCATIONS" "0" "does not invoke on empty input"

set +e
apiary_webhook_wake '{"invalid' "wake-bad"
rc=$?
set -e

assert_eq "$rc" "0" "returns 0 on malformed JSON"
assert_eq "$_WAKE_INVOCATIONS" "0" "does not invoke on malformed JSON"

# ── Wake: log file is written ──────────────────────────────────

describe "Wake — log file records activity"

_setup
_WAKE_INVOCATIONS=0
task_json=$(_make_pr_comment_task "wake-log1" 300)

apiary_webhook_wake "$task_json" "wake-log1" 2>/dev/null

if [[ -f "${_tmp_dir}/wake.log" ]]; then
    log_content=$(cat "${_tmp_dir}/wake.log")
    assert_contains "$log_content" "wake-log1" "log contains task ID"
    assert_contains "$log_content" "INFO" "log contains INFO level"
else
    _fail "log file exists after wake" "wake.log was not created"
fi

# ═══════════════════════════════════════════════════════════════
# Fallback transport tests
# ═══════════════════════════════════════════════════════════════

describe "Wake — primary path (openclaw CLI present and succeeds)"

_setup
_WAKE_INVOCATIONS=0
task_json=$(_make_pr_comment_task "wake-primary" 400 "org/primary" 10 "Primary path test")

# The mock `openclaw` function defined above is in scope → primary path
apiary_webhook_wake "$task_json" "wake-primary"

assert_eq "$_WAKE_INVOCATIONS" "1" "primary: openclaw sessions_send invoked"
assert_eq "$_WAKE_LAST_SESSION" "test-session-123" "primary: correct session"
assert_contains "$_WAKE_LAST_MESSAGE" "org/primary" "primary: message includes repo"

# ── Fallback: openclaw missing, gateway succeeds ──────────────

describe "Wake — fallback path (openclaw missing, gateway succeeds)"

_setup
_WAKE_INVOCATIONS=0
rm -f "${_tmp_dir}/wake_seen.json"

# Override _wake_send to simulate: openclaw absent, gateway reachable
# We track gateway invocations separately.
_GATEWAY_INVOCATIONS=0
_GATEWAY_LAST_SESSION=""
_GATEWAY_LAST_MESSAGE=""

_wake_send() {
    local session_id="$1"
    local message="$2"
    # Simulate: openclaw not found (skip CLI), call gateway fallback
    _wake_log "INFO" "openclaw CLI not found; using gateway fallback"
    # Simulate successful gateway call
    _GATEWAY_INVOCATIONS=$((_GATEWAY_INVOCATIONS + 1))
    _GATEWAY_LAST_SESSION="$session_id"
    _GATEWAY_LAST_MESSAGE="$message"
    return 0
}

task_json=$(_make_pr_comment_task "wake-fallback" 401 "org/fallback" 11 "Fallback path test")
apiary_webhook_wake "$task_json" "wake-fallback"

assert_eq "$_GATEWAY_INVOCATIONS" "1" "fallback: gateway invoked"
assert_eq "$_GATEWAY_LAST_SESSION" "test-session-123" "fallback: correct session"
assert_contains "$_GATEWAY_LAST_MESSAGE" "org/fallback" "fallback: message includes repo"

# Check log mentions gateway fallback
if [[ -f "${_tmp_dir}/wake.log" ]]; then
    log_content=$(cat "${_tmp_dir}/wake.log")
    assert_contains "$log_content" "gateway fallback" "fallback: log mentions gateway"
fi

# ── Fallback: gateway also fails, logged gracefully ──────────

describe "Wake — fallback failure (openclaw missing, gateway fails)"

_setup
rm -f "${_tmp_dir}/wake_seen.json"
rm -f "${_tmp_dir}/wake.log"

_wake_send() {
    local session_id="$1"
    local message="$2"
    _wake_log "INFO" "openclaw CLI not found; using gateway fallback"
    _wake_log "WARN" "gateway request failed (curl error) url=http://localhost:3223/tools/invoke"
    return 1
}

task_json=$(_make_pr_comment_task "wake-fail" 402 "org/fail" 12 "Fallback fail test")
set +e
apiary_webhook_wake "$task_json" "wake-fail"
rc=$?
set -e

assert_eq "$rc" "0" "fallback-fail: returns 0 (fail-soft)"

if [[ -f "${_tmp_dir}/wake.log" ]]; then
    log_content=$(cat "${_tmp_dir}/wake.log")
    assert_contains "$log_content" "gateway" "fallback-fail: log mentions gateway"
    assert_contains "$log_content" "WARN" "fallback-fail: log has WARN level"
    assert_contains "$log_content" "Failed to wake" "fallback-fail: log records wake failure"
fi

# ── Gateway unit: _wake_send_gateway with mock curl ───────────

describe "Wake — _wake_send_gateway constructs correct request"

_setup
# Re-source to restore original functions after overrides
source "${SCRIPT_DIR}/../bin/apiary-webhook-wake.sh"

# Mock curl: writes captured args to files (survives command substitution subshell)
_curl_capture_dir="${_tmp_dir}/curl_capture"
mkdir -p "$_curl_capture_dir"

curl() {
    local url="" body="" auth=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d) body="$2"; shift 2 ;;
            -H)
                if [[ "$2" == Authorization:* ]]; then
                    auth="$2"
                fi
                shift 2
                ;;
            -o|-w|--max-time|--connect-timeout|-X) shift 2 ;;
            -s|-S) shift ;;
            *) url="$1"; shift ;;
        esac
    done
    echo "$url" > "${_curl_capture_dir}/url"
    echo "$body" > "${_curl_capture_dir}/body"
    echo "$auth" > "${_curl_capture_dir}/auth"
    echo "200"
    return 0
}

export APIARY_WAKE_GATEWAY_URL="http://test-gw:9999"
export APIARY_WAKE_GATEWAY_TOKEN="test-token-abc"
source "${SCRIPT_DIR}/../bin/apiary-webhook-wake.sh"

rm -f "${_curl_capture_dir}"/{url,body,auth}

set +e
_wake_send_gateway "sess-42" "Hello gateway"
rc=$?
set -e

_captured_url=$(cat "${_curl_capture_dir}/url" 2>/dev/null || echo "")
_captured_body=$(cat "${_curl_capture_dir}/body" 2>/dev/null || echo "")
_captured_auth=$(cat "${_curl_capture_dir}/auth" 2>/dev/null || echo "")

assert_eq "$rc" "0" "gateway-unit: returns 0 on HTTP 200"
assert_contains "$_captured_url" "test-gw:9999" "gateway-unit: uses configured gateway host"
assert_contains "$_captured_url" "/tools/invoke" "gateway-unit: correct endpoint path"
assert_contains "$_captured_auth" "Bearer test-token-abc" "gateway-unit: sends bearer token"

# Validate exact payload shape: {"tool":"sessions_send","args":{"sessionKey":"...","message":"..."}}
_body_tool=$(echo "$_captured_body" | jq -r '.tool' 2>/dev/null)
_body_session_key=$(echo "$_captured_body" | jq -r '.args.sessionKey' 2>/dev/null)
_body_message=$(echo "$_captured_body" | jq -r '.args.message' 2>/dev/null)
assert_eq "$_body_tool" "sessions_send" "gateway-unit: payload tool is sessions_send"
assert_eq "$_body_session_key" "sess-42" "gateway-unit: payload sessionKey matches session id"
assert_contains "$_body_message" "Hello gateway" "gateway-unit: payload message contains text"

# ── Gateway unit: HTTP error code ─────────────────────────────

describe "Wake — _wake_send_gateway handles HTTP errors"

_setup
source "${SCRIPT_DIR}/../bin/apiary-webhook-wake.sh"

curl() {
    echo "503"
    return 0
}

set +e
_wake_send_gateway "sess-err" "will fail" 2>/dev/null
rc=$?
set -e

assert_ne "$rc" "0" "gateway-error: returns non-zero on HTTP 503"

# ── Gateway unit: curl failure ────────────────────────────────

describe "Wake — _wake_send_gateway handles curl failure"

_setup
source "${SCRIPT_DIR}/../bin/apiary-webhook-wake.sh"

curl() {
    return 7  # connection refused
}

set +e
_wake_send_gateway "sess-curl" "unreachable" 2>/dev/null
rc=$?
set -e

assert_ne "$rc" "0" "gateway-curl-fail: returns non-zero when curl errors"

# ── Alert gateway unit: _wake_send_alert_gateway payload contract ──

describe "Alert gateway — _wake_send_alert_gateway constructs correct request"

_setup
source "${SCRIPT_DIR}/../bin/apiary-webhook-wake.sh"

_curl_capture_dir="${_tmp_dir}/curl_capture_alert"
mkdir -p "$_curl_capture_dir"

curl() {
    local url="" body="" auth=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d) body="$2"; shift 2 ;;
            -H)
                if [[ "$2" == Authorization:* ]]; then
                    auth="$2"
                fi
                shift 2
                ;;
            -o|-w|--max-time|--connect-timeout|-X) shift 2 ;;
            -s|-S) shift ;;
            *) url="$1"; shift ;;
        esac
    done
    echo "$url" > "${_curl_capture_dir}/url"
    echo "$body" > "${_curl_capture_dir}/body"
    echo "$auth" > "${_curl_capture_dir}/auth"
    echo "200"
    return 0
}

export APIARY_WAKE_GATEWAY_URL="http://test-gw:9999"
export APIARY_WAKE_GATEWAY_TOKEN="test-token-abc"
source "${SCRIPT_DIR}/../bin/apiary-webhook-wake.sh"

rm -f "${_curl_capture_dir}"/{url,body,auth}

set +e
_wake_send_alert_gateway "@myuser" "telegram" "Test alert message"
rc=$?
set -e

_captured_url=$(cat "${_curl_capture_dir}/url" 2>/dev/null || echo "")
_captured_body=$(cat "${_curl_capture_dir}/body" 2>/dev/null || echo "")

assert_eq "$rc" "0" "alert-gw-unit: returns 0 on HTTP 200"
assert_contains "$_captured_url" "/tools/invoke" "alert-gw-unit: correct endpoint path"

# Validate exact payload: {"tool":"message","args":{"action":"send","channel":"...","target":"...","message":"..."}}
_alert_tool=$(echo "$_captured_body" | jq -r '.tool' 2>/dev/null)
_alert_action=$(echo "$_captured_body" | jq -r '.args.action' 2>/dev/null)
_alert_channel=$(echo "$_captured_body" | jq -r '.args.channel' 2>/dev/null)
_alert_target=$(echo "$_captured_body" | jq -r '.args.target' 2>/dev/null)
_alert_message=$(echo "$_captured_body" | jq -r '.args.message' 2>/dev/null)

assert_eq "$_alert_tool" "message" "alert-gw-unit: tool is 'message' (not 'message.send')"
assert_eq "$_alert_action" "send" "alert-gw-unit: args.action is 'send'"
assert_eq "$_alert_channel" "telegram" "alert-gw-unit: args.channel matches"
assert_eq "$_alert_target" "@myuser" "alert-gw-unit: args.target matches"
assert_contains "$_alert_message" "Test alert message" "alert-gw-unit: args.message contains text"

# Ensure no legacy 'text' key in args
_alert_text=$(echo "$_captured_body" | jq -r '.args.text // "ABSENT"' 2>/dev/null)
assert_eq "$_alert_text" "ABSENT" "alert-gw-unit: no legacy 'text' key in args"

# ═══════════════════════════════════════════════════════════════
# Dual-delivery (visible Telegram alert) tests
# ═══════════════════════════════════════════════════════════════

# Mock openclaw to track both sessions_send and message.send calls
_setup_dual_mocks() {
    _WAKE_INVOCATIONS=0
    _WAKE_LAST_MESSAGE=""
    _WAKE_LAST_SESSION=""
    _ALERT_INVOCATIONS=0
    _ALERT_LAST_TARGET=""
    _ALERT_LAST_CHANNEL=""
    _ALERT_LAST_MESSAGE=""

    openclaw() {
        if [[ "${1:-}" == "sessions_send" ]]; then
            shift
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --session) _WAKE_LAST_SESSION="$2"; shift 2 ;;
                    --text) _WAKE_LAST_MESSAGE="$2"; shift 2 ;;
                    *) shift ;;
                esac
            done
            _WAKE_INVOCATIONS=$((_WAKE_INVOCATIONS + 1))
            return 0
        elif [[ "${1:-}" == "message.send" ]]; then
            shift
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --channel) _ALERT_LAST_CHANNEL="$2"; shift 2 ;;
                    --target) _ALERT_LAST_TARGET="$2"; shift 2 ;;
                    --text) _ALERT_LAST_MESSAGE="$2"; shift 2 ;;
                    *) shift ;;
                esac
            done
            _ALERT_INVOCATIONS=$((_ALERT_INVOCATIONS + 1))
            return 0
        fi
        return 0
    }
    export -f openclaw 2>/dev/null || true
}

# ── Dual-send: both wake + alert succeed ──────────────────────

describe "Dual-delivery — both wake and alert succeed"

_setup
export APIARY_WAKE_ALERT_ENABLED="true"
export APIARY_WAKE_ALERT_TELEGRAM="@myuser"
export APIARY_WAKE_ALERT_CHANNEL="telegram"
source "${SCRIPT_DIR}/../bin/apiary-webhook-wake.sh"
_setup_dual_mocks

task_json=$(_make_pr_comment_task "dual-t1" 600 "org/dual-repo" 20 "[urgent] Fix deploy")

apiary_webhook_wake "$task_json" "dual-t1"

assert_eq "$_WAKE_INVOCATIONS" "1" "dual: internal wake invoked"
assert_eq "$_ALERT_INVOCATIONS" "1" "dual: visible alert invoked"
assert_eq "$_ALERT_LAST_CHANNEL" "telegram" "dual: alert uses telegram channel"
assert_eq "$_ALERT_LAST_TARGET" "@myuser" "dual: alert targets configured user"
assert_contains "$_ALERT_LAST_MESSAGE" "org/dual-repo" "dual: alert includes repo"
assert_contains "$_ALERT_LAST_MESSAGE" "#20" "dual: alert includes PR number"
assert_contains "$_ALERT_LAST_MESSAGE" "urgent" "dual: alert includes severity"

# ── Dual-send: alert disabled, only wake fires ───────────────

describe "Dual-delivery — alert disabled, only wake fires"

_setup
export APIARY_WAKE_ALERT_ENABLED="false"
export APIARY_WAKE_ALERT_TELEGRAM="@myuser"
source "${SCRIPT_DIR}/../bin/apiary-webhook-wake.sh"
_setup_dual_mocks

task_json=$(_make_pr_comment_task "dual-t2" 601 "org/no-alert" 21 "No alert expected")

apiary_webhook_wake "$task_json" "dual-t2"

assert_eq "$_WAKE_INVOCATIONS" "1" "alert-off: internal wake invoked"
assert_eq "$_ALERT_INVOCATIONS" "0" "alert-off: no visible alert sent"

# ── Dual-send: alert enabled but no telegram target, only wake fires ─

describe "Dual-delivery — alert enabled but no telegram target"

_setup
export APIARY_WAKE_ALERT_ENABLED="true"
export APIARY_WAKE_ALERT_TELEGRAM=""
source "${SCRIPT_DIR}/../bin/apiary-webhook-wake.sh"
_setup_dual_mocks

task_json=$(_make_pr_comment_task "dual-t3" 602 "org/no-tgt" 22 "Missing target")

apiary_webhook_wake "$task_json" "dual-t3"

assert_eq "$_WAKE_INVOCATIONS" "1" "no-target: internal wake invoked"
assert_eq "$_ALERT_INVOCATIONS" "0" "no-target: no visible alert sent"

# ── Dual-send: alert fails but wake still succeeds ──────────

describe "Dual-delivery — alert failure does not crash, wake still succeeds"

_setup
export APIARY_WAKE_ALERT_ENABLED="true"
export APIARY_WAKE_ALERT_TELEGRAM="@failuser"
export APIARY_WAKE_ALERT_CHANNEL="telegram"
source "${SCRIPT_DIR}/../bin/apiary-webhook-wake.sh"
_WAKE_INVOCATIONS=0
_ALERT_INVOCATIONS=0

# Mock: sessions_send succeeds, message.send fails
openclaw() {
    if [[ "${1:-}" == "sessions_send" ]]; then
        shift
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --session) _WAKE_LAST_SESSION="$2"; shift 2 ;;
                --text) _WAKE_LAST_MESSAGE="$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        _WAKE_INVOCATIONS=$((_WAKE_INVOCATIONS + 1))
        return 0
    elif [[ "${1:-}" == "message.send" ]]; then
        _ALERT_INVOCATIONS=$((_ALERT_INVOCATIONS + 1))
        return 1  # simulate failure
    fi
    return 0
}
export -f openclaw 2>/dev/null || true

# Also need to make gateway fallback fail for alert
_wake_send_alert_gateway() {
    return 1
}

task_json=$(_make_pr_comment_task "dual-t4" 603 "org/alert-fail" 23 "Alert will fail")

set +e
apiary_webhook_wake "$task_json" "dual-t4"
rc=$?
set -e

assert_eq "$rc" "0" "alert-fail: returns 0 (fail-soft)"
assert_eq "$_WAKE_INVOCATIONS" "1" "alert-fail: internal wake still succeeded"

# Verify log records alert failure
if [[ -f "${_tmp_dir}/wake.log" ]]; then
    log_content=$(cat "${_tmp_dir}/wake.log")
    assert_contains "$log_content" "Failed to send visible alert" "alert-fail: log records alert failure"
    assert_contains "$log_content" "Woke session" "alert-fail: log records wake success"
fi

# ── Dual-send: wake fails, alert succeeds → still marks seen (dedupe) ──

describe "Dual-delivery — wake fails, alert succeeds, event marked seen"

_setup
export APIARY_WAKE_ALERT_ENABLED="true"
export APIARY_WAKE_ALERT_TELEGRAM="@wake-fail-user"
export APIARY_WAKE_ALERT_CHANNEL="telegram"
source "${SCRIPT_DIR}/../bin/apiary-webhook-wake.sh"
_WAKE_INVOCATIONS=0
_ALERT_INVOCATIONS=0

# Mock: sessions_send FAILS, message.send SUCCEEDS
openclaw() {
    if [[ "${1:-}" == "sessions_send" ]]; then
        _WAKE_INVOCATIONS=$((_WAKE_INVOCATIONS + 1))
        return 1  # simulate wake failure
    elif [[ "${1:-}" == "message.send" ]]; then
        shift
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --channel) _ALERT_LAST_CHANNEL="$2"; shift 2 ;;
                --target) _ALERT_LAST_TARGET="$2"; shift 2 ;;
                --text) _ALERT_LAST_MESSAGE="$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        _ALERT_INVOCATIONS=$((_ALERT_INVOCATIONS + 1))
        return 0  # alert succeeds
    fi
    return 0
}
export -f openclaw 2>/dev/null || true

# Also make gateway fallback fail for wake
_wake_send_gateway() {
    return 1
}

task_json=$(_make_pr_comment_task "dual-wf1" 700 "org/wake-fail" 30 "Wake will fail, alert ok")

apiary_webhook_wake "$task_json" "dual-wf1"
assert_eq "$_ALERT_INVOCATIONS" "1" "wake-fail-alert-ok: alert was sent"

# Key assertion: event must be marked seen even though wake failed
# Second call should be deduped (alert succeeded → seen marker written)
_ALERT_INVOCATIONS=0
apiary_webhook_wake "$task_json" "dual-wf1"
assert_eq "$_ALERT_INVOCATIONS" "0" "wake-fail-alert-ok: second alert deduped (seen marker written on first alert success)"

# Verify log records wake failure and alert success
if [[ -f "${_tmp_dir}/wake.log" ]]; then
    log_content=$(cat "${_tmp_dir}/wake.log")
    assert_contains "$log_content" "Failed to wake" "wake-fail-alert-ok: log records wake failure"
    assert_contains "$log_content" "Sent visible alert" "wake-fail-alert-ok: log records alert success"
fi

# ── Dual-send: both fail → event NOT marked seen (retry on next poll) ──

describe "Dual-delivery — both fail, event not marked seen (allows retry)"

_setup
export APIARY_WAKE_ALERT_ENABLED="true"
export APIARY_WAKE_ALERT_TELEGRAM="@both-fail-user"
export APIARY_WAKE_ALERT_CHANNEL="telegram"
source "${SCRIPT_DIR}/../bin/apiary-webhook-wake.sh"
_WAKE_INVOCATIONS=0
_ALERT_INVOCATIONS=0

# Mock: both transports fail
openclaw() {
    if [[ "${1:-}" == "sessions_send" ]]; then
        _WAKE_INVOCATIONS=$((_WAKE_INVOCATIONS + 1))
        return 1
    elif [[ "${1:-}" == "message.send" ]]; then
        _ALERT_INVOCATIONS=$((_ALERT_INVOCATIONS + 1))
        return 1
    fi
    return 0
}
export -f openclaw 2>/dev/null || true
_wake_send_gateway() { return 1; }
_wake_send_alert_gateway() { return 1; }

task_json=$(_make_pr_comment_task "dual-bf1" 701 "org/both-fail" 31 "Both will fail")

set +e
apiary_webhook_wake "$task_json" "dual-bf1"
rc=$?
set -e

assert_eq "$rc" "0" "both-fail: returns 0 (fail-soft)"

# Key assertion: event NOT marked seen → second attempt should NOT be deduped
_WAKE_INVOCATIONS=0
_ALERT_INVOCATIONS=0
apiary_webhook_wake "$task_json" "dual-bf1"
assert_eq "$_WAKE_INVOCATIONS" "1" "both-fail: second wake attempted (not deduped)"
assert_eq "$_ALERT_INVOCATIONS" "1" "both-fail: second alert attempted (not deduped)"

# ── Dual-send: dedupe prevents second alert ──────────────────

describe "Dual-delivery — dedupe prevents duplicate alert"

_setup
export APIARY_WAKE_ALERT_ENABLED="true"
export APIARY_WAKE_ALERT_TELEGRAM="@dedup-user"
source "${SCRIPT_DIR}/../bin/apiary-webhook-wake.sh"
_setup_dual_mocks

task_json=$(_make_pr_comment_task "dual-t5" 604 "org/dedup" 24 "Dedup test")

apiary_webhook_wake "$task_json" "dual-t5"
assert_eq "$_WAKE_INVOCATIONS" "1" "dedup-dual: first wake sent"
assert_eq "$_ALERT_INVOCATIONS" "1" "dedup-dual: first alert sent"

# Second call with same task+comment should be deduped (both wake and alert)
apiary_webhook_wake "$task_json" "dual-t5"
assert_eq "$_WAKE_INVOCATIONS" "1" "dedup-dual: second wake deduped"
assert_eq "$_ALERT_INVOCATIONS" "1" "dedup-dual: second alert deduped"

# ── Dual-send: severity icon mapping ─────────────────────────

describe "Dual-delivery — severity icon in alert message"

_setup
export APIARY_WAKE_ALERT_ENABLED="true"
export APIARY_WAKE_ALERT_TELEGRAM="@icon-user"
source "${SCRIPT_DIR}/../bin/apiary-webhook-wake.sh"
_setup_dual_mocks

task_json=$(_make_pr_comment_task "dual-t6" 605 "org/icon" 25 "[high] Needs attention")
apiary_webhook_wake "$task_json" "dual-t6"
assert_contains "$_ALERT_LAST_MESSAGE" "high" "icon: high severity in alert"


# ═══════════════════════════════════════════════════════════════
# P2: whitespace .body falls back to event_payload
# ═══════════════════════════════════════════════════════════════

# Build a task where .body is whitespace but event_payload has valid PR comment data
_make_whitespace_body_task() {
    local task_id="${1:-task-ws}"
    local comment_id="${2:-42}"
    local repo="${3:-org/ws-repo}"
    local pr_num="${4:-7}"
    local comment_body="${5:-Whitespace body test}"

    jq -n \
        --arg tid "$task_id" \
        --argjson cid "$comment_id" \
        --arg repo "$repo" \
        --argjson pr "$pr_num" \
        --arg cbody "$comment_body" \
        --arg curl "https://github.com/${repo}/pull/${pr_num}#issuecomment-${comment_id}" \
        --arg purl "https://github.com/${repo}/pull/${pr_num}" \
        '{
            id: $tid,
            type: "webhook_handler",
            payload: {
                event_payload: {
                    action: "created",
                    body: "   ",
                    comment: {
                        id: $cid,
                        html_url: $curl,
                        body: $cbody
                    },
                    issue: {
                        number: $pr,
                        pull_request: {
                            html_url: $purl
                        }
                    },
                    repository: {
                        full_name: $repo
                    }
                }
            }
        }'
}

_make_empty_string_body_task() {
    local task_id="${1:-task-es}"
    local comment_id="${2:-42}"
    local repo="${3:-org/es-repo}"
    local pr_num="${4:-7}"
    local comment_body="${5:-Empty string body test}"

    jq -n \
        --arg tid "$task_id" \
        --argjson cid "$comment_id" \
        --arg repo "$repo" \
        --argjson pr "$pr_num" \
        --arg cbody "$comment_body" \
        --arg curl "https://github.com/${repo}/pull/${pr_num}#issuecomment-${comment_id}" \
        --arg purl "https://github.com/${repo}/pull/${pr_num}" \
        '{
            id: $tid,
            type: "webhook_handler",
            payload: {
                event_payload: {
                    action: "created",
                    body: "",
                    comment: {
                        id: $cid,
                        html_url: $curl,
                        body: $cbody
                    },
                    issue: {
                        number: $pr,
                        pull_request: {
                            html_url: $purl
                        }
                    },
                    repository: {
                        full_name: $repo
                    }
                }
            }
        }'
}

describe "P2 Parser — whitespace .body falls back to event_payload"

_setup
task_json=$(_make_whitespace_body_task "p2-ws" 8001 "org/ws-test" 80 "Whitespace body comment")

set +e
parsed=$(_wake_parse_pr_comment "$task_json" 2>/dev/null)
rc=$?
set -e

assert_eq "$rc" "0" "p2-ws: parses successfully (falls back to event_payload)"
assert_eq "$(echo "$parsed" | jq -r '.comment_id')" "8001" "p2-ws: extracts comment_id"
assert_eq "$(echo "$parsed" | jq -r '.repo')" "org/ws-test" "p2-ws: extracts repo"
assert_eq "$(echo "$parsed" | jq -r '.pr_number')" "80" "p2-ws: extracts pr_number"
assert_eq "$(echo "$parsed" | jq -r '.comment_body')" "Whitespace body comment" "p2-ws: extracts comment body"


describe "P2 Parser — empty string .body falls back to event_payload"

_setup
task_json=$(_make_empty_string_body_task "p2-es" 8002 "org/es-test" 81 "Empty string body")

set +e
parsed=$(_wake_parse_pr_comment "$task_json" 2>/dev/null)
rc=$?
set -e

assert_eq "$rc" "0" "p2-es: parses successfully (falls back to event_payload)"
assert_eq "$(echo "$parsed" | jq -r '.comment_id')" "8002" "p2-es: extracts comment_id"
assert_eq "$(echo "$parsed" | jq -r '.repo')" "org/es-test" "p2-es: extracts repo"


describe "P2 Wake — whitespace .body still delivers wake correctly"

_setup
_WAKE_INVOCATIONS=0
task_json=$(_make_whitespace_body_task "p2-wake" 8003 "org/ws-wake" 82 "Wake with whitespace body")

apiary_webhook_wake "$task_json" "p2-wake"

assert_eq "$_WAKE_INVOCATIONS" "1" "p2-wake: wake sent despite whitespace .body"
assert_contains "$_WAKE_LAST_MESSAGE" "org/ws-wake" "p2-wake: message includes repo"
assert_contains "$_WAKE_LAST_MESSAGE" "#82" "p2-wake: message includes PR number"


# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════

test_summary
