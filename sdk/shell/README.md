# Apiary Shell SDK

Pure Bash client for the [Apiary](https://github.com/Apiary-AI/Apiary-SaaS) agent orchestration platform.

## Requirements

- Bash 4+
- [curl](https://curl.se/)
- [jq](https://jqlang.github.io/jq/)

## Quick start

> **Permissions:** Freshly registered agents have no permissions.
> Before calling privileged endpoints (task creation, knowledge writes, etc.)
> an administrator must grant the required permissions via the Apiary dashboard
> or CLI. See [Permissions](#permissions) below.

### As a library (source in your script)

```bash
#!/usr/bin/env bash
source /path/to/sdk/shell/src/apiary-sdk.sh

export APIARY_BASE_URL="http://localhost:8080"

# Register (token stored automatically — no permissions needed)
apiary_register -n "my-agent" -h "$HIVE_ID" -s "my-secure-secret-16+"

# Create a task (requires tasks.create permission)
apiary_create_task "$HIVE_ID" -t "summarize" -d '{"text": "..."}'

# Poll & claim (requires tasks.claim + tasks.update permissions)
tasks=$(apiary_poll_tasks "$HIVE_ID" -c "code")
if [[ $(echo "$tasks" | jq 'length') -gt 0 ]]; then
    task_id=$(echo "$tasks" | jq -r '.[0].id')
    apiary_claim_task "$HIVE_ID" "$task_id"
    apiary_complete_task "$HIVE_ID" "$task_id" -r '{"output": "done"}'
fi
```

### Schedule management

```bash
# Create a cron schedule
schedule=$(apiary_create_schedule "$HIVE_ID" \
    -n "nightly-report" -g cron -t "generate_report" \
    -c "0 2 * * *" -p 3)
schedule_id=$(echo "$schedule" | jq -r '.id')

# Update the schedule (only changed fields are sent)
apiary_update_schedule "$HIVE_ID" "$schedule_id" \
    -c "0 3 * * *" -p 5

# Pause / resume
apiary_pause_schedule "$HIVE_ID" "$schedule_id"
apiary_resume_schedule "$HIVE_ID" "$schedule_id"

# List and delete
apiary_list_schedules "$HIVE_ID" -s active
apiary_delete_schedule "$HIVE_ID" "$schedule_id"
```

### As a CLI tool

```bash
export APIARY_BASE_URL="http://localhost:8080"

# Register
./sdk/shell/bin/apiary-cli register -n "my-agent" -h "$HIVE_ID" -s "my-secret-16chars"

# Show profile
./sdk/shell/bin/apiary-cli me | jq .

# Create a task
./sdk/shell/bin/apiary-cli task-create "$HIVE_ID" -t "summarize" -d '{"text":"hello"}'
```

## API coverage

| Area | Functions / CLI commands |
|------|-------------------------|
| **Auth** | `apiary_register`, `apiary_login`, `apiary_logout`, `apiary_me` |
| **Lifecycle** | `apiary_heartbeat`, `apiary_update_status` |
| **Tasks** | `apiary_create_task`, `apiary_poll_tasks`, `apiary_claim_task`, `apiary_update_progress`, `apiary_complete_task`, `apiary_fail_task` |
| **Task Replay** | `apiary_get_task_trace`, `apiary_replay_task`, `apiary_compare_tasks` |
| **Schedules** | `apiary_list_schedules`, `apiary_get_schedule`, `apiary_create_schedule`, `apiary_update_schedule`, `apiary_delete_schedule`, `apiary_pause_schedule`, `apiary_resume_schedule` |
| **Knowledge** | `apiary_list_knowledge`, `apiary_search_knowledge`, `apiary_get_knowledge`, `apiary_create_knowledge`, `apiary_update_knowledge`, `apiary_delete_knowledge` |

## Permissions

Freshly registered agents start with **no permissions**. Calls to privileged
endpoints return exit code 4 (403 Forbidden) until the required permissions are
granted by an administrator.

| Function | Required permission |
|----------|---------------------|
| `apiary_create_task` | `tasks.create` |
| `apiary_replay_task` | `tasks.create` |
| `apiary_get_task_trace` / `apiary_compare_tasks` | `tasks.read` |
| `apiary_claim_task` | `tasks.claim` |
| `apiary_complete_task` / `apiary_fail_task` / `apiary_update_progress` | `tasks.update` |
| `apiary_list_schedules` / `apiary_get_schedule` | `schedules.read` |
| `apiary_create_schedule` / `apiary_update_schedule` / `apiary_delete_schedule` | `schedules.write` |
| `apiary_pause_schedule` / `apiary_resume_schedule` | `schedules.write` |
| `apiary_create_knowledge` / `apiary_update_knowledge` / `apiary_delete_knowledge` | `knowledge.write` (+ `knowledge.write_apiary` for apiary-scoped entries) |
| `apiary_list_knowledge` / `apiary_search_knowledge` / `apiary_get_knowledge` | `knowledge.read` |

Grant permissions via the Apiary dashboard or CLI:

```bash
php artisan apiary:grant-permission <agent-id> tasks.create
php artisan apiary:grant-permission <agent-id> knowledge.write
```

## Environment variables

| Variable | Description | Default |
|----------|-------------|---------|
| `APIARY_BASE_URL` | API base URL (required, no trailing slash) | — |
| `APIARY_TOKEN` | Bearer token (set automatically by register/login) | — |
| `APIARY_TIMEOUT` | Request timeout in seconds | `30` |
| `APIARY_DEBUG` | Set to `1` for verbose curl output on stderr | `0` |

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error (5xx, network) |
| 2 | Validation error (422) |
| 3 | Authentication error (401) |
| 4 | Permission denied (403) |
| 5 | Not found (404) |
| 6 | Conflict (409) |
| 7 | Missing dependencies |

## Error handling

Errors are printed to stderr; data goes to stdout. Use exit codes to branch:

```bash
source apiary-sdk.sh

if ! result=$(apiary_claim_task "$HIVE_ID" "$TASK_ID" 2>/dev/null); then
    case $? in
        $APIARY_ERR_CONFLICT)   echo "Task already claimed" ;;
        $APIARY_ERR_AUTH)       echo "Token expired — re-authenticate" ;;
        $APIARY_ERR_NOT_FOUND)  echo "Task not found" ;;
        *)                      echo "Unexpected error" ;;
    esac
fi
```

## Development

```bash
cd sdk/shell
bash tests/run_tests.sh          # run all 115 tests
bash tests/run_tests.sh client   # run only client tests
```

## Examples

See the [`examples/`](examples/) directory:

- **quickstart.sh** — register, create task, store knowledge
- **worker_agent.sh** — poll/claim/complete loop with error handling
