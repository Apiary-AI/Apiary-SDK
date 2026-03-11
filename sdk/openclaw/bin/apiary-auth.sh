#!/usr/bin/env bash
# apiary-auth.sh — OpenClaw-specific authentication for Apiary.
#
# Sources the Shell SDK and provides auto-register/login flow
# with token and agent metadata persistence.
#
# Functions:
#   apiary_oc_ensure_auth   — Validate or obtain authentication
#   apiary_oc_register      — Register a new OpenClaw agent
#   apiary_oc_login         — Login an existing agent
#
# Env vars:
#   APIARY_AGENT_NAME     — Agent name for registration
#   APIARY_AGENT_SECRET   — Shared secret for auth
#   APIARY_AGENT_ID       — Agent ID for login (set after first registration)
#   APIARY_HIVE_ID        — Target hive ID
#   APIARY_CAPABILITIES   — Comma-separated capability list (default: "general")

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
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    _src="${BASH_SOURCE[0]}"
    while [[ -L "$_src" ]]; do
        _dir="$(cd "$(dirname "$_src")" && pwd)"
        _src="$(readlink "$_src")"
        [[ "$_src" != /* ]] && _src="$_dir/$_src"
    done
    SCRIPT_DIR="$(cd "$(dirname "$_src")" && pwd)"
    unset _src _dir
fi

# ── Config directory ────────────────────────────────────────────
_apiary_oc_config_dir() {
    echo "${APIARY_CONFIG_DIR:-${HOME}/.config/apiary}"
}

_apiary_oc_agent_file() {
    echo "$(_apiary_oc_config_dir)/agent.json"
}

# ── Load persisted agent metadata ───────────────────────────────
_apiary_oc_load_agent() {
    local agent_file
    agent_file=$(_apiary_oc_agent_file)
    if [[ -f "$agent_file" ]]; then
        # Validate JSON before parsing — malformed file must not abort
        # the script under set -e when env vars already provide auth.
        if ! jq empty "$agent_file" 2>/dev/null; then
            _apiary_debug "Warning: $agent_file contains invalid JSON, skipping metadata load"
            return 0
        fi
        if [[ -z "${APIARY_AGENT_ID:-}" ]]; then
            APIARY_AGENT_ID=$(jq -r '.id // empty' "$agent_file")
            export APIARY_AGENT_ID
        fi
        if [[ -z "${APIARY_HIVE_ID:-}" ]]; then
            APIARY_HIVE_ID=$(jq -r '.hive_id // empty' "$agent_file")
            export APIARY_HIVE_ID
        fi
        if [[ -z "${APIARY_AGENT_NAME:-}" ]]; then
            APIARY_AGENT_NAME=$(jq -r '.name // empty' "$agent_file")
            export APIARY_AGENT_NAME
        fi
    fi
}

# ── Save agent metadata ────────────────────────────────────────
_apiary_oc_save_agent() {
    local id="$1" name="$2" hive_id="$3"
    local config_dir agent_file
    config_dir=$(_apiary_oc_config_dir)
    agent_file=$(_apiary_oc_agent_file)
    mkdir -p "$config_dir"
    jq -n --arg id "$id" --arg name "$name" --arg hive_id "$hive_id" \
        '{id: $id, name: $name, hive_id: $hive_id}' > "$agent_file"
    chmod 600 "$agent_file"
    APIARY_AGENT_ID="$id"
    export APIARY_AGENT_ID
}

# ── Register ────────────────────────────────────────────────────
# apiary_oc_register — Register a new OpenClaw agent.
#   Uses APIARY_AGENT_NAME, APIARY_HIVE_ID, APIARY_AGENT_SECRET,
#   APIARY_CAPABILITIES env vars.
apiary_oc_register() {
    local name="${APIARY_AGENT_NAME:?APIARY_AGENT_NAME must be set}"
    local hive_id="${APIARY_HIVE_ID:?APIARY_HIVE_ID must be set}"
    local secret="${APIARY_AGENT_SECRET:?APIARY_AGENT_SECRET must be set}"
    local caps="${APIARY_CAPABILITIES:-general}"

    # Convert comma-separated capabilities to JSON array
    local caps_json
    caps_json=$(echo "$caps" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))')

    local result
    result=$(apiary_register \
        -n "$name" \
        -h "$hive_id" \
        -s "$secret" \
        -t "openclaw" \
        -c "$caps_json"
    ) || return $?

    # Persist token and agent metadata
    apiary_save_token

    local agent_id agent_name
    agent_id=$(echo "$result" | jq -r '.agent.id // empty')
    agent_name=$(echo "$result" | jq -r '.agent.name // empty')
    if [[ -n "$agent_id" ]]; then
        _apiary_oc_save_agent "$agent_id" "$agent_name" "$hive_id"
    fi

    echo "$result"
    return $APIARY_OK
}

# ── Login ───────────────────────────────────────────────────────
# apiary_oc_login — Login an existing agent.
#   Uses APIARY_AGENT_ID and APIARY_AGENT_SECRET env vars.
apiary_oc_login() {
    local agent_id="${APIARY_AGENT_ID:?APIARY_AGENT_ID must be set}"
    local secret="${APIARY_AGENT_SECRET:?APIARY_AGENT_SECRET must be set}"

    local result
    result=$(apiary_login -i "$agent_id" -s "$secret") || return $?

    apiary_save_token

    # Persist agent metadata (consistent with register flow).
    # Preserve existing hive_id/name when the response omits them so a
    # login that returns only {id, token} doesn't blank out saved state.
    local agent_name hive_id
    agent_name=$(echo "$result" | jq -r '.agent.name // empty')
    hive_id=$(echo "$result" | jq -r '.agent.hive_id // empty')

    # Fall back to current env / previously loaded values
    if [[ -z "$hive_id" ]]; then
        hive_id="${APIARY_HIVE_ID:-}"
    fi
    if [[ -z "$agent_name" ]]; then
        agent_name="${APIARY_AGENT_NAME:-}"
    fi

    _apiary_oc_save_agent "$agent_id" "${agent_name:-}" "${hive_id:-}"
    if [[ -n "$hive_id" ]]; then
        APIARY_HIVE_ID="$hive_id"
        export APIARY_HIVE_ID
    fi
    if [[ -n "$agent_name" ]]; then
        APIARY_AGENT_NAME="$agent_name"
        export APIARY_AGENT_NAME
    fi

    echo "$result"
    return $APIARY_OK
}

# ── Ensure auth ─────────────────────────────────────────────────
# apiary_oc_ensure_auth — Check for valid token, re-login or register as needed.
#   Returns 0 on success, non-zero on failure.
apiary_oc_ensure_auth() {
    # Load persisted state
    apiary_load_token
    _apiary_oc_load_agent

    # If we have a token, validate it
    if [[ -n "${APIARY_TOKEN:-}" ]]; then
        if apiary_me >/dev/null 2>&1; then
            _apiary_debug "Auth valid (existing token)"
            return $APIARY_OK
        fi
        _apiary_debug "Token expired or invalid, re-authenticating..."
        APIARY_TOKEN=""
    fi

    # Try login if we have an agent ID
    if [[ -n "${APIARY_AGENT_ID:-}" && -n "${APIARY_AGENT_SECRET:-}" ]]; then
        _apiary_debug "Attempting login with agent ID ${APIARY_AGENT_ID}"
        if apiary_oc_login >/dev/null 2>&1; then
            _apiary_debug "Login successful"
            return $APIARY_OK
        fi
        _apiary_debug "Login failed, attempting registration..."
    fi

    # Fall back to registration
    if [[ -n "${APIARY_AGENT_NAME:-}" && -n "${APIARY_HIVE_ID:-}" && -n "${APIARY_AGENT_SECRET:-}" ]]; then
        _apiary_debug "Attempting registration as ${APIARY_AGENT_NAME}"
        if apiary_oc_register >/dev/null 2>&1; then
            _apiary_debug "Registration successful"
            return $APIARY_OK
        fi
        _apiary_err "Registration failed"
        return $APIARY_ERR_AUTH
    fi

    _apiary_err "Cannot authenticate: set APIARY_AGENT_ID+APIARY_AGENT_SECRET (login) or APIARY_AGENT_NAME+APIARY_HIVE_ID+APIARY_AGENT_SECRET (register)"
    return $APIARY_ERR_AUTH
}
