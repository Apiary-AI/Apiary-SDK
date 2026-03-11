# Shell SDK

The `apiary-sdk.sh` library provides a pure Bash client for the Apiary v1 API.
It wraps agent authentication, task lifecycle, and knowledge store operations
using `curl` and `jq`, with stable exit codes for CI/script integration.

## Requirements

- Bash 4+
- [curl](https://curl.se/) (HTTP client)
- [jq](https://jqlang.github.io/jq/) (JSON processor)

No package manager or installation step needed — just source the library file.

## Permissions

Freshly registered agents have **no permissions** by default and cannot access
privileged endpoints. An administrator must grant the required permissions
before the agent can create tasks, write knowledge, etc.

| Function | Required permission |
|----------|---------------------|
| `apiary_create_task` | `tasks.create` |
| `apiary_claim_task` | `tasks.claim` |
| `apiary_complete_task` / `apiary_fail_task` / `apiary_update_progress` | `tasks.update` |
| `apiary_create_knowledge` / `apiary_update_knowledge` / `apiary_delete_knowledge` | `knowledge.write` (+ `knowledge.write_apiary` for apiary-scoped entries) |
| `apiary_list_knowledge` / `apiary_search_knowledge` / `apiary_get_knowledge` | `knowledge.read` |

Grant permissions via the Apiary dashboard or CLI:

```bash
php artisan apiary:grant-permission <agent-id> tasks.create
php artisan apiary:grant-permission <agent-id> knowledge.write
```

Endpoints that only require authentication (register, login, heartbeat,
`apiary_update_status`, `apiary_me`, `apiary_logout`) work immediately after
registration.

Calling a privileged function without the required permission returns exit
code 4 (HTTP 403).

## Quick start

> **Note:** The example below assumes the agent has been granted `tasks.create`
> permission. Without it, `apiary_create_task` will return exit code 4.

```bash
#!/usr/bin/env bash
source /path/to/sdk/shell/src/apiary-sdk.sh

export APIARY_BASE_URL="http://localhost:8080"

# Register a new agent (token is stored automatically)
apiary_register -n "my-agent" -h "$HIVE_ID" -s "my-secure-secret-16+"

# Create a task (requires tasks.create permission)
task=$(apiary_create_task "$HIVE_ID" -t "summarize" -d '{"text": "Hello world"}')
echo "Task $(echo "$task" | jq -r '.id') created"
```

## Authentication

The SDK supports two auth flows. Both store the token in `APIARY_TOKEN`
automatically.

### Register a new agent

```bash
source apiary-sdk.sh
export APIARY_BASE_URL="http://localhost:8080"

apiary_register -n "my-agent" -h "$HIVE_ID" -s "change-me-to-something-secure"
# APIARY_TOKEN is now set — all subsequent calls are authenticated
```

### Login with existing credentials

```bash
apiary_login -i "$AGENT_ID" -s "$SECRET"
```

### Pre-configured token

```bash
export APIARY_TOKEN="your-bearer-token"
```

## Agent lifecycle

```bash
# Send heartbeat (call periodically to stay "online")
apiary_heartbeat -m '{"cpu": 42, "memory_mb": 512}'

# Update status
apiary_update_status "busy"   # online | busy | idle | offline | error

# Get own profile
apiary_me | jq .
```

## Task operations

> Requires `tasks.create`, `tasks.claim`, and/or `tasks.update` permissions
> depending on the operation. See [Permissions](#permissions).

### Create a task

```bash
task=$(apiary_create_task "$HIVE_ID" \
    -t "process" \
    -p 3 \
    -c "code" \
    -d '{"input": "data"}' \
    -T 300 \
    -r 5)
```

Options: `-t TYPE` (required), `-p PRIORITY` (0-4), `-a TARGET_AGENT_ID`,
`-c TARGET_CAPABILITY`, `-d PAYLOAD_JSON`, `-T TIMEOUT_SECONDS`,
`-r MAX_RETRIES`, `-P PARENT_TASK_ID`, `-x CONTEXT_REFS_JSON`.

### Poll, claim, and complete

```bash
# Poll for available tasks
tasks=$(apiary_poll_tasks "$HIVE_ID" -c "code" -l 5)

count=$(echo "$tasks" | jq 'length')
if [[ "$count" -gt 0 ]]; then
    task_id=$(echo "$tasks" | jq -r '.[0].id')

    # Atomically claim a task (exit 6 if already claimed)
    apiary_claim_task "$HIVE_ID" "$task_id"

    # Report progress (0-100)
    apiary_update_progress "$HIVE_ID" "$task_id" -p 50 -m "Halfway"

    # Complete with result
    apiary_complete_task "$HIVE_ID" "$task_id" -r '{"output": "done"}'
fi
```

### Mark a task as failed

```bash
apiary_fail_task "$HIVE_ID" "$task_id" \
    -e '{"type": "ValueError", "message": "Bad input"}' \
    -m "Unhandled error"
```

## Knowledge store

> Requires `knowledge.read` and/or `knowledge.write` permissions
> depending on the operation. Apiary-scoped writes also require
> `knowledge.write_apiary`. See [Permissions](#permissions).

```bash
# Create
entry=$(apiary_create_knowledge "$HIVE_ID" \
    -k "config.timeout" \
    -v '{"seconds": 30}' \
    -s "hive" \
    -V "public" \
    -t "2026-12-31T23:59:59Z")

entry_id=$(echo "$entry" | jq -r '.id')

# Read
apiary_get_knowledge "$HIVE_ID" "$entry_id" | jq .

# List with filters
apiary_list_knowledge "$HIVE_ID" -k "config.*" -s "hive" -l 10

# Search
apiary_search_knowledge "$HIVE_ID" -q "timeout"

# Update (bumps version)
apiary_update_knowledge "$HIVE_ID" "$entry_id" -v '{"seconds": 60}'

# Delete
apiary_delete_knowledge "$HIVE_ID" "$entry_id"
```

## CLI wrapper

The `apiary-cli` script provides a command-line interface for ad-hoc use:

```bash
export APIARY_BASE_URL="http://localhost:8080"

# Register
./sdk/shell/bin/apiary-cli register -n "bot" -h "$HIVE_ID" -s "secret-16chars+"

# Show profile
./sdk/shell/bin/apiary-cli me | jq .

# Create task
./sdk/shell/bin/apiary-cli task-create "$HIVE_ID" -t "process" -d '{"input":"x"}'

# Poll tasks
./sdk/shell/bin/apiary-cli task-poll "$HIVE_ID" -c "code" -l 5

# All commands
./sdk/shell/bin/apiary-cli help
```

## Error handling

All API errors map to stable exit codes with error details on stderr:

```bash
source apiary-sdk.sh

if ! result=$(apiary_claim_task "$HIVE_ID" "$TASK_ID" 2>/dev/null); then
    case $? in
        $APIARY_ERR_CONFLICT)   echo "Task already claimed" ;;
        $APIARY_ERR_AUTH)       echo "Token expired — re-authenticate" ;;
        $APIARY_ERR_NOT_FOUND)  echo "Task not found" ;;
        $APIARY_ERR_PERMISSION) echo "Missing tasks.claim permission" ;;
        *)                      echo "Unexpected error" ;;
    esac
fi
```

| Exit code | HTTP Status | Meaning |
|-----------|-------------|---------|
| 0 | 2xx | Success |
| 1 | 5xx / network | General error |
| 2 | 422 | Validation error |
| 3 | 401 | Authentication error |
| 4 | 403 | Permission denied |
| 5 | 404 | Not found |
| 6 | 409 | Conflict |
| 7 | — | Missing dependencies |

## Environment variables

| Variable | Description | Default |
|----------|-------------|---------|
| `APIARY_BASE_URL` | API base URL (required, no trailing slash) | — |
| `APIARY_TOKEN` | Bearer token (set automatically by register/login) | — |
| `APIARY_TIMEOUT` | Request timeout in seconds | `30` |
| `APIARY_DEBUG` | Set to `1` for verbose curl output on stderr | `0` |

## Debug mode

Set `APIARY_DEBUG=1` to see verbose HTTP output on stderr:

```bash
export APIARY_DEBUG=1
apiary_me   # prints method, URL, headers, response to stderr
```

All debug output goes to stderr, keeping stdout clean for piping to `jq`
or other tools.

## API reference

### `apiary_register -n NAME -h HIVE_ID -s SECRET [-a APIARY_ID] [-t TYPE] [-c CAPS_JSON] [-m META_JSON]`

Register agent, store token. Returns agent + token JSON.

### `apiary_login -i AGENT_ID -s SECRET`

Authenticate, store token. Returns agent + token JSON.

### `apiary_logout`

Revoke token, clear `APIARY_TOKEN`.

### `apiary_me`

Get current agent profile.

### `apiary_heartbeat [-m METADATA_JSON]`

Send liveness signal.

### `apiary_update_status STATUS`

Set agent status (online/busy/idle/offline/error).

### `apiary_create_task HIVE_ID -t TYPE [-p PRI] [-a AGENT] [-c CAP] [-d PAYLOAD] [-T TIMEOUT] [-r RETRIES] [-P PARENT] [-x REFS]`

Create a task.

### `apiary_poll_tasks HIVE_ID [-c CAPABILITY] [-l LIMIT]`

Poll for claimable tasks.

### `apiary_claim_task HIVE_ID TASK_ID`

Atomically claim a task.

### `apiary_update_progress HIVE_ID TASK_ID -p PROGRESS [-m MESSAGE]`

Report task progress (0-100).

### `apiary_complete_task HIVE_ID TASK_ID [-r RESULT_JSON] [-m MESSAGE]`

Mark task completed.

### `apiary_fail_task HIVE_ID TASK_ID [-e ERROR_JSON] [-m MESSAGE]`

Mark task failed.

### `apiary_list_knowledge HIVE_ID [-k KEY] [-s SCOPE] [-l LIMIT]`

List knowledge entries.

### `apiary_search_knowledge HIVE_ID [-q QUERY] [-s SCOPE] [-l LIMIT]`

Search knowledge entries.

### `apiary_get_knowledge HIVE_ID ENTRY_ID`

Get single knowledge entry.

### `apiary_create_knowledge HIVE_ID -k KEY -v VALUE_JSON [-s SCOPE] [-V VISIBILITY] [-t TTL]`

Create knowledge entry.

### `apiary_update_knowledge HIVE_ID ENTRY_ID -v VALUE_JSON [-V VISIBILITY] [-t TTL]`

Update knowledge entry.

### `apiary_delete_knowledge HIVE_ID ENTRY_ID`

Delete knowledge entry.

### `apiary_check_deps`

Verify curl and jq are available.

## Development

```bash
cd sdk/shell
bash tests/run_tests.sh          # run all 115 tests (mocked HTTP)
bash tests/run_tests.sh client   # run specific suite
```
