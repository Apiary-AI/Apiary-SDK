#!/usr/bin/env bash
# apiary-webhook-wake.sh — Bridge: wake OpenClaw session on actionable webhook tasks.
#
# When the daemon detects a new pending webhook_handler task, this module
# parses PR comment metadata from the event payload and invokes
# `openclaw sessions_send` to auto-wake the assistant with actionable context.
#
# Features:
#   - Idempotent: tracks seen task+comment IDs to prevent duplicate wakeups
#   - Fail-soft: parsing/invoke failures are logged but never crash the daemon
#   - Configurable: enable/disable, session target, log path, debounce
#
# Environment variables:
#   APIARY_WAKE_ENABLED          — "true" to enable (default: "false")
#   APIARY_WAKE_SESSION          — OpenClaw session ID to wake (required if enabled)
#   APIARY_WAKE_LOG              — Log file path (default: ~/.config/apiary/wake.log)
#   APIARY_WAKE_DEBOUNCE_SECS   — Min seconds between wakes for same comment (default: 5)
#   APIARY_CONFIG_DIR            — Config directory (default: ~/.config/apiary)
#
# Fallback transport (when openclaw CLI is not in PATH):
#   APIARY_WAKE_GATEWAY_URL      — OpenClaw gateway base URL (default: http://localhost:3223)
#   APIARY_WAKE_GATEWAY_TOKEN    — Bearer token for gateway auth (optional)
#   APIARY_WAKE_GATEWAY_TIMEOUT  — HTTP timeout in seconds (default: 5)
#
# Visible alert (dual-delivery: sends user-visible Telegram message alongside internal wake):
#   APIARY_WAKE_ALERT_ENABLED    — "true" to enable visible Telegram alerts (default: "false")
#   APIARY_WAKE_ALERT_TELEGRAM   — Telegram chat ID or username target (required if alert enabled)
#   APIARY_WAKE_ALERT_CHANNEL    — Optional channel name for routing (default: "telegram")

# ── Source Shell SDK (guard against re-sourcing) ────────────────
if [[ -z "${_APIARY_SDK_LOADED:-}" ]]; then
    _src="${BASH_SOURCE[0]}"
    while [[ -L "$_src" ]]; do
        _dir="$(cd "$(dirname "$_src")" && pwd)"
        _src="$(readlink "$_src")"
        [[ "$_src" != /* ]] && _src="$_dir/$_src"
    done
    SCRIPT_DIR="$(cd "$(dirname "$_src")" && pwd)"
    unset _src _dir
    # shellcheck source=_resolve-sdk.sh
    source "${SCRIPT_DIR}/_resolve-sdk.sh"
    _apiary_find_shell_sdk || return 1
    # shellcheck source=../../shell/src/apiary-sdk.sh
    source "$_APIARY_SHELL_SDK_PATH"
    _APIARY_SDK_LOADED=1
fi

# ── Configuration ──────────────────────────────────────────────

_WAKE_ENABLED="${APIARY_WAKE_ENABLED:-false}"
_WAKE_SESSION="${APIARY_WAKE_SESSION:-}"
_WAKE_CONFIG_DIR="${APIARY_CONFIG_DIR:-${HOME}/.config/apiary}"
_WAKE_LOG="${APIARY_WAKE_LOG:-${_WAKE_CONFIG_DIR}/wake.log}"
_WAKE_DEBOUNCE_SECS="${APIARY_WAKE_DEBOUNCE_SECS:-5}"
_WAKE_SEEN_FILE="${_WAKE_CONFIG_DIR}/wake_seen.json"
_WAKE_GATEWAY_URL="${APIARY_WAKE_GATEWAY_URL:-http://localhost:3223}"
_WAKE_GATEWAY_TOKEN="${APIARY_WAKE_GATEWAY_TOKEN:-}"
_WAKE_GATEWAY_TIMEOUT="${APIARY_WAKE_GATEWAY_TIMEOUT:-5}"
_WAKE_ALERT_ENABLED="${APIARY_WAKE_ALERT_ENABLED:-false}"
_WAKE_ALERT_TELEGRAM="${APIARY_WAKE_ALERT_TELEGRAM:-}"
_WAKE_ALERT_CHANNEL="${APIARY_WAKE_ALERT_CHANNEL:-telegram}"

# ── Logging ────────────────────────────────────────────────────

_wake_log() {
    local level="$1"
    shift
    local ts
    ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%s')
    local msg="[${ts}] [webhook-wake] [${level}] $*"
    echo "$msg" >&2
    # Append to log file (best-effort)
    if [[ -n "$_WAKE_LOG" ]]; then
        mkdir -p "$(dirname "$_WAKE_LOG")" 2>/dev/null || true
        echo "$msg" >> "$_WAKE_LOG" 2>/dev/null || true
    fi
}

# ── Deduplication ──────────────────────────────────────────────

# Load the seen-IDs map. Format: { "key": timestamp, ... }
_wake_load_seen() {
    if [[ -f "$_WAKE_SEEN_FILE" ]]; then
        cat "$_WAKE_SEEN_FILE" 2>/dev/null || echo '{}'
    else
        echo '{}'
    fi
}

# Check if a key was already seen within the debounce window.
# Returns 0 (true = already seen), 1 (false = not seen / expired).
_wake_is_seen() {
    local key="$1"
    local seen_json
    seen_json=$(_wake_load_seen)

    local last_ts
    last_ts=$(echo "$seen_json" | jq -r --arg k "$key" '.[$k] // 0' 2>/dev/null) || last_ts=0

    if [[ "$last_ts" == "null" ]] || [[ "$last_ts" == "0" ]]; then
        return 1
    fi

    local now
    now=$(date +%s)
    local elapsed=$(( now - last_ts ))
    if (( elapsed < _WAKE_DEBOUNCE_SECS )); then
        return 0  # still within debounce window
    fi
    return 1  # expired
}

# Mark a key as seen with current timestamp.
_wake_mark_seen() {
    local key="$1"
    local now
    now=$(date +%s)

    mkdir -p "$(dirname "$_WAKE_SEEN_FILE")" 2>/dev/null || true

    local seen_json
    seen_json=$(_wake_load_seen)

    # Add/update the key and prune entries older than 1 hour
    local cutoff=$(( now - 3600 ))
    echo "$seen_json" | jq --arg k "$key" --argjson ts "$now" --argjson cut "$cutoff" \
        '. + {($k): $ts} | with_entries(select(.value > $cut))' \
        > "$_WAKE_SEEN_FILE" 2>/dev/null || true
}

# ── Payload parsing ────────────────────────────────────────────

# Parse GitHub PR comment metadata from a webhook_handler task payload.
# Outputs JSON with extracted fields, or empty string on parse failure.
#
# Expected payload structure (from WebhookRouteEvaluator + GitHubConnector):
#   { "event_payload": { "action": "...", "repository": {...}, "sender": {...},
#                         "body": { "action": "created", "comment": { ... }, "issue": { ... }, ... } } }
#
# The GitHubConnector wraps the raw GitHub JSON inside event_payload.body.
# For backwards compatibility we also check event_payload directly (legacy / flat shape).
_wake_parse_pr_comment() {
    local task_json="$1"

    # Extract event_payload from nested task payload
    local event_payload
    event_payload=$(echo "$task_json" | jq -r '.payload.event_payload // empty' 2>/dev/null) || return 1
    [[ -z "$event_payload" ]] && return 1

    # Resolve the GitHub event body.  The GitHubConnector nests the raw
    # webhook JSON under event_payload.body; fall back to event_payload
    # itself for flat/legacy payloads.
    local github_body
    github_body=$(echo "$event_payload" | jq -r '.body // empty' 2>/dev/null) || true
    # Fall back to event_payload when .body is absent, null, empty, or
    # whitespace-only.  Without this trim check, a whitespace .body would
    # shadow valid nested fields in event_payload (P2 fix).
    if [[ -z "$github_body" ]] || [[ "$github_body" == "null" ]] || [[ ! "$github_body" =~ [^[:space:]] ]]; then
        github_body="$event_payload"
    fi

    # Check if this is a PR comment event (issue_comment on a PR, or pull_request_review_comment)
    local action comment_id comment_url comment_body
    local pr_number pr_url repo_full_name

    action=$(echo "$github_body" | jq -r '.action // empty' 2>/dev/null) || return 1

    # Try pull_request_review_comment format first
    comment_id=$(echo "$github_body" | jq -r '.comment.id // empty' 2>/dev/null) || true
    comment_url=$(echo "$github_body" | jq -r '.comment.html_url // empty' 2>/dev/null) || true
    comment_body=$(echo "$github_body" | jq -r '.comment.body // empty' 2>/dev/null) || true

    # Distinguish PR comments from regular issue comments.
    # pull_request_review_comment events have .pull_request at top level.
    # issue_comment events on PRs have .issue.pull_request (object with href).
    # Regular issue_comment events have neither — reject those.
    local has_pr
    has_pr=$(echo "$github_body" | jq -r '
        if .pull_request != null then "pr_review"
        elif .issue.pull_request != null then "issue_on_pr"
        else empty end' 2>/dev/null) || true

    if [[ -z "$has_pr" ]]; then
        return 1  # Not a PR-related comment; skip
    fi

    # PR number — try .pull_request.number, then .issue.number
    pr_number=$(echo "$github_body" | jq -r '.pull_request.number // .issue.number // empty' 2>/dev/null) || true
    pr_url=$(echo "$github_body" | jq -r '.pull_request.html_url // .issue.pull_request.html_url // empty' 2>/dev/null) || true
    repo_full_name=$(echo "$github_body" | jq -r '.repository.full_name // empty' 2>/dev/null) || true

    # Must have at least a comment ID to be actionable
    if [[ -z "$comment_id" ]]; then
        return 1
    fi

    # Extract severity hints from comment body (e.g., [urgent], [critical], @bot)
    local severity="normal"
    if [[ -n "$comment_body" ]]; then
        local body_lower
        body_lower=$(echo "$comment_body" | tr '[:upper:]' '[:lower:]')
        if [[ "$body_lower" == *"[critical]"* ]] || [[ "$body_lower" == *"[urgent]"* ]]; then
            severity="urgent"
        elif [[ "$body_lower" == *"[high]"* ]]; then
            severity="high"
        elif [[ "$body_lower" == *"[low]"* ]]; then
            severity="low"
        fi
    fi

    # Extract trusted control-plane invoke passthrough fields.
    # Canonical contract is top-level .invoke.* with legacy payload fallback.
    local invoke_instructions invoke_context
    invoke_instructions=$(echo "$task_json" | jq -r '.invoke.instructions // .payload.invoke.instructions // empty' 2>/dev/null) || invoke_instructions=""
    invoke_context=$(echo "$task_json" | jq -c '.invoke.context // .payload.invoke.context // null' 2>/dev/null) || invoke_context="null"

    # Build result JSON
    jq -n \
        --arg action "$action" \
        --arg comment_id "$comment_id" \
        --arg comment_url "$comment_url" \
        --arg comment_body "$comment_body" \
        --arg pr_number "${pr_number:-}" \
        --arg pr_url "${pr_url:-}" \
        --arg repo "$repo_full_name" \
        --arg severity "$severity" \
        --arg invoke_instructions "$invoke_instructions" \
        --argjson invoke_context "$invoke_context" \
        '{
            action: $action,
            comment_id: $comment_id,
            comment_url: $comment_url,
            comment_body: $comment_body,
            pr_number: $pr_number,
            pr_url: $pr_url,
            repo: $repo,
            severity: $severity,
            invoke: {
                instructions: $invoke_instructions,
                context: $invoke_context
            }
        }' 2>/dev/null || return 1
}

# ── Wake invocation ────────────────────────────────────────────

# Fallback: POST directly to the OpenClaw local gateway HTTP API.
# Endpoint: POST {gateway}/tools/invoke  body: {"tool":"sessions_send","args":{"sessionKey":"...","message":"..."}}
_wake_send_gateway() {
    local session_id="$1"
    local message="$2"

    if ! command -v curl >/dev/null 2>&1; then
        _wake_log "WARN" "curl not found; gateway fallback unavailable"
        return 1
    fi

    local url="${_WAKE_GATEWAY_URL%/}/tools/invoke"

    local -a curl_args=(
        -s -S
        -X POST
        -H "Content-Type: application/json"
        --max-time "$_WAKE_GATEWAY_TIMEOUT"
        --connect-timeout "$_WAKE_GATEWAY_TIMEOUT"
    )
    if [[ -n "$_WAKE_GATEWAY_TOKEN" ]]; then
        curl_args+=(-H "Authorization: Bearer ${_WAKE_GATEWAY_TOKEN}")
    fi

    local body
    body=$(jq -n --arg key "$session_id" --arg msg "$message" \
        '{"tool":"sessions_send","args":{"sessionKey":$key,"message":$msg}}' 2>/dev/null) || \
        body="{\"tool\":\"sessions_send\",\"args\":{\"sessionKey\":\"${session_id}\",\"message\":\"wake\"}}"

    local http_code
    http_code=$(curl "${curl_args[@]}" -o /dev/null -w '%{http_code}' -d "$body" "$url" 2>/dev/null) || {
        _wake_log "WARN" "gateway request failed (curl error) url=${url}"
        return 1
    }

    if [[ "$http_code" -ge 200 ]] && [[ "$http_code" -lt 300 ]]; then
        return 0
    fi

    _wake_log "WARN" "gateway returned HTTP ${http_code} for ${url}"
    return 1
}

# Invoke openclaw sessions_send to wake the target session.
# Falls back to direct gateway HTTP POST when the CLI is unavailable.
_wake_send() {
    local session_id="$1"
    local message="$2"

    # Primary: try openclaw CLI
    if command -v openclaw >/dev/null 2>&1; then
        if openclaw sessions_send --session "$session_id" --text "$message" 2>/dev/null; then
            return 0
        fi
        _wake_log "WARN" "openclaw sessions_send failed; trying gateway fallback"
    else
        _wake_log "INFO" "openclaw CLI not found; using gateway fallback"
    fi

    # Fallback: direct HTTP to local gateway
    _wake_send_gateway "$session_id" "$message"
}

# ── Visible alert (Telegram) ──────────────────────────────────

# Send a short user-visible alert via openclaw message.send (Telegram).
# Returns 0 on success, 1 on failure (caller should treat as non-fatal).
_wake_send_alert() {
    local target="$1"
    local channel="$2"
    local message="$3"

    # Primary: try openclaw CLI message.send
    if command -v openclaw >/dev/null 2>&1; then
        if openclaw message.send --channel "$channel" --target "$target" --text "$message" 2>/dev/null; then
            return 0
        fi
        _wake_log "WARN" "openclaw message.send failed; trying gateway fallback for alert"
    else
        _wake_log "INFO" "openclaw CLI not found; using gateway fallback for alert"
    fi

    # Fallback: direct HTTP to local gateway
    _wake_send_alert_gateway "$target" "$channel" "$message"
}

# Fallback: POST alert via gateway /tools/invoke with message tool (action=send).
_wake_send_alert_gateway() {
    local target="$1"
    local channel="$2"
    local message="$3"

    if ! command -v curl >/dev/null 2>&1; then
        _wake_log "WARN" "curl not found; alert gateway fallback unavailable"
        return 1
    fi

    local url="${_WAKE_GATEWAY_URL%/}/tools/invoke"

    local -a curl_args=(
        -s -S
        -X POST
        -H "Content-Type: application/json"
        --max-time "$_WAKE_GATEWAY_TIMEOUT"
        --connect-timeout "$_WAKE_GATEWAY_TIMEOUT"
    )
    if [[ -n "$_WAKE_GATEWAY_TOKEN" ]]; then
        curl_args+=(-H "Authorization: Bearer ${_WAKE_GATEWAY_TOKEN}")
    fi

    local body
    body=$(jq -n --arg ch "$channel" --arg tgt "$target" --arg msg "$message" \
        '{"tool":"message","args":{"action":"send","channel":$ch,"target":$tgt,"message":$msg}}' 2>/dev/null) || \
        body="{\"tool\":\"message\",\"args\":{\"action\":\"send\",\"channel\":\"${channel}\",\"target\":\"${target}\",\"message\":\"alert\"}}"

    local http_code
    http_code=$(curl "${curl_args[@]}" -o /dev/null -w '%{http_code}' -d "$body" "$url" 2>/dev/null) || {
        _wake_log "WARN" "alert gateway request failed (curl error) url=${url}"
        return 1
    }

    if [[ "$http_code" -ge 200 ]] && [[ "$http_code" -lt 300 ]]; then
        return 0
    fi

    _wake_log "WARN" "alert gateway returned HTTP ${http_code} for ${url}"
    return 1
}

# ── Main entry point ──────────────────────────────────────────

# Called by the daemon for each new webhook_handler task.
# Parses PR comment metadata, deduplicates, and wakes the session.
#
# Arguments:
#   $1 — task JSON (full task object)
#   $2 — task ID
#
# Returns 0 always (fail-soft).
apiary_webhook_wake() {
    local task_json="${1:-}"
    local task_id="${2:-}"

    # Guard: feature must be enabled
    if [[ "$_WAKE_ENABLED" != "true" ]]; then
        return 0
    fi

    # Guard: session target must be set
    if [[ -z "$_WAKE_SESSION" ]]; then
        _wake_log "WARN" "APIARY_WAKE_SESSION not set; skipping wake for task ${task_id}"
        return 0
    fi

    # Guard: need task JSON
    if [[ -z "$task_json" ]]; then
        _wake_log "WARN" "Empty task JSON for task ${task_id}"
        return 0
    fi

    # Parse PR comment metadata (fail-soft)
    local parsed
    if ! parsed=$(_wake_parse_pr_comment "$task_json"); then
        _wake_log "DEBUG" "Task ${task_id} is not a parseable PR comment webhook; skipping"
        return 0
    fi

    if [[ -z "$parsed" ]]; then
        _wake_log "DEBUG" "Task ${task_id} produced empty parse result; skipping"
        return 0
    fi

    # Extract dedup key: task_id + comment_id
    local comment_id
    comment_id=$(echo "$parsed" | jq -r '.comment_id // empty' 2>/dev/null) || comment_id=""
    local dedup_key="${task_id}:${comment_id}"

    # Check idempotency
    if _wake_is_seen "$dedup_key"; then
        _wake_log "DEBUG" "Already woke for ${dedup_key}; skipping (debounce)"
        return 0
    fi

    # Build wake message
    local repo pr_number comment_url severity comment_body invoke_instructions invoke_context
    repo=$(echo "$parsed" | jq -r '.repo // "unknown"' 2>/dev/null) || repo="unknown"
    pr_number=$(echo "$parsed" | jq -r '.pr_number // ""' 2>/dev/null) || pr_number=""
    comment_url=$(echo "$parsed" | jq -r '.comment_url // ""' 2>/dev/null) || comment_url=""
    severity=$(echo "$parsed" | jq -r '.severity // "normal"' 2>/dev/null) || severity="normal"
    comment_body=$(echo "$parsed" | jq -r '.comment_body // ""' 2>/dev/null) || comment_body=""
    invoke_instructions=$(echo "$parsed" | jq -r '.invoke.instructions // ""' 2>/dev/null) || invoke_instructions=""
    invoke_context=$(echo "$parsed" | jq -c '.invoke.context // null' 2>/dev/null) || invoke_context="null"

    # Truncate comment body for the wake message (max 500 chars)
    if [[ ${#comment_body} -gt 500 ]]; then
        comment_body="${comment_body:0:497}..."
    fi

    local message
    message=$(printf 'Webhook task %s: PR comment on %s #%s [%s]\nComment: %s\nURL: %s' \
        "$task_id" "$repo" "$pr_number" "$severity" "$comment_body" "$comment_url")

    # Trusted control-plane passthrough for invoke instructions/context.
    if [[ -n "$invoke_instructions" ]]; then
        message+=$(printf '\nInvoke instructions: %s' "$invoke_instructions")
    fi
    if [[ "$invoke_context" != "null" ]]; then
        message+=$(printf '\nInvoke context: %s' "$invoke_context")
    fi

    # Send internal wake (fail-soft)
    local wake_ok=0
    if _wake_send "$_WAKE_SESSION" "$message"; then
        _wake_log "INFO" "Woke session ${_WAKE_SESSION} for task ${task_id} (comment ${comment_id})"
        wake_ok=1
    else
        _wake_log "WARN" "Failed to wake session ${_WAKE_SESSION} for task ${task_id}"
    fi

    # Send visible Telegram alert (dual-delivery, fail-soft)
    local alert_ok=0
    if [[ "$_WAKE_ALERT_ENABLED" == "true" ]] && [[ -n "$_WAKE_ALERT_TELEGRAM" ]]; then
        # Build a short user-visible alert message
        local alert_icon="🔔"
        case "$severity" in
            urgent) alert_icon="🚨" ;;
            high)   alert_icon="⚠️" ;;
            low)    alert_icon="ℹ️" ;;
        esac

        local alert_body
        if [[ ${#comment_body} -gt 200 ]]; then
            alert_body="${comment_body:0:197}..."
        else
            alert_body="$comment_body"
        fi

        local alert_msg
        alert_msg=$(printf '%s PR comment on %s #%s [%s]\n%s\n%s' \
            "$alert_icon" "$repo" "$pr_number" "$severity" "$alert_body" "$comment_url")

        if _wake_send_alert "$_WAKE_ALERT_TELEGRAM" "$_WAKE_ALERT_CHANNEL" "$alert_msg"; then
            _wake_log "INFO" "Sent visible alert for task ${task_id} (comment ${comment_id})"
            alert_ok=1
        else
            _wake_log "WARN" "Failed to send visible alert for task ${task_id}; wake still proceeded"
        fi
    fi

    # Mark seen when any outbound delivery succeeds (wake OR alert).
    # Prevents repeated alert spam when one transport is down.
    # If both deliveries fail, the event remains unseen for retry.
    if [[ "$wake_ok" -eq 1 ]] || [[ "$alert_ok" -eq 1 ]]; then
        _wake_mark_seen "$dedup_key"
    fi

    return 0
}
