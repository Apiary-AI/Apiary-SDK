#!/usr/bin/env bash
# apiary-sdk.sh — Pure Bash client for the Apiary v1 API.
#
# Source this file in your script:
#   source apiary-sdk.sh
#
# Dependencies: bash 4+, curl, jq
# Env vars:
#   APIARY_BASE_URL  — API base URL (required, no trailing slash)
#   APIARY_TOKEN     — Bearer token (set automatically by auth helpers)
#   APIARY_AGENT_REFRESH_TOKEN — Agent refresh token (set by register/login/refresh helpers)
#   APIARY_TIMEOUT   — Request timeout in seconds (default: 30)
#   APIARY_TOKEN_FILE — Path to persisted token file (default: ~/.config/apiary/token)
#   APIARY_DEBUG     — Set to 1 for verbose curl output on stderr

# ── Version ──────────────────────────────────────────────────────
APIARY_SDK_VERSION="0.1.0"

# ── Exit codes ───────────────────────────────────────────────────
readonly APIARY_OK=0
readonly APIARY_ERR=1
readonly APIARY_ERR_VALIDATION=2   # 422
readonly APIARY_ERR_AUTH=3         # 401
readonly APIARY_ERR_PERMISSION=4   # 403
readonly APIARY_ERR_NOT_FOUND=5    # 404
readonly APIARY_ERR_CONFLICT=6     # 409
readonly APIARY_ERR_DEPS=7         # missing dependencies
readonly APIARY_ERR_RATE_LIMIT=8   # 429

# Rate-limit retry-after value (set by _apiary_request on 429 responses)
_APIARY_RETRY_AFTER=""

# ── Dependency check ─────────────────────────────────────────────
apiary_check_deps() {
    local missing=()
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    command -v jq   >/dev/null 2>&1 || missing+=("jq")
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "apiary-sdk: missing required dependencies: ${missing[*]}" >&2
        return $APIARY_ERR_DEPS
    fi
    # Check bash version
    if [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
        echo "apiary-sdk: requires bash 4+, found ${BASH_VERSION}" >&2
        return $APIARY_ERR_DEPS
    fi
    return $APIARY_OK
}

# ── Internal helpers ─────────────────────────────────────────────

# _apiary_debug MSG — print to stderr when APIARY_DEBUG=1
_apiary_debug() {
    [[ "${APIARY_DEBUG:-0}" == "1" ]] && echo "[apiary-debug] $*" >&2
    return 0
}

# _apiary_err MSG — print error to stderr
_apiary_err() {
    echo "apiary-sdk: $*" >&2
}

# _apiary_exit_code HTTP_STATUS — map HTTP status to exit code
_apiary_exit_code() {
    local status="$1"
    case "$status" in
        2[0-9][0-9]) echo $APIARY_OK ;;
        401)         echo $APIARY_ERR_AUTH ;;
        403)         echo $APIARY_ERR_PERMISSION ;;
        404)         echo $APIARY_ERR_NOT_FOUND ;;
        409)         echo $APIARY_ERR_CONFLICT ;;
        422)         echo $APIARY_ERR_VALIDATION ;;
        429)         echo $APIARY_ERR_RATE_LIMIT ;;
        *)           echo $APIARY_ERR ;;
    esac
}

# _apiary_request METHOD PATH [JSON_BODY]
#   Sends HTTP request, unwraps envelope, prints data to stdout.
#   Returns mapped exit code. Errors go to stderr.
_apiary_request() {
    local method="$1"
    local path="$2"
    local body="${3:-}"
    local url="${APIARY_BASE_URL:?APIARY_BASE_URL must be set}${path}"
    local timeout="${APIARY_TIMEOUT:-30}"

    local _header_file
    _header_file=$(mktemp "${TMPDIR:-/tmp}/apiary-sdk-headers.XXXXXXXXXX") || {
        _apiary_err "failed to create temp file for response headers"
        return $APIARY_ERR
    }

    local -a curl_args=(
        --silent
        --show-error
        --max-time "$timeout"
        --write-out '\n%{http_code}'
        -D "$_header_file"
        -H 'Accept: application/json'
    )

    if [[ -n "${APIARY_TOKEN:-}" ]]; then
        curl_args+=(-H "Authorization: Bearer ${APIARY_TOKEN}")
    fi

    if [[ -n "$body" ]]; then
        curl_args+=(-H 'Content-Type: application/json' -d "$body")
    fi

    [[ "${APIARY_DEBUG:-0}" == "1" ]] && curl_args+=(--verbose) 2>/dev/null

    _apiary_debug "$method $url"
    [[ -n "$body" ]] && _apiary_debug "body: $body"

    # Execute request — capture both body and status code
    local raw_output
    raw_output=$(curl -X "$method" "${curl_args[@]}" "$url" 2>&${_apiary_debug_fd:-2}) || {
        _apiary_err "curl failed (network error or timeout)"
        rm -f "$_header_file" 2>/dev/null || true
        return $APIARY_ERR
    }

    # Extract Retry-After header for rate-limit handling
    _APIARY_RETRY_AFTER=""
    local _ra_line
    _ra_line=$(grep -i '^retry-after:' "$_header_file" 2>/dev/null | head -1) || true
    if [[ -n "${_ra_line:-}" ]]; then
        _APIARY_RETRY_AFTER=$(echo "$_ra_line" | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
    fi
    rm -f "$_header_file" 2>/dev/null || true

    # Split response: last line is HTTP status code
    local http_status
    http_status=$(echo "$raw_output" | tail -n1)
    local response_body
    response_body=$(echo "$raw_output" | sed '$d')

    _apiary_debug "HTTP $http_status"

    # Handle 204 No Content
    if [[ "$http_status" == "204" ]]; then
        return $APIARY_OK
    fi

    # Verify JSON response — always fail on non-JSON, even for 2xx
    if ! echo "$response_body" | jq empty 2>/dev/null; then
        _apiary_err "HTTP ${http_status}: non-JSON response"
        [[ -n "$response_body" ]] && _apiary_err "${response_body:0:200}"
        return $APIARY_ERR
    fi

    local exit_code
    exit_code=$(_apiary_exit_code "$http_status")

    if [[ "$exit_code" -ne 0 ]]; then
        # Extract error message(s) from envelope
        local errors
        errors=$(echo "$response_body" | jq -r '.errors // empty')
        if [[ -n "$errors" && "$errors" != "null" ]]; then
            # Handle array of errors
            if echo "$response_body" | jq -e '.errors | type == "array"' >/dev/null 2>&1; then
                echo "$response_body" | jq -r '.errors[] | "[\(.code // "error")] \(.message // "Unknown error")\(if .field then " (field: \(.field))" else "" end)"' >&2
            # Handle object-style Laravel errors
            elif echo "$response_body" | jq -e '.errors | type == "object"' >/dev/null 2>&1; then
                echo "$response_body" | jq -r '.errors | to_entries[] | .key as $field | (.value | if type == "array" then .[] else . end) | "[validation_error] \(.) (field: \($field))"' >&2
            fi
        else
            _apiary_err "HTTP ${http_status}"
        fi
        # Still output the full response body for programmatic consumption
        echo "$response_body"
        return "$exit_code"
    fi

    # Success — unwrap envelope: output .data
    local data
    data=$(echo "$response_body" | jq '.data // empty')
    if [[ -n "$data" && "$data" != "null" ]]; then
        echo "$data"
    fi

    return $APIARY_OK
}

# _apiary_urlencode VALUE — percent-encode a value for use in query strings.
#   Uses jq's @uri filter (RFC 3986).
_apiary_urlencode() {
    jq -rn --arg v "$1" '$v | @uri'
}

# _apiary_build_json KEY1 VAL1 KEY2 VAL2 ...
#   Build JSON object from key-value pairs, skipping empty values.
#   Values starting with '{' or '[' and booleans/null are treated as raw JSON.
#   Digit-only strings are treated as strings by default (safe for secrets/IDs).
#   Append ':n' to a key name to force numeric treatment, e.g. "priority:n" "3".
_apiary_build_json() {
    local json="{}"
    while [[ $# -ge 2 ]]; do
        local key="$1" val="$2"
        shift 2
        [[ -z "$val" ]] && continue
        # Explicit numeric hint: key ends with ':n'
        local force_raw=false
        if [[ "$key" == *":n" ]]; then
            key="${key%:n}"
            force_raw=true
        fi
        # Validate forced-numeric values — only allow numbers (reject arrays, objects, booleans, null)
        if $force_raw && ! [[ "$val" =~ ^-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$ ]]; then
            _apiary_err "build_json: invalid numeric value for '$key': $val"
            return $APIARY_ERR
        fi
        # Detect raw JSON values (objects, arrays, booleans, null, or forced numeric)
        if $force_raw || [[ "$val" =~ ^[\{\[] ]] || [[ "$val" == "true" || "$val" == "false" || "$val" == "null" ]]; then
            json=$(echo "$json" | jq --arg k "$key" --argjson v "$val" '. + {($k): $v}') || {
                _apiary_err "build_json: invalid JSON value for '$key': $val"
                return $APIARY_ERR
            }
        else
            json=$(echo "$json" | jq --arg k "$key" --arg v "$val" '. + {($k): $v}')
        fi
    done
    echo "$json"
}

# ── Agent Auth ───────────────────────────────────────────────────

# apiary_register — register a new agent and store the token.
#   -n NAME  -h HIVE_ID  -s SECRET  [-a APIARY_ID] [-t TYPE] [-c CAPABILITIES_JSON] [-m METADATA_JSON]
#   Outputs full data envelope (agent + token) to stdout.
apiary_register() {
    local name="" hive_id="" secret="" apiary_id="" agent_type="" capabilities="" metadata=""
    local OPTIND OPTARG opt
    while getopts "n:h:s:a:t:c:m:" opt; do
        case "$opt" in
            n) name="$OPTARG" ;;
            h) hive_id="$OPTARG" ;;
            s) secret="$OPTARG" ;;
            a) apiary_id="$OPTARG" ;;
            t) agent_type="$OPTARG" ;;
            c) capabilities="$OPTARG" ;;
            m) metadata="$OPTARG" ;;
            *) _apiary_err "register: unknown option -$opt"; return $APIARY_ERR ;;
        esac
    done

    if [[ -z "$name" || -z "$hive_id" || -z "$secret" ]]; then
        _apiary_err "register: -n NAME, -h HIVE_ID, and -s SECRET are required"
        return $APIARY_ERR
    fi

    local body
    body=$(_apiary_build_json \
        "name" "$name" \
        "hive_id" "$hive_id" \
        "secret" "$secret" \
        "apiary_id" "$apiary_id" \
        "type" "$agent_type" \
        "capabilities" "$capabilities" \
        "metadata" "$metadata"
    ) || return $APIARY_ERR

    local result
    result=$(_apiary_request POST "/api/v1/agents/register" "$body") || return $?

    # Auto-store auth credentials
    APIARY_TOKEN=$(echo "$result" | jq -r '.token // empty')
    APIARY_AGENT_REFRESH_TOKEN=$(echo "$result" | jq -r '.refresh_token // empty')
    echo "$result"
    return $APIARY_OK
}

# apiary_login — authenticate an existing agent.
#   -i AGENT_ID  -s SECRET
apiary_login() {
    local agent_id="" secret=""
    local OPTIND OPTARG opt
    while getopts "i:s:" opt; do
        case "$opt" in
            i) agent_id="$OPTARG" ;;
            s) secret="$OPTARG" ;;
            *) _apiary_err "login: unknown option -$opt"; return $APIARY_ERR ;;
        esac
    done

    if [[ -z "$agent_id" || -z "$secret" ]]; then
        _apiary_err "login: -i AGENT_ID and -s SECRET are required"
        return $APIARY_ERR
    fi

    local body
    body=$(_apiary_build_json "agent_id" "$agent_id" "secret" "$secret") || return $APIARY_ERR

    local result
    result=$(_apiary_request POST "/api/v1/agents/login" "$body") || return $?

    APIARY_TOKEN=$(echo "$result" | jq -r '.token // empty')
    APIARY_AGENT_REFRESH_TOKEN=$(echo "$result" | jq -r '.refresh_token // empty')
    echo "$result"
    return $APIARY_OK
}

# apiary_refresh_agent_token — refresh an expired/expiring token without the agent secret.
#   -i AGENT_ID  -r REFRESH_TOKEN
apiary_refresh_agent_token() {
    local agent_id="" refresh_token=""
    local OPTIND OPTARG opt
    while getopts "i:r:" opt; do
        case "$opt" in
            i) agent_id="$OPTARG" ;;
            r) refresh_token="$OPTARG" ;;
            *) _apiary_err "refresh_agent_token: unknown option -$opt"; return $APIARY_ERR ;;
        esac
    done

    if [[ -z "$agent_id" || -z "$refresh_token" ]]; then
        _apiary_err "refresh_agent_token: -i AGENT_ID and -r REFRESH_TOKEN are required"
        return $APIARY_ERR
    fi

    local body
    body=$(_apiary_build_json "agent_id" "$agent_id" "refresh_token" "$refresh_token") || return $APIARY_ERR

    local result
    result=$(_apiary_request POST "/api/v1/agents/token/refresh" "$body") || return $?

    APIARY_TOKEN=$(echo "$result" | jq -r '.token // empty')
    APIARY_AGENT_REFRESH_TOKEN=$(echo "$result" | jq -r '.refresh_token // empty')
    echo "$result"
    return $APIARY_OK
}

# apiary_logout — revoke the current token.
#   Always clears APIARY_TOKEN regardless of HTTP/network outcome.
apiary_logout() {
    local rc=0
    _apiary_request POST "/api/v1/agents/logout" || rc=$?
    APIARY_TOKEN=""
    return $rc
}

# ── Token file persistence ────────────────────────────────────────
# Optional file-based token storage for multi-command CLI workflows.
# Override the file location with APIARY_TOKEN_FILE env var.

_apiary_token_file() {
    echo "${APIARY_TOKEN_FILE:-${HOME}/.config/apiary/token}"
}

# apiary_save_token — persist APIARY_TOKEN to a file (mode 600).
apiary_save_token() {
    local tf
    tf=$(_apiary_token_file)
    if [[ -n "${APIARY_TOKEN:-}" ]]; then
        mkdir -p "$(dirname "$tf")"
        printf '%s\n' "$APIARY_TOKEN" > "$tf"
        chmod 600 "$tf"
    fi
}

# apiary_load_token — load token from file if APIARY_TOKEN is unset.
apiary_load_token() {
    if [[ -n "${APIARY_TOKEN:-}" ]]; then
        return 0
    fi
    local tf
    tf=$(_apiary_token_file)
    if [[ -f "$tf" ]]; then
        APIARY_TOKEN=$(<"$tf")
        export APIARY_TOKEN
    fi
}

# apiary_clear_token_file — remove the persisted token file.
apiary_clear_token_file() {
    rm -f "$(_apiary_token_file)"
}

# apiary_me — get the authenticated agent's profile.
apiary_me() {
    _apiary_request GET "/api/v1/agents/me"
}

# ── Agent Lifecycle ──────────────────────────────────────────────

# apiary_heartbeat — send a heartbeat signal.
#   [-m METADATA_JSON]
apiary_heartbeat() {
    local metadata=""
    local OPTIND OPTARG opt
    while getopts "m:" opt; do
        case "$opt" in
            m) metadata="$OPTARG" ;;
            *) _apiary_err "heartbeat: unknown option -$opt"; return $APIARY_ERR ;;
        esac
    done

    local body="{}"
    if [[ -n "$metadata" ]]; then
        body=$(_apiary_build_json "metadata" "$metadata") || return $APIARY_ERR
    fi

    _apiary_request POST "/api/v1/agents/heartbeat" "$body"
}

# apiary_update_status — update the agent's status.
#   STATUS (online|busy|idle|offline|error)
apiary_update_status() {
    local status="${1:?usage: apiary_update_status STATUS}"
    local body
    body=$(_apiary_build_json "status" "$status") || return $APIARY_ERR
    _apiary_request PATCH "/api/v1/agents/status" "$body"
}

# ── Drain Mode ───────────────────────────────────────────────────

# apiary_enter_drain — enter drain mode (stop accepting new tasks).
#   [-r REASON] [-d DEADLINE_MINUTES]
apiary_enter_drain() {
    local reason="" deadline_minutes=""
    local OPTIND OPTARG opt
    while getopts "r:d:" opt; do
        case "$opt" in
            r) reason="$OPTARG" ;;
            d) deadline_minutes="$OPTARG" ;;
            *) _apiary_err "enter_drain: unknown option -$opt"; return $APIARY_ERR ;;
        esac
    done

    local body
    body=$(_apiary_build_json "reason" "$reason" "deadline_minutes:n" "$deadline_minutes") || return $APIARY_ERR
    _apiary_request POST "/api/v1/agents/drain" "$body"
}

# apiary_exit_drain — exit drain mode.
apiary_exit_drain() {
    _apiary_request POST "/api/v1/agents/undrain"
}

# apiary_drain_status — get current drain status.
apiary_drain_status() {
    _apiary_request GET "/api/v1/agents/drain"
}

# ── Key Rotation ─────────────────────────────────────────────────

# apiary_rotate_key — rotate the agent's API key.
#   -s NEW_SECRET  [-g GRACE_PERIOD_MINUTES]
#   Returns new token; auto-stores in APIARY_TOKEN.
apiary_rotate_key() {
    local new_secret="" grace_period_minutes=""
    local OPTIND OPTARG opt
    while getopts "s:g:" opt; do
        case "$opt" in
            s) new_secret="$OPTARG" ;;
            g) grace_period_minutes="$OPTARG" ;;
            *) _apiary_err "rotate_key: unknown option -$opt"; return $APIARY_ERR ;;
        esac
    done

    if [[ -z "$new_secret" ]]; then
        _apiary_err "rotate_key: -s NEW_SECRET is required"
        return $APIARY_ERR
    fi

    local body
    body=$(_apiary_build_json \
        "new_secret" "$new_secret" \
        "grace_period_minutes:n" "$grace_period_minutes"
    ) || return $APIARY_ERR

    local result
    result=$(_apiary_request POST "/api/v1/agents/key/rotate" "$body") || return $?

    APIARY_TOKEN=$(echo "$result" | jq -r '.token // empty')
    APIARY_AGENT_REFRESH_TOKEN=$(echo "$result" | jq -r '.refresh_token // empty')
    export APIARY_TOKEN APIARY_AGENT_REFRESH_TOKEN

    echo "$result"
    return $APIARY_OK
}

# apiary_revoke_previous_key — immediately revoke the grace-period key.
apiary_revoke_previous_key() {
    _apiary_request POST "/api/v1/agents/key/revoke"
}

# apiary_key_status — get current key rotation status.
apiary_key_status() {
    _apiary_request GET "/api/v1/agents/key/status"
}

# ── Pool Health ───────────────────────────────────────────────────

# apiary_get_pool_health — get pool health metrics for a hive.
#   HIVE_ID  [-w WINDOW_MINUTES]
apiary_get_pool_health() {
    local hive_id="${1:?usage: apiary_get_pool_health HIVE_ID [-w WINDOW_MINUTES]}"
    shift
    local window=""
    local OPTIND OPTARG opt
    while getopts "w:" opt; do
        case "$opt" in
            w) window="$OPTARG" ;;
            *) _apiary_err "get_pool_health: unknown option -$opt"; return $APIARY_ERR ;;
        esac
    done

    local params=()
    [[ -n "$window" ]] && params+=("window=$(_apiary_urlencode "$window")")
    local qs=""
    if [[ ${#params[@]} -gt 0 ]]; then
        qs="?$(IFS='&'; echo "${params[*]}")"
    fi

    _apiary_request GET "/api/v1/hives/${hive_id}/pool/health${qs}"
}

# ── Tasks ────────────────────────────────────────────────────────

# apiary_create_task — create a task in a hive.
#   HIVE_ID  -t TYPE  [-p PRIORITY] [-a TARGET_AGENT_ID] [-c TARGET_CAPABILITY]
#   [-d PAYLOAD_JSON] [-T TIMEOUT_SECONDS] [-r MAX_RETRIES] [-P PARENT_TASK_ID]
#   [-x CONTEXT_REFS_JSON] [-g GUARANTEE] [-e EXPIRES_AT]
#   [-I INVOKE_INSTRUCTIONS] [-X INVOKE_CONTEXT_JSON]
apiary_create_task() {
    local hive_id="${1:?usage: apiary_create_task HIVE_ID -t TYPE ...}"
    shift
    local task_type="" priority="" target_agent_id="" target_capability=""
    local payload="" timeout_seconds="" max_retries="" parent_task_id="" context_refs=""
    local guarantee="" expires_at="" invoke_instructions="" invoke_context=""
    local OPTIND OPTARG opt
    while getopts "t:p:a:c:d:T:r:P:x:g:e:I:X:" opt; do
        case "$opt" in
            t) task_type="$OPTARG" ;;
            p) priority="$OPTARG" ;;
            a) target_agent_id="$OPTARG" ;;
            c) target_capability="$OPTARG" ;;
            d) payload="$OPTARG" ;;
            T) timeout_seconds="$OPTARG" ;;
            r) max_retries="$OPTARG" ;;
            P) parent_task_id="$OPTARG" ;;
            x) context_refs="$OPTARG" ;;
            g) guarantee="$OPTARG" ;;
            e) expires_at="$OPTARG" ;;
            I) invoke_instructions="$OPTARG" ;;
            X) invoke_context="$OPTARG" ;;
            *) _apiary_err "create_task: unknown option -$opt"; return $APIARY_ERR ;;
        esac
    done

    if [[ -z "$task_type" ]]; then
        _apiary_err "create_task: -t TYPE is required"
        return $APIARY_ERR
    fi

    local invoke_json=""
    if [[ -n "$invoke_instructions" || -n "$invoke_context" ]]; then
        invoke_json=$(_apiary_build_json \
            "instructions" "$invoke_instructions" \
            "context" "$invoke_context"
        ) || return $APIARY_ERR
    fi

    local body
    body=$(_apiary_build_json \
        "type" "$task_type" \
        "priority:n" "$priority" \
        "target_agent_id" "$target_agent_id" \
        "target_capability" "$target_capability" \
        "payload" "$payload" \
        "timeout_seconds:n" "$timeout_seconds" \
        "max_retries:n" "$max_retries" \
        "parent_task_id" "$parent_task_id" \
        "context_refs" "$context_refs" \
        "guarantee" "$guarantee" \
        "expires_at" "$expires_at" \
        "invoke" "$invoke_json"
    ) || return $APIARY_ERR

    _apiary_request POST "/api/v1/hives/${hive_id}/tasks" "$body"
}

# apiary_poll_tasks — poll for available tasks.
#   HIVE_ID  [-c CAPABILITY] [-l LIMIT]
apiary_poll_tasks() {
    local hive_id="${1:?usage: apiary_poll_tasks HIVE_ID [-c CAPABILITY] [-l LIMIT]}"
    shift
    local capability="" limit=""
    local OPTIND OPTARG opt
    while getopts "c:l:" opt; do
        case "$opt" in
            c) capability="$OPTARG" ;;
            l) limit="$OPTARG" ;;
            *) _apiary_err "poll_tasks: unknown option -$opt"; return $APIARY_ERR ;;
        esac
    done

    local params=()
    [[ -n "$capability" ]] && params+=("capability=$(_apiary_urlencode "$capability")")
    [[ -n "$limit" ]]      && params+=("limit=$(_apiary_urlencode "$limit")")
    local qs=""
    if [[ ${#params[@]} -gt 0 ]]; then
        qs="?$(IFS='&'; echo "${params[*]}")"
    fi

    _apiary_request GET "/api/v1/hives/${hive_id}/tasks/poll${qs}"
}

# apiary_claim_task — atomically claim a pending task.
#   HIVE_ID  TASK_ID
apiary_claim_task() {
    local hive_id="${1:?usage: apiary_claim_task HIVE_ID TASK_ID}"
    local task_id="${2:?usage: apiary_claim_task HIVE_ID TASK_ID}"
    _apiary_request PATCH "/api/v1/hives/${hive_id}/tasks/${task_id}/claim"
}

# apiary_update_progress — report progress on a claimed task.
#   HIVE_ID  TASK_ID  -p PROGRESS  [-m STATUS_MESSAGE]
apiary_update_progress() {
    local hive_id="${1:?usage: apiary_update_progress HIVE_ID TASK_ID -p PROGRESS}"
    local task_id="${2:?usage: apiary_update_progress HIVE_ID TASK_ID -p PROGRESS}"
    shift 2
    local progress="" status_message=""
    local OPTIND OPTARG opt
    while getopts "p:m:" opt; do
        case "$opt" in
            p) progress="$OPTARG" ;;
            m) status_message="$OPTARG" ;;
            *) _apiary_err "update_progress: unknown option -$opt"; return $APIARY_ERR ;;
        esac
    done

    if [[ -z "$progress" ]]; then
        _apiary_err "update_progress: -p PROGRESS is required"
        return $APIARY_ERR
    fi

    local body
    body=$(_apiary_build_json "progress:n" "$progress" "status_message" "$status_message") || return $APIARY_ERR
    _apiary_request PATCH "/api/v1/hives/${hive_id}/tasks/${task_id}/progress" "$body"
}

# apiary_complete_task — mark a claimed task as completed.
#   HIVE_ID  TASK_ID  [-r RESULT_JSON] [-m STATUS_MESSAGE]
apiary_complete_task() {
    local hive_id="${1:?usage: apiary_complete_task HIVE_ID TASK_ID}"
    local task_id="${2:?usage: apiary_complete_task HIVE_ID TASK_ID}"
    shift 2
    local result="" status_message=""
    local OPTIND OPTARG opt
    while getopts "r:m:" opt; do
        case "$opt" in
            r) result="$OPTARG" ;;
            m) status_message="$OPTARG" ;;
            *) _apiary_err "complete_task: unknown option -$opt"; return $APIARY_ERR ;;
        esac
    done

    local body
    body=$(_apiary_build_json "result" "$result" "status_message" "$status_message") || return $APIARY_ERR
    _apiary_request PATCH "/api/v1/hives/${hive_id}/tasks/${task_id}/complete" "$body"
}

# apiary_fail_task — mark a claimed task as failed.
#   HIVE_ID  TASK_ID  [-e ERROR_JSON] [-m STATUS_MESSAGE]
apiary_fail_task() {
    local hive_id="${1:?usage: apiary_fail_task HIVE_ID TASK_ID}"
    local task_id="${2:?usage: apiary_fail_task HIVE_ID TASK_ID}"
    shift 2
    local error="" status_message=""
    local OPTIND OPTARG opt
    while getopts "e:m:" opt; do
        case "$opt" in
            e) error="$OPTARG" ;;
            m) status_message="$OPTARG" ;;
            *) _apiary_err "fail_task: unknown option -$opt"; return $APIARY_ERR ;;
        esac
    done

    local body
    body=$(_apiary_build_json "error" "$error" "status_message" "$status_message") || return $APIARY_ERR
    _apiary_request PATCH "/api/v1/hives/${hive_id}/tasks/${task_id}/fail" "$body"
}

# ── Task Replay / Time Travel ─────────────────────────────────────

# apiary_get_task_trace — get the full execution trace for a task.
#   HIVE_ID  TASK_ID
apiary_get_task_trace() {
    local hive_id="${1:?usage: apiary_get_task_trace HIVE_ID TASK_ID}"
    local task_id="${2:?usage: apiary_get_task_trace HIVE_ID TASK_ID}"
    _apiary_request GET "/api/v1/hives/${hive_id}/tasks/${task_id}/trace"
}

# apiary_replay_task — create a replay of a completed/failed/dead_letter/expired task.
#   HIVE_ID  TASK_ID  [-d OVERRIDE_PAYLOAD_JSON]
apiary_replay_task() {
    local hive_id="${1:?usage: apiary_replay_task HIVE_ID TASK_ID}"
    local task_id="${2:?usage: apiary_replay_task HIVE_ID TASK_ID}"
    shift 2
    local override_payload=""
    local OPTIND OPTARG opt
    while getopts "d:" opt; do
        case "$opt" in
            d) override_payload="$OPTARG" ;;
            *) _apiary_err "replay_task: unknown option -$opt"; return $APIARY_ERR ;;
        esac
    done

    local body
    body=$(_apiary_build_json "override_payload" "$override_payload") || return $APIARY_ERR
    _apiary_request POST "/api/v1/hives/${hive_id}/tasks/${task_id}/replay" "$body"
}

# apiary_compare_tasks — compare two tasks by payload, result, and trace.
#   HIVE_ID  TASK_A_ID  TASK_B_ID
apiary_compare_tasks() {
    local hive_id="${1:?usage: apiary_compare_tasks HIVE_ID TASK_A_ID TASK_B_ID}"
    local task_a="${2:?usage: apiary_compare_tasks HIVE_ID TASK_A_ID TASK_B_ID}"
    local task_b="${3:?usage: apiary_compare_tasks HIVE_ID TASK_A_ID TASK_B_ID}"

    local qs="?task_a=$(_apiary_urlencode "$task_a")&task_b=$(_apiary_urlencode "$task_b")"
    _apiary_request GET "/api/v1/hives/${hive_id}/tasks/compare${qs}"
}

# ── Schedules ────────────────────────────────────────────────────

# apiary_list_schedules — list task schedules in a hive.
#   HIVE_ID  [-s STATUS]
apiary_list_schedules() {
    local hive_id="${1:?usage: apiary_list_schedules HIVE_ID [-s STATUS]}"
    shift
    local status=""
    local OPTIND OPTARG opt
    while getopts "s:" opt; do
        case "$opt" in
            s) status="$OPTARG" ;;
            *) _apiary_err "list_schedules: unknown option -$opt"; return $APIARY_ERR ;;
        esac
    done

    local params=()
    [[ -n "$status" ]] && params+=("status=$(_apiary_urlencode "$status")")
    local qs=""
    if [[ ${#params[@]} -gt 0 ]]; then
        qs="?$(IFS='&'; echo "${params[*]}")"
    fi

    _apiary_request GET "/api/v1/hives/${hive_id}/schedules${qs}"
}

# apiary_get_schedule — get a single task schedule.
#   HIVE_ID  SCHEDULE_ID
apiary_get_schedule() {
    local hive_id="${1:?usage: apiary_get_schedule HIVE_ID SCHEDULE_ID}"
    local schedule_id="${2:?usage: apiary_get_schedule HIVE_ID SCHEDULE_ID}"
    _apiary_request GET "/api/v1/hives/${hive_id}/schedules/${schedule_id}"
}

# apiary_create_schedule — create a task schedule.
#   HIVE_ID  -n NAME  -g TRIGGER_TYPE  -t TASK_TYPE
#   [-c CRON_EXPRESSION] [-i INTERVAL_SECONDS] [-R RUN_AT]
#   [-d TASK_PAYLOAD_JSON] [-p TASK_PRIORITY] [-a TASK_TARGET_AGENT_ID]
#   [-C TASK_TARGET_CAPABILITY] [-T TASK_TIMEOUT_SECONDS]
#   [-r TASK_MAX_RETRIES] [-o OVERLAP_POLICY] [-e EXPIRES_AT]
apiary_create_schedule() {
    local hive_id="${1:?usage: apiary_create_schedule HIVE_ID -n NAME -g TRIGGER_TYPE -t TASK_TYPE ...}"
    shift
    local name="" trigger_type="" task_type="" cron_expression="" interval_seconds=""
    local run_at="" task_payload="" task_priority="" task_target_agent_id=""
    local task_target_capability="" task_timeout_seconds="" task_max_retries=""
    local overlap_policy="" expires_at=""
    local OPTIND OPTARG opt
    while getopts "n:g:t:c:i:R:d:p:a:C:T:r:o:e:" opt; do
        case "$opt" in
            n) name="$OPTARG" ;;
            g) trigger_type="$OPTARG" ;;
            t) task_type="$OPTARG" ;;
            c) cron_expression="$OPTARG" ;;
            i) interval_seconds="$OPTARG" ;;
            R) run_at="$OPTARG" ;;
            d) task_payload="$OPTARG" ;;
            p) task_priority="$OPTARG" ;;
            a) task_target_agent_id="$OPTARG" ;;
            C) task_target_capability="$OPTARG" ;;
            T) task_timeout_seconds="$OPTARG" ;;
            r) task_max_retries="$OPTARG" ;;
            o) overlap_policy="$OPTARG" ;;
            e) expires_at="$OPTARG" ;;
            *) _apiary_err "create_schedule: unknown option -$opt"; return $APIARY_ERR ;;
        esac
    done

    if [[ -z "$name" || -z "$trigger_type" || -z "$task_type" ]]; then
        _apiary_err "create_schedule: -n NAME, -g TRIGGER_TYPE, and -t TASK_TYPE are required"
        return $APIARY_ERR
    fi

    local body
    body=$(_apiary_build_json \
        "name" "$name" \
        "trigger_type" "$trigger_type" \
        "task_type" "$task_type" \
        "cron_expression" "$cron_expression" \
        "interval_seconds:n" "$interval_seconds" \
        "run_at" "$run_at" \
        "task_payload" "$task_payload" \
        "task_priority:n" "$task_priority" \
        "task_target_agent_id" "$task_target_agent_id" \
        "task_target_capability" "$task_target_capability" \
        "task_timeout_seconds:n" "$task_timeout_seconds" \
        "task_max_retries:n" "$task_max_retries" \
        "overlap_policy" "$overlap_policy" \
        "expires_at" "$expires_at"
    ) || return $APIARY_ERR

    _apiary_request POST "/api/v1/hives/${hive_id}/schedules" "$body"
}

# apiary_update_schedule — update a task schedule (partial update).
#   HIVE_ID  SCHEDULE_ID
#   [-n NAME] [-g TRIGGER_TYPE] [-t TASK_TYPE]
#   [-c CRON_EXPRESSION] [-i INTERVAL_SECONDS] [-R RUN_AT]
#   [-d TASK_PAYLOAD_JSON] [-p TASK_PRIORITY] [-a TASK_TARGET_AGENT_ID]
#   [-C TASK_TARGET_CAPABILITY] [-T TASK_TIMEOUT_SECONDS]
#   [-r TASK_MAX_RETRIES] [-o OVERLAP_POLICY] [-e EXPIRES_AT]
apiary_update_schedule() {
    local hive_id="${1:?usage: apiary_update_schedule HIVE_ID SCHEDULE_ID [-n NAME] ...}"
    local schedule_id="${2:?usage: apiary_update_schedule HIVE_ID SCHEDULE_ID [-n NAME] ...}"
    shift 2
    local name="" trigger_type="" task_type="" cron_expression="" interval_seconds=""
    local run_at="" task_payload="" task_priority="" task_target_agent_id=""
    local task_target_capability="" task_timeout_seconds="" task_max_retries=""
    local overlap_policy="" expires_at=""
    local OPTIND OPTARG opt
    while getopts "n:g:t:c:i:R:d:p:a:C:T:r:o:e:" opt; do
        case "$opt" in
            n) name="$OPTARG" ;;
            g) trigger_type="$OPTARG" ;;
            t) task_type="$OPTARG" ;;
            c) cron_expression="$OPTARG" ;;
            i) interval_seconds="$OPTARG" ;;
            R) run_at="$OPTARG" ;;
            d) task_payload="$OPTARG" ;;
            p) task_priority="$OPTARG" ;;
            a) task_target_agent_id="$OPTARG" ;;
            C) task_target_capability="$OPTARG" ;;
            T) task_timeout_seconds="$OPTARG" ;;
            r) task_max_retries="$OPTARG" ;;
            o) overlap_policy="$OPTARG" ;;
            e) expires_at="$OPTARG" ;;
            *) _apiary_err "update_schedule: unknown option -$opt"; return $APIARY_ERR ;;
        esac
    done

    local body
    body=$(_apiary_build_json \
        "name" "$name" \
        "trigger_type" "$trigger_type" \
        "task_type" "$task_type" \
        "cron_expression" "$cron_expression" \
        "interval_seconds:n" "$interval_seconds" \
        "run_at" "$run_at" \
        "task_payload" "$task_payload" \
        "task_priority:n" "$task_priority" \
        "task_target_agent_id" "$task_target_agent_id" \
        "task_target_capability" "$task_target_capability" \
        "task_timeout_seconds:n" "$task_timeout_seconds" \
        "task_max_retries:n" "$task_max_retries" \
        "overlap_policy" "$overlap_policy" \
        "expires_at" "$expires_at"
    ) || return $APIARY_ERR

    _apiary_request PUT "/api/v1/hives/${hive_id}/schedules/${schedule_id}" "$body"
}

# apiary_delete_schedule — delete a task schedule.
#   HIVE_ID  SCHEDULE_ID
apiary_delete_schedule() {
    local hive_id="${1:?usage: apiary_delete_schedule HIVE_ID SCHEDULE_ID}"
    local schedule_id="${2:?usage: apiary_delete_schedule HIVE_ID SCHEDULE_ID}"
    _apiary_request DELETE "/api/v1/hives/${hive_id}/schedules/${schedule_id}"
}

# apiary_pause_schedule — pause an active schedule.
#   HIVE_ID  SCHEDULE_ID
apiary_pause_schedule() {
    local hive_id="${1:?usage: apiary_pause_schedule HIVE_ID SCHEDULE_ID}"
    local schedule_id="${2:?usage: apiary_pause_schedule HIVE_ID SCHEDULE_ID}"
    _apiary_request PATCH "/api/v1/hives/${hive_id}/schedules/${schedule_id}/pause"
}

# apiary_resume_schedule — resume a paused schedule.
#   HIVE_ID  SCHEDULE_ID
apiary_resume_schedule() {
    local hive_id="${1:?usage: apiary_resume_schedule HIVE_ID SCHEDULE_ID}"
    local schedule_id="${2:?usage: apiary_resume_schedule HIVE_ID SCHEDULE_ID}"
    _apiary_request PATCH "/api/v1/hives/${hive_id}/schedules/${schedule_id}/resume"
}

# ── Knowledge ────────────────────────────────────────────────────

# apiary_list_knowledge — list knowledge entries.
#   HIVE_ID  [-k KEY_PATTERN] [-s SCOPE] [-l LIMIT]
apiary_list_knowledge() {
    local hive_id="${1:?usage: apiary_list_knowledge HIVE_ID}"
    shift
    local key="" scope="" limit=""
    local OPTIND OPTARG opt
    while getopts "k:s:l:" opt; do
        case "$opt" in
            k) key="$OPTARG" ;;
            s) scope="$OPTARG" ;;
            l) limit="$OPTARG" ;;
            *) _apiary_err "list_knowledge: unknown option -$opt"; return $APIARY_ERR ;;
        esac
    done

    local params=()
    [[ -n "$key" ]]   && params+=("key=$(_apiary_urlencode "$key")")
    [[ -n "$scope" ]] && params+=("scope=$(_apiary_urlencode "$scope")")
    [[ -n "$limit" ]] && params+=("limit=$(_apiary_urlencode "$limit")")
    local qs=""
    if [[ ${#params[@]} -gt 0 ]]; then
        qs="?$(IFS='&'; echo "${params[*]}")"
    fi

    _apiary_request GET "/api/v1/hives/${hive_id}/knowledge${qs}"
}

# apiary_search_knowledge — search knowledge entries.
#   HIVE_ID  [-q QUERY] [-s SCOPE] [-l LIMIT]
apiary_search_knowledge() {
    local hive_id="${1:?usage: apiary_search_knowledge HIVE_ID}"
    shift
    local query="" scope="" limit=""
    local OPTIND OPTARG opt
    while getopts "q:s:l:" opt; do
        case "$opt" in
            q) query="$OPTARG" ;;
            s) scope="$OPTARG" ;;
            l) limit="$OPTARG" ;;
            *) _apiary_err "search_knowledge: unknown option -$opt"; return $APIARY_ERR ;;
        esac
    done

    local params=()
    [[ -n "$query" ]] && params+=("q=$(_apiary_urlencode "$query")")
    [[ -n "$scope" ]] && params+=("scope=$(_apiary_urlencode "$scope")")
    [[ -n "$limit" ]] && params+=("limit=$(_apiary_urlencode "$limit")")
    local qs=""
    if [[ ${#params[@]} -gt 0 ]]; then
        qs="?$(IFS='&'; echo "${params[*]}")"
    fi

    _apiary_request GET "/api/v1/hives/${hive_id}/knowledge/search${qs}"
}

# apiary_get_knowledge — get a single knowledge entry.
#   HIVE_ID  ENTRY_ID
apiary_get_knowledge() {
    local hive_id="${1:?usage: apiary_get_knowledge HIVE_ID ENTRY_ID}"
    local entry_id="${2:?usage: apiary_get_knowledge HIVE_ID ENTRY_ID}"
    _apiary_request GET "/api/v1/hives/${hive_id}/knowledge/${entry_id}"
}

# apiary_create_knowledge — create a knowledge entry.
#   HIVE_ID  -k KEY  -v VALUE_JSON  [-s SCOPE] [-V VISIBILITY] [-t TTL]
apiary_create_knowledge() {
    local hive_id="${1:?usage: apiary_create_knowledge HIVE_ID -k KEY -v VALUE_JSON}"
    shift
    local key="" value="" scope="" visibility="" ttl=""
    local OPTIND OPTARG opt
    while getopts "k:v:s:V:t:" opt; do
        case "$opt" in
            k) key="$OPTARG" ;;
            v) value="$OPTARG" ;;
            s) scope="$OPTARG" ;;
            V) visibility="$OPTARG" ;;
            t) ttl="$OPTARG" ;;
            *) _apiary_err "create_knowledge: unknown option -$opt"; return $APIARY_ERR ;;
        esac
    done

    if [[ -z "$key" || -z "$value" ]]; then
        _apiary_err "create_knowledge: -k KEY and -v VALUE_JSON are required"
        return $APIARY_ERR
    fi

    local body
    body=$(_apiary_build_json \
        "key" "$key" \
        "value" "$value" \
        "scope" "$scope" \
        "visibility" "$visibility" \
        "ttl" "$ttl"
    ) || return $APIARY_ERR
    _apiary_request POST "/api/v1/hives/${hive_id}/knowledge" "$body"
}

# apiary_update_knowledge — update an existing knowledge entry.
#   HIVE_ID  ENTRY_ID  -v VALUE_JSON  [-V VISIBILITY] [-t TTL]
apiary_update_knowledge() {
    local hive_id="${1:?usage: apiary_update_knowledge HIVE_ID ENTRY_ID -v VALUE_JSON}"
    local entry_id="${2:?usage: apiary_update_knowledge HIVE_ID ENTRY_ID -v VALUE_JSON}"
    shift 2
    local value="" visibility="" ttl=""
    local OPTIND OPTARG opt
    while getopts "v:V:t:" opt; do
        case "$opt" in
            v) value="$OPTARG" ;;
            V) visibility="$OPTARG" ;;
            t) ttl="$OPTARG" ;;
            *) _apiary_err "update_knowledge: unknown option -$opt"; return $APIARY_ERR ;;
        esac
    done

    if [[ -z "$value" ]]; then
        _apiary_err "update_knowledge: -v VALUE_JSON is required"
        return $APIARY_ERR
    fi

    local body
    body=$(_apiary_build_json "value" "$value" "visibility" "$visibility" "ttl" "$ttl") || return $APIARY_ERR
    _apiary_request PUT "/api/v1/hives/${hive_id}/knowledge/${entry_id}" "$body"
}

# apiary_delete_knowledge — delete a knowledge entry.
#   HIVE_ID  ENTRY_ID
apiary_delete_knowledge() {
    local hive_id="${1:?usage: apiary_delete_knowledge HIVE_ID ENTRY_ID}"
    local entry_id="${2:?usage: apiary_delete_knowledge HIVE_ID ENTRY_ID}"
    _apiary_request DELETE "/api/v1/hives/${hive_id}/knowledge/${entry_id}"
}

# ======================================================================
# Rate Limiting
# ======================================================================

# apiary_rate_limit_status — get current rate limit config & usage.
apiary_rate_limit_status() {
    _apiary_request GET "/api/v1/agents/rate-limit"
}

# apiary_update_rate_limit — update the per-agent rate limit.
#   -l LIMIT  (integer or "null" to reset to default)
apiary_update_rate_limit() {
    local limit=""
    local OPTIND OPTARG opt
    while getopts "l:" opt; do
        case "$opt" in
            l) limit="$OPTARG" ;;
            *) _apiary_err "update_rate_limit: unknown option -$opt"; return $APIARY_ERR ;;
        esac
    done

    if [[ -z "$limit" ]]; then
        _apiary_err "update_rate_limit: -l LIMIT is required (integer or 'null')"
        return $APIARY_ERR
    fi

    local body
    if [[ "$limit" == "null" ]]; then
        body='{"rate_limit_per_minute":null}'
    else
        body=$(_apiary_build_json "rate_limit_per_minute:n" "$limit") || return $APIARY_ERR
    fi

    _apiary_request PUT "/api/v1/agents/rate-limit" "$body"
}

# ── Persona ──────────────────────────────────────────────────────

# apiary_get_persona_version — lightweight version check for hot-reload polling.
#   [-k KNOWN_VERSION]  (optional) — if set, response includes a 'changed' bool
#
# Returns the server-assigned persona version for this agent without fetching full
# documents. When -k KNOWN_VERSION is provided, the response also includes
# 'changed' (true/false) comparing the server version to the provided value.
apiary_get_persona_version() {
    local known_version="" query_string=""
    local OPTIND OPTARG opt
    while getopts "k:" opt; do
        case "$opt" in
            k) known_version="$OPTARG" ;;
            *) _apiary_err "get_persona_version: unknown option -$opt"; return $APIARY_ERR ;;
        esac
    done

    if [[ -n "$known_version" ]]; then
        query_string="?known_version=${known_version}"
    fi

    _apiary_request GET "/api/v1/persona/version${query_string}"
}

# apiary_check_persona_version — returns 0 (true) if persona version has changed.
#   -k KNOWN_VERSION  (required) — the version the agent currently holds locally
#
# Returns exit code 0 if the server persona version differs from KNOWN_VERSION
# (i.e., the agent should refresh its persona), or 1 if unchanged.
# Exits with APIARY_ERR on request failure.
apiary_check_persona_version() {
    local known_version=""
    local OPTIND OPTARG opt
    while getopts "k:" opt; do
        case "$opt" in
            k) known_version="$OPTARG" ;;
            *) _apiary_err "check_persona_version: unknown option -$opt"; return $APIARY_ERR ;;
        esac
    done

    if [[ -z "$known_version" ]]; then
        _apiary_err "check_persona_version: -k KNOWN_VERSION is required"
        return $APIARY_ERR
    fi

    if ! jq --version >/dev/null 2>&1; then
        _apiary_err "check_persona_version: jq is required (install jq and retry)"
        return $APIARY_ERR_DEPS
    fi

    local result
    result=$(apiary_get_persona_version -k "$known_version") || return $?

    local changed
    changed=$(echo "$result" | jq -r '.changed // "false"')

    if [[ "$changed" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# apiary_get_persona — get the agent's active persona (policy-selected version).
apiary_get_persona() {
    _apiary_request GET "/api/v1/persona"
}

# apiary_get_persona_config — get persona config only (model, temperature, etc.).
apiary_get_persona_config() {
    _apiary_request GET "/api/v1/persona/config"
}

# apiary_get_persona_document — get a single persona document by name.
#   NAME  (e.g. SOUL, AGENT, RULES, STYLE, EXAMPLES, MEMORY)
apiary_get_persona_document() {
    local name="${1:?usage: apiary_get_persona_document NAME}"
    _apiary_request GET "/api/v1/persona/documents/${name}"
}

# apiary_get_persona_assembled — get pre-assembled system prompt in canonical order.
apiary_get_persona_assembled() {
    _apiary_request GET "/api/v1/persona/assembled"
}

# apiary_update_persona_document — agent self-update of an unlocked document.
#   NAME  -c CONTENT  [-m MESSAGE]  [-M MODE]
#   MODE: replace (default), append, prepend
#   Returns 403 if the document is locked by policy.
apiary_update_persona_document() {
    local name="${1:?usage: apiary_update_persona_document NAME -c CONTENT [-m MESSAGE] [-M MODE]}"
    shift
    local content="" message="" mode="replace"
    local message_set=0
    local OPTIND OPTARG opt
    while getopts "c:m:M:" opt; do
        case "$opt" in
            c) content="$OPTARG" ;;
            m) message="$OPTARG"; message_set=1 ;;
            M) mode="$OPTARG" ;;
            *) _apiary_err "update_persona_document: unknown option -$opt"; return $APIARY_ERR ;;
        esac
    done

    if [[ -z "$content" ]]; then
        _apiary_err "update_persona_document: -c CONTENT is required"
        return $APIARY_ERR
    fi

    if [[ "$mode" != "replace" && "$mode" != "append" && "$mode" != "prepend" ]]; then
        _apiary_err "update_persona_document: -M MODE must be replace, append, or prepend"
        return $APIARY_ERR
    fi

    # jq is required to build the request body with guaranteed string encoding
    # AND to parse the response in _apiary_request. Without jq, we must not send
    # the PATCH at all — the server-side update would succeed (creating a new
    # persona version) while the response parsing would fail, misleading callers
    # into retrying and silently creating duplicate versions.
    if ! jq --version >/dev/null 2>&1; then
        _apiary_err "update_persona_document: jq is required (install jq and retry)"
        return $APIARY_ERR_DEPS
    fi

    # Build JSON body with guaranteed string encoding for content and message.
    # _apiary_build_json coerces values starting with {, [, true, false, null as
    # raw JSON, making it unsafe for free-form persona text. Use jq --arg instead,
    # which always emits values as JSON strings regardless of their content.
    #
    # Use message_set flag (not [[ -n "$message" ]]) so that -m '' (explicit
    # empty string) is included in the body rather than silently dropped.
    local body
    if [[ "$message_set" -eq 1 ]]; then
        body=$(jq -n --arg content "$content" --arg message "$message" --arg mode "$mode" \
            '{content: $content, message: $message, mode: $mode}') || {
            _apiary_err "update_persona_document: failed to build JSON body"
            return $APIARY_ERR
        }
    else
        body=$(jq -n --arg content "$content" --arg mode "$mode" \
            '{content: $content, mode: $mode}') || {
            _apiary_err "update_persona_document: failed to build JSON body"
            return $APIARY_ERR
        }
    fi
    _apiary_request PATCH "/api/v1/persona/documents/${name}" "$body"
}

# apiary_update_memory — agent self-update of the MEMORY document.
#   -c CONTENT  (required) — content to write
#   -m MESSAGE  (optional) — commit message
#   -M MODE     (optional) — replace | append (default) | prepend
#
# Convenience wrapper for apiary_update_persona_document MEMORY.
# Agents call this to persist learned facts, project context, and runtime
# observations across executions. Defaults to append mode so that individual
# calls accumulate knowledge rather than overwriting earlier entries.
apiary_update_memory() {
    local content="" message="" mode="append"
    local message_set=0
    local OPTIND OPTARG opt
    while getopts "c:m:M:" opt; do
        case "$opt" in
            c) content="$OPTARG" ;;
            m) message="$OPTARG"; message_set=1 ;;
            M) mode="$OPTARG" ;;
            *) _apiary_err "update_memory: unknown option -$opt"; return $APIARY_ERR ;;
        esac
    done

    if [[ -z "$content" ]]; then
        _apiary_err "update_memory: -c CONTENT is required"
        return $APIARY_ERR
    fi

    if [[ "$mode" != "replace" && "$mode" != "append" && "$mode" != "prepend" ]]; then
        _apiary_err "update_memory: -M MODE must be replace, append, or prepend"
        return $APIARY_ERR
    fi

    if ! jq --version >/dev/null 2>&1; then
        _apiary_err "update_memory: jq is required (install jq and retry)"
        return $APIARY_ERR_DEPS
    fi

    local body
    if [[ "$message_set" -eq 1 ]]; then
        body=$(jq -n --arg content "$content" --arg message "$message" --arg mode "$mode" \
            '{content: $content, message: $message, mode: $mode}') || {
            _apiary_err "update_memory: failed to build JSON body"
            return $APIARY_ERR
        }
    else
        body=$(jq -n --arg content "$content" --arg mode "$mode" \
            '{content: $content, mode: $mode}') || {
            _apiary_err "update_memory: failed to build JSON body"
            return $APIARY_ERR
        }
    fi
    _apiary_request PATCH "/api/v1/persona/memory" "$body"
}
