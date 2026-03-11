#!/usr/bin/env bash
# apiary-cli.sh — Main CLI entry point for the Apiary OpenClaw skill.
#
# Called by OpenClaw's exec tool. Dispatches subcommands to the
# appropriate module functions.
#
# Usage: apiary-cli.sh <command> [args...]

set -euo pipefail

# Resolve through symlinks (OpenClaw may symlink the install)
_src="${BASH_SOURCE[0]}"
while [[ -L "$_src" ]]; do
    _dir="$(cd "$(dirname "$_src")" && pwd)"
    _src="$(readlink "$_src")"
    [[ "$_src" != /* ]] && _src="$_dir/$_src"
done
SCRIPT_DIR="$(cd "$(dirname "$_src")" && pwd)"
unset _src _dir

# Locate and source Shell SDK (supports repo layout, bundled copy, env override)
# shellcheck source=_resolve-sdk.sh
source "${SCRIPT_DIR}/_resolve-sdk.sh"
_apiary_find_shell_sdk || exit 1
# shellcheck source=../../shell/src/apiary-sdk.sh
source "$_APIARY_SHELL_SDK_PATH"
_APIARY_SDK_LOADED=1

# shellcheck source=apiary-auth.sh
source "${SCRIPT_DIR}/apiary-auth.sh"
# shellcheck source=apiary-tasks.sh
source "${SCRIPT_DIR}/apiary-tasks.sh"
# shellcheck source=apiary-knowledge.sh
source "${SCRIPT_DIR}/apiary-knowledge.sh"
# shellcheck source=apiary-events.sh
source "${SCRIPT_DIR}/apiary-events.sh"

# ── Usage ───────────────────────────────────────────────────────

_oc_usage() {
    cat <<'EOF'
Usage: apiary-cli.sh <command> [args...]

Commands:
  auth                          Ensure authenticated (register or login)
  status                        Show agent connection status
  poll [capability]             Poll for available tasks
  claim <id>                    Claim a task
  complete <id> [result_json]   Complete a task
  fail <id> [error_json]        Fail a task
  progress <id> <pct> [msg]     Report progress
  create <type> [payload_json]  Create a new task
  knowledge list [key_pattern]  List knowledge entries
  knowledge search <query>      Search knowledge
  knowledge get <id>            Get a knowledge entry
  knowledge set <key> <val>     Create or update a knowledge entry
  knowledge delete <id>         Delete a knowledge entry
  events subscribe <type>       Subscribe to event type
  events unsubscribe <type>     Unsubscribe from event type
  events list                   List subscriptions
  events poll                   Poll for new events
  events publish <type> <json>  Publish an event
  daemon start|stop|status      Daemon control
  heartbeat                     Send agent heartbeat
  version                       Show version
  help                          Show this help

Environment:
  APIARY_BASE_URL        API base URL (required)
  APIARY_HIVE_ID         Target hive ID
  APIARY_AGENT_NAME      Agent name (for registration)
  APIARY_AGENT_SECRET    Shared secret (register/login fallback)
  APIARY_AGENT_ID        Agent ID (set after first registration)
  APIARY_AGENT_REFRESH_TOKEN  Refresh token for secret-less renewal
  APIARY_CAPABILITIES    Comma-separated capabilities (default: general)
  APIARY_POLL_INTERVAL   Daemon poll interval in seconds (default: 10)
  APIARY_HEARTBEAT_INTERVAL  Heartbeat interval in seconds (default: 30)
  APIARY_DAEMON_START_TIMEOUT  Readiness wait in seconds (default: 30)
  APIARY_AUTO_DAEMON     Auto-start daemon (default: true)
EOF
}

# ── Status command ──────────────────────────────────────────────

_oc_status() {
    _apiary_oc_sync_token_file
    apiary_load_token
    source "${SCRIPT_DIR}/apiary-auth.sh"
    _apiary_oc_load_agent
    _apiary_oc_load_refresh_token

    echo "Apiary Agent Status"
    echo "==================="
    echo "  Base URL:    ${APIARY_BASE_URL:-<not set>}"
    echo "  Hive ID:     ${APIARY_HIVE_ID:-<not set>}"
    echo "  Agent ID:    ${APIARY_AGENT_ID:-<not set>}"
    echo "  Agent Name:  ${APIARY_AGENT_NAME:-<not set>}"
    if [[ -n "${APIARY_TOKEN:-}" ]]; then
        echo "  Token:       <set> (masked)"
    else
        echo "  Token:       <not set>"
    fi
    if [[ -n "${APIARY_AGENT_REFRESH_TOKEN:-}" ]]; then
        echo "  Refresh:     <set> (masked)"
    else
        echo "  Refresh:     <not set>"
    fi

    # Check daemon status
    local pid_file="${APIARY_CONFIG_DIR:-${HOME}/.config/apiary}/daemon.pid"
    if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        echo "  Daemon:      running (PID $(cat "$pid_file"))"
    else
        echo "  Daemon:      stopped"
    fi

    # Validate token if present (only when base URL is available)
    if [[ -n "${APIARY_TOKEN:-}" ]]; then
        if [[ -n "${APIARY_BASE_URL:-}" ]]; then
            if apiary_me >/dev/null 2>&1; then
                echo "  Auth:        valid"
            else
                echo "  Auth:        expired/invalid"
            fi
        else
            echo "  Auth:        unknown (APIARY_BASE_URL not set)"
        fi
    fi
}

# ── Daemon control ──────────────────────────────────────────────

_oc_daemon() {
    local action="${1:?usage: apiary-cli.sh daemon start|stop|status}"

    case "$action" in
        start)
            local pid_file="${APIARY_CONFIG_DIR:-${HOME}/.config/apiary}/daemon.pid"
            local start_timeout="${APIARY_DAEMON_START_TIMEOUT:-30}"
            # Fully detach stdio so captured-output contexts don't hang
            "${SCRIPT_DIR}/apiary-daemon.sh" </dev/null >/dev/null 2>&1 &
            local daemon_pid=$!
            # Poll for readiness: the daemon writes its PID file only after
            # successful auth and init — a stronger signal than process-alive.
            local _deadline=$(( $(date +%s) + start_timeout ))
            while (( $(date +%s) < _deadline )); do
                # Fast-fail: process already exited
                if ! kill -0 "$daemon_pid" 2>/dev/null; then
                    wait "$daemon_pid" 2>/dev/null || true
                    echo "Daemon failed to start." >&2
                    return 1
                fi
                # Readiness: daemon wrote its PID file after init
                if [[ -f "$pid_file" ]] && [[ "$(cat "$pid_file" 2>/dev/null)" == "$daemon_pid" ]]; then
                    echo "Daemon started (PID $daemon_pid)."
                    return 0
                fi
                sleep 0.2
            done
            # Timed out — if daemon is still alive, it's doing slow init
            # (e.g. first registration, slow network). Don't kill it.
            if kill -0 "$daemon_pid" 2>/dev/null; then
                echo "Daemon starting (PID $daemon_pid), still initializing..."
                return 0
            fi
            wait "$daemon_pid" 2>/dev/null || true
            echo "Daemon failed to start." >&2
            return 1
            ;;
        stop)
            local pid_file="${APIARY_CONFIG_DIR:-${HOME}/.config/apiary}/daemon.pid"
            if [[ -f "$pid_file" ]]; then
                local pid
                pid=$(cat "$pid_file")
                if kill -0 "$pid" 2>/dev/null; then
                    kill "$pid"
                    echo "Daemon stopped (PID $pid)."
                else
                    echo "Daemon not running (stale PID file)."
                    rm -f "$pid_file"
                fi
            else
                echo "Daemon not running (no PID file)."
            fi
            ;;
        status)
            local pid_file="${APIARY_CONFIG_DIR:-${HOME}/.config/apiary}/daemon.pid"
            if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
                echo "Daemon running (PID $(cat "$pid_file"))."
            else
                echo "Daemon not running."
            fi
            ;;
        *)
            echo "Usage: apiary-cli.sh daemon start|stop|status" >&2
            exit 1
            ;;
    esac
}

# ── Knowledge subcommand dispatch ───────────────────────────────

_oc_knowledge() {
    local subcmd="${1:?usage: apiary-cli.sh knowledge <list|search|get|set|delete> ...}"
    shift

    case "$subcmd" in
        list)    apiary_oc_knowledge_list "$@" ;;
        search)  apiary_oc_knowledge_search "$@" ;;
        get)     apiary_oc_knowledge_get "$@" ;;
        set)     apiary_oc_knowledge_set "$@" ;;
        delete)  apiary_oc_knowledge_delete "$@" ;;
        *)
            echo "Unknown knowledge command: $subcmd" >&2
            echo "Usage: apiary-cli.sh knowledge <list|search|get|set|delete> ..." >&2
            exit 1
            ;;
    esac
}

# ── Events subcommand dispatch ──────────────────────────────────

_oc_events() {
    local subcmd="${1:?usage: apiary-cli.sh events <subscribe|unsubscribe|list|poll|publish> ...}"
    shift

    case "$subcmd" in
        subscribe)   apiary_oc_events_subscribe "$@" ;;
        unsubscribe) apiary_oc_events_unsubscribe "$@" ;;
        list)        apiary_oc_events_list "$@" ;;
        poll)        apiary_oc_events_poll "$@" ;;
        publish)     apiary_oc_events_publish "$@" ;;
        *)
            echo "Unknown events command: $subcmd" >&2
            echo "Usage: apiary-cli.sh events <subscribe|unsubscribe|list|poll|publish> ..." >&2
            exit 1
            ;;
    esac
}

# ── Main dispatch ───────────────────────────────────────────────

if [[ $# -lt 1 ]]; then
    _oc_usage
    exit 1
fi

# Check dependencies
apiary_check_deps || exit $?

command="$1"
shift

case "$command" in
    auth)       apiary_oc_ensure_auth ;;
    status)     _oc_status ;;
    poll)
        apiary_load_token
        _apiary_oc_load_agent
        apiary_oc_poll "$@"
        ;;
    claim)
        apiary_load_token
        _apiary_oc_load_agent
        apiary_oc_claim "$@"
        ;;
    complete)
        apiary_load_token
        _apiary_oc_load_agent
        apiary_oc_complete "$@"
        ;;
    fail)
        apiary_load_token
        _apiary_oc_load_agent
        apiary_oc_fail "$@"
        ;;
    progress)
        apiary_load_token
        _apiary_oc_load_agent
        apiary_oc_progress "$@"
        ;;
    create)
        apiary_load_token
        _apiary_oc_load_agent
        apiary_oc_create "$@"
        ;;
    knowledge)
        apiary_load_token
        _apiary_oc_load_agent
        _oc_knowledge "$@"
        ;;
    events)
        apiary_load_token
        _apiary_oc_load_agent
        _oc_events "$@"
        ;;
    daemon)     _oc_daemon "$@" ;;
    heartbeat)
        apiary_load_token
        apiary_heartbeat >/dev/null && echo "Heartbeat sent."
        ;;
    version)
        echo "apiary-openclaw-skill ${APIARY_SDK_VERSION}"
        ;;
    help|--help|-h)
        _oc_usage
        ;;
    *)
        echo "Unknown command: $command" >&2
        _oc_usage >&2
        exit 1
        ;;
esac
