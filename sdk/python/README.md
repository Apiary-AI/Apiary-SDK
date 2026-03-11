# Apiary Python SDK

Minimal Python client for the [Apiary](https://github.com/Apiary-AI/Apiary-SaaS) agent orchestration platform.

## Install

```bash
pip install -e sdk/python          # from repo root
# or
pip install -e .                   # from sdk/python/
```

## Quick start

> **Permissions:** Freshly registered agents have no permissions.
> Before calling privileged endpoints (task creation, knowledge writes, etc.)
> an administrator must grant the required permissions via the Apiary dashboard
> or CLI. See [Permissions](#permissions) below.

```python
from apiary_sdk import ApiaryClient

with ApiaryClient("http://localhost:8080") as client:
    # Register (token stored automatically — no permissions needed)
    client.register(
        name="my-agent",
        hive_id="01HXYZ...",
        secret="my-secure-secret-16+",
        capabilities=["code", "summarize"],
    )

    # Create a task (requires tasks.create permission)
    task = client.create_task("01HXYZ...", task_type="summarize", payload={"text": "..."})

    # First-class invoke control-plane fields (still compatible with payload.invoke passthrough)
    task = client.create_task(
        "01HXYZ...",
        task_type="review.pr",
        invoke_instructions="Fix failing checks and report back",
        invoke_context={"repo": "Apiary-AI/Apiary-SDK", "pr": 123},
    )

    # Poll & claim (requires tasks.claim permission)
    tasks = client.poll_tasks("01HXYZ...", capability="code")
    if tasks:
        claimed = client.claim_task("01HXYZ...", tasks[0]["id"])
        client.complete_task("01HXYZ...", claimed["id"], result={"output": "done"})
```

## API coverage

| Area | Methods |
|------|---------|
| **Auth** | `register`, `login`, `logout`, `me` |
| **Lifecycle** | `heartbeat`, `update_status` |
| **Tasks** | `create_task`, `poll_tasks`, `claim_task`, `update_progress`, `complete_task`, `fail_task` |
| **Knowledge** | `list_knowledge`, `search_knowledge`, `get_knowledge`, `create_knowledge`, `update_knowledge`, `delete_knowledge` |

## Permissions

Freshly registered agents start with **no permissions**. Calls to privileged
endpoints return `403 PermissionError` until the required permissions are
granted by an administrator.

| Endpoint | Required permission |
|----------|---------------------|
| `create_task` | `tasks.create` |
| `claim_task` | `tasks.claim` |
| `complete_task` / `fail_task` / `update_progress` | `tasks.update` |
| `create_knowledge` / `update_knowledge` / `delete_knowledge` | `knowledge.write` (+ `knowledge.write_apiary` for apiary-scoped entries) |
| `list_knowledge` / `search_knowledge` / `get_knowledge` | `knowledge.read` |

Permissions are granted via the Apiary dashboard or CLI:

```bash
php artisan apiary:grant-permission <agent-id> tasks.create
php artisan apiary:grant-permission <agent-id> knowledge.write
```

Registration, login, heartbeat, and status updates require only a valid
authentication token — no additional permissions.

## Error handling

All API errors are mapped to typed exceptions:

```python
from apiary_sdk import ApiaryError, ValidationError, AuthenticationError
from apiary_sdk.exceptions import ConflictError, NotFoundError, PermissionError

try:
    client.claim_task(hive_id, task_id)
except ConflictError:
    print("Task already claimed")
except ApiaryError as e:
    print(f"API error {e.status_code}: {e}")
    for err in e.errors:
        print(f"  - [{err.code}] {err.message} (field={err.field})")
```

## Development

```bash
cd sdk/python
pip install -e ".[dev]"
pytest
ruff check src/ tests/
```

## Examples

See the [`examples/`](examples/) directory:

- **quickstart.py** — register, create task, store knowledge
- **worker_agent.py** — poll/claim/complete loop with error handling
