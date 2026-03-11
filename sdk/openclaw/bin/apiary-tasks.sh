#!/usr/bin/env bash
# apiary-tasks.sh — Task operations for OpenClaw skill.
#
# Thin wrappers around Shell SDK functions, formatted for
# OpenClaw's LLM consumption with human-readable output.
#
# Functions:
#   apiary_oc_poll       — Poll for available tasks
#   apiary_oc_claim      — Claim a task
#   apiary_oc_progress   — Report task progress
#   apiary_oc_complete   — Complete a task
#   apiary_oc_fail       — Fail a task
#   apiary_oc_create     — Create a new task

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

# ── Poll ────────────────────────────────────────────────────────
# apiary_oc_poll — Poll for available tasks and output a readable list.
#   Uses APIARY_HIVE_ID and optional APIARY_CAPABILITIES.
apiary_oc_poll() {
    local hive_id="${APIARY_HIVE_ID:?APIARY_HIVE_ID must be set}"
    local capability="${1:-}"

    local -a poll_args=("$hive_id")
    [[ -n "$capability" ]] && poll_args+=(-c "$capability")

    local tasks
    tasks=$(apiary_poll_tasks "${poll_args[@]}") || return $?

    # Check for empty results
    local count
    count=$(echo "$tasks" | jq 'if type == "array" then length else 0 end' 2>/dev/null || echo 0)

    if [[ "$count" -eq 0 ]]; then
        echo "No tasks available."
        return $APIARY_OK
    fi

    echo "Available tasks ($count):"
    echo ""
    echo "$tasks" | jq -r '.[] | "  [\(.id)] type=\(.type) priority=\(.priority // "normal") created=\(.created_at // "unknown")"'

    return $APIARY_OK
}

# ── Claim ───────────────────────────────────────────────────────
# apiary_oc_claim TASK_ID — Claim a task. Handles 409 Conflict gracefully.
apiary_oc_claim() {
    local task_id="${1:?usage: apiary_oc_claim TASK_ID}"
    local hive_id="${APIARY_HIVE_ID:?APIARY_HIVE_ID must be set}"

    local result rc=0
    result=$(apiary_claim_task "$hive_id" "$task_id" 2>&1) || rc=$?

    if [[ $rc -eq $APIARY_ERR_CONFLICT ]]; then
        echo "Task $task_id was already claimed by another agent."
        return $APIARY_ERR_CONFLICT
    elif [[ $rc -ne 0 ]]; then
        echo "Failed to claim task $task_id: $result" >&2
        return $rc
    fi

    echo "Task $task_id claimed successfully."
    echo "$result" | jq '.' 2>/dev/null || echo "$result"
    return $APIARY_OK
}

# ── Progress ────────────────────────────────────────────────────
# apiary_oc_progress TASK_ID PERCENT [MESSAGE] — Report progress.
apiary_oc_progress() {
    local task_id="${1:?usage: apiary_oc_progress TASK_ID PERCENT [MESSAGE]}"
    local percent="${2:?usage: apiary_oc_progress TASK_ID PERCENT [MESSAGE]}"
    local message="${3:-}"
    local hive_id="${APIARY_HIVE_ID:?APIARY_HIVE_ID must be set}"

    local -a args=(-p "$percent")
    [[ -n "$message" ]] && args+=(-m "$message")

    apiary_update_progress "$hive_id" "$task_id" "${args[@]}" >/dev/null || return $?
    echo "Progress updated: ${percent}%${message:+ — $message}"
    return $APIARY_OK
}

# ── Complete ────────────────────────────────────────────────────
# apiary_oc_complete TASK_ID [RESULT_JSON] — Complete a task.
apiary_oc_complete() {
    local task_id="${1:?usage: apiary_oc_complete TASK_ID [RESULT_JSON]}"
    local result_json="${2:-}"
    local hive_id="${APIARY_HIVE_ID:?APIARY_HIVE_ID must be set}"

    local -a args=()
    [[ -n "$result_json" ]] && args+=(-r "$result_json")

    apiary_complete_task "$hive_id" "$task_id" "${args[@]}" >/dev/null || return $?
    echo "Task $task_id completed successfully."
    return $APIARY_OK
}

# ── Fail ────────────────────────────────────────────────────────
# apiary_oc_fail TASK_ID [ERROR_JSON] — Fail a task.
apiary_oc_fail() {
    local task_id="${1:?usage: apiary_oc_fail TASK_ID [ERROR_JSON]}"
    local error_json="${2:-}"
    local hive_id="${APIARY_HIVE_ID:?APIARY_HIVE_ID must be set}"

    local -a args=()
    [[ -n "$error_json" ]] && args+=(-e "$error_json")

    apiary_fail_task "$hive_id" "$task_id" "${args[@]}" >/dev/null || return $?
    echo "Task $task_id marked as failed."
    return $APIARY_OK
}

# ── Create ──────────────────────────────────────────────────────
# apiary_oc_create TYPE [PAYLOAD_JSON] [OPTIONS...] — Create a new task.
#   OPTIONS: -p PRIORITY -a TARGET_AGENT_ID -c TARGET_CAPABILITY
apiary_oc_create() {
    local task_type="${1:?usage: apiary_oc_create TYPE [PAYLOAD_JSON] [OPTIONS...]}"
    shift
    local payload=""
    if [[ $# -gt 0 && "${1}" != -* ]]; then
        payload="$1"
        shift
    fi
    local hive_id="${APIARY_HIVE_ID:?APIARY_HIVE_ID must be set}"

    local -a args=(-t "$task_type")
    [[ -n "$payload" ]] && args+=(-d "$payload")

    # Pass through remaining options
    while [[ $# -gt 0 ]]; do
        args+=("$1")
        shift
    done

    local result
    result=$(apiary_create_task "$hive_id" "${args[@]}") || return $?
    local task_id
    task_id=$(echo "$result" | jq -r '.id // "unknown"' 2>/dev/null)
    echo "Task created: $task_id (type: $task_type)"
    return $APIARY_OK
}
