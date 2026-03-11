#!/usr/bin/env bash
# _resolve-sdk.sh — Locate the Apiary Shell SDK.
#
# Sourced by CLI entry points and modules. No external dependencies.
#
# Searches (in order):
#   1. $APIARY_SHELL_SDK                          — explicit override
#   2. $SCRIPT_DIR/../../shell/src/apiary-sdk.sh  — repo layout
#   3. $SCRIPT_DIR/../lib/apiary-sdk.sh           — bundled copy install
#
# Sets _APIARY_SHELL_SDK_PATH on success, returns 1 on failure.
# Requires SCRIPT_DIR to be set before calling.

_apiary_find_shell_sdk() {
    local _candidates=(
        "${APIARY_SHELL_SDK:-}"
        "${SCRIPT_DIR}/../../shell/src/apiary-sdk.sh"
        "${SCRIPT_DIR}/../lib/apiary-sdk.sh"
    )
    for _c in "${_candidates[@]}"; do
        [[ -z "$_c" ]] && continue
        if [[ -f "$_c" ]]; then
            _APIARY_SHELL_SDK_PATH="$_c"
            return 0
        fi
    done
    echo "Fatal: Apiary Shell SDK not found." >&2
    echo "Searched:" >&2
    for _c in "${_candidates[@]}"; do
        [[ -n "$_c" ]] && echo "  - $_c" >&2
    done
    echo "" >&2
    echo "Fix: set APIARY_SHELL_SDK=/path/to/apiary-sdk.sh" >&2
    echo "  or copy sdk/shell/src/apiary-sdk.sh into $(cd "${SCRIPT_DIR}/.." 2>/dev/null && pwd)/lib/" >&2
    return 1
}
