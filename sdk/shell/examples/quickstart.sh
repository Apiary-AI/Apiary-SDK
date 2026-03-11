#!/usr/bin/env bash
# quickstart.sh — Register an agent, create a task, store knowledge.
#
# Usage:
#   export APIARY_BASE_URL="http://localhost:8080"
#   bash examples/quickstart.sh
#
# Prerequisites: bash 4+, curl, jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../src/apiary-sdk.sh"

apiary_check_deps || exit $?

HIVE_ID="${HIVE_ID:?Set HIVE_ID to your target hive}"

echo "==> Registering agent..."
# Avoid command-substitution: apiary_register sets APIARY_TOKEN in the
# current shell.  Running it inside $(...) would execute in a subshell and
# the token assignment would be lost for subsequent authenticated calls.
_reg_tmp=$(mktemp)
apiary_register -n "shell-quickstart" -h "$HIVE_ID" -s "my-secure-secret-16chars" > "$_reg_tmp"
result=$(<"$_reg_tmp"); rm -f "$_reg_tmp"
echo "Agent ID: $(echo "$result" | jq -r '.agent.id')"
echo "Token stored automatically."

echo ""
echo "==> Getting agent profile..."
apiary_me | jq .

echo ""
echo "==> Sending heartbeat..."
apiary_heartbeat -m '{"cpu": 42, "memory_mb": 512}' | jq .

echo ""
echo "==> Creating a task (requires tasks.create permission)..."
task=$(apiary_create_task "$HIVE_ID" -t "summarize" -d '{"text": "Hello from Shell SDK"}')
task_id=$(echo "$task" | jq -r '.id')
echo "Task created: $task_id"

echo ""
echo "==> Creating a knowledge entry (requires knowledge.write permission)..."
entry=$(apiary_create_knowledge "$HIVE_ID" \
    -k "config.greeting" \
    -v '{"message": "Hello from Shell SDK"}' \
    -s "hive")
entry_id=$(echo "$entry" | jq -r '.id')
echo "Knowledge entry created: $entry_id"

echo ""
echo "==> Listing knowledge..."
apiary_list_knowledge "$HIVE_ID" -l 5 | jq .

echo ""
echo "==> Logging out..."
apiary_logout
echo "Done."
