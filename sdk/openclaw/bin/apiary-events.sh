#!/usr/bin/env bash
# apiary-events.sh — Event operations for OpenClaw skill.
#
# Wrappers for Apiary event subscription and publishing.
# Uses _apiary_request directly for event endpoints not yet in the Shell SDK.
#
# Functions:
#   apiary_oc_events_subscribe     — Subscribe to an event type
#   apiary_oc_events_unsubscribe   — Unsubscribe from an event type
#   apiary_oc_events_poll_raw      — Poll for new events (raw JSON array)
#   apiary_oc_events_commit_cursor — Persist event cursor after successful handling
#   apiary_oc_events_poll          — Poll for new events (human-readable)
#   apiary_oc_events_publish       — Publish an event
#   apiary_oc_events_list          — List current subscriptions

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

# ── Cursor persistence ─────────────────────────────────────────
_apiary_oc_cursor_file() {
    echo "${APIARY_CONFIG_DIR:-${HOME}/.config/apiary}/cursor.json"
}

_apiary_oc_load_cursor() {
    local cursor_file
    cursor_file=$(_apiary_oc_cursor_file)
    if [[ -f "$cursor_file" ]]; then
        local cursor
        if cursor=$(jq -r '.last_event_id // empty' "$cursor_file" 2>/dev/null); then
            echo "$cursor"
        else
            echo "[apiary-events] warning: malformed cursor.json, skipping cursor" >&2
        fi
    fi
}

_apiary_oc_save_cursor() {
    local last_event_id="$1"
    local cursor_file
    cursor_file=$(_apiary_oc_cursor_file)
    mkdir -p "$(dirname "$cursor_file")"
    jq -n --arg id "$last_event_id" '{last_event_id: $id}' > "$cursor_file"
}

# ── Subscribe ───────────────────────────────────────────────────
# apiary_oc_events_subscribe EVENT_TYPE [SCOPE] — Subscribe to an event type.
#   SCOPE: "hive" (default) or "apiary"
apiary_oc_events_subscribe() {
    local event_type="${1:?usage: apiary_oc_events_subscribe EVENT_TYPE [SCOPE]}"
    local scope="${2:-hive}"

    local body
    body=$(_apiary_build_json "event_type" "$event_type" "scope" "$scope") || return $APIARY_ERR

    local result
    result=$(_apiary_request POST "/api/v1/agents/subscriptions" "$body") || return $?
    echo "Subscribed to: $event_type (scope: $scope)"
    return $APIARY_OK
}

# ── Unsubscribe ─────────────────────────────────────────────────
# apiary_oc_events_unsubscribe EVENT_TYPE — Unsubscribe from an event type.
apiary_oc_events_unsubscribe() {
    local event_type="${1:?usage: apiary_oc_events_unsubscribe EVENT_TYPE}"

    local encoded_type
    encoded_type=$(_apiary_urlencode "$event_type")

    _apiary_request DELETE "/api/v1/agents/subscriptions/${encoded_type}" || return $?
    echo "Unsubscribed from: $event_type"
    return $APIARY_OK
}

# ── List subscriptions ──────────────────────────────────────────
# apiary_oc_events_list — List current event subscriptions.
apiary_oc_events_list() {
    local result
    result=$(_apiary_request GET "/api/v1/agents/subscriptions") || return $?

    local count
    count=$(echo "$result" | jq 'if type == "array" then length else 0 end' 2>/dev/null || echo 0)

    if [[ "$count" -eq 0 ]]; then
        echo "No active subscriptions."
        return $APIARY_OK
    fi

    echo "Active subscriptions ($count):"
    echo ""
    echo "$result" | jq -r '.[] | "  \(.event_type) (scope: \(.scope // "hive"))"'

    return $APIARY_OK
}

# ── Poll events ─────────────────────────────────────────────────
# apiary_oc_events_poll_raw — Poll for new events since last cursor.
# Outputs raw JSON array. Cursor is NOT advanced here; caller must commit
# only after events are successfully handled.
apiary_oc_events_poll_raw() {
    local hive_id="${APIARY_HIVE_ID:?APIARY_HIVE_ID must be set}"

    local params=()
    local last_event_id
    last_event_id=$(_apiary_oc_load_cursor) || last_event_id=""
    [[ -n "$last_event_id" ]] && params+=("last_event_id=$(_apiary_urlencode "$last_event_id")")

    local qs=""
    if [[ ${#params[@]} -gt 0 ]]; then
        qs="?$(IFS='&'; echo "${params[*]}")"
    fi

    local result
    result=$(_apiary_request GET "/api/v1/hives/${hive_id}/events/poll${qs}") || return $?

    echo "$result"
    return $APIARY_OK
}

# apiary_oc_events_commit_cursor EVENT_ID — Persist cursor after successful handling.
apiary_oc_events_commit_cursor() {
    local event_id="${1:-}"
    [[ -n "$event_id" ]] || return $APIARY_OK
    _apiary_oc_save_cursor "$event_id"
    return $APIARY_OK
}

# apiary_oc_events_poll — Human-readable wrapper around raw event polling.
apiary_oc_events_poll() {
    local result
    result=$(apiary_oc_events_poll_raw) || return $?

    local count
    count=$(echo "$result" | jq 'if type == "array" then length else 0 end' 2>/dev/null || echo 0)

    if [[ "$count" -eq 0 ]]; then
        echo "No new events."
        return $APIARY_OK
    fi

    echo "New events ($count):"
    echo ""
    echo "$result" | jq -r '.[] | "  [\(.id)] type=\(.type) from=\(.source_agent_id // "system") at=\(.created_at // "unknown")"'

    # Human wrapper treats display as handling complete.
    local new_cursor
    new_cursor=$(echo "$result" | jq -r '.[-1].id // empty' 2>/dev/null)
    [[ -n "$new_cursor" ]] && apiary_oc_events_commit_cursor "$new_cursor"

    return $APIARY_OK
}

# ── Publish ─────────────────────────────────────────────────────
# apiary_oc_events_publish EVENT_TYPE PAYLOAD_JSON — Publish an event.
apiary_oc_events_publish() {
    local event_type="${1:?usage: apiary_oc_events_publish EVENT_TYPE PAYLOAD_JSON}"
    local payload="${2:-"{}"}"
    local hive_id="${APIARY_HIVE_ID:?APIARY_HIVE_ID must be set}"

    local body
    body=$(_apiary_build_json "type" "$event_type" "payload" "$payload") || return $APIARY_ERR

    local result
    result=$(_apiary_request POST "/api/v1/hives/${hive_id}/events" "$body") || return $?
    local event_id
    event_id=$(echo "$result" | jq -r '.id // "unknown"' 2>/dev/null)
    echo "Event published: $event_id (type: $event_type)"
    return $APIARY_OK
}
