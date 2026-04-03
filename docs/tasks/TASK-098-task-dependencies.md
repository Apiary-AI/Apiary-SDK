# TASK-098: Task Dependencies (depends_on + waiting status)

## Summary

Tasks can now declare dependencies on other tasks. A task with unmet dependencies is held in `waiting` status until all (or some, depending on policy) of its dependencies complete.

## Changes

### Database

- **`tasks.depends_on`** (JSONB, nullable): stores the dependency specification
- **`task_dependencies`** table: normalized dependency rows for indexed queries

```sql
CREATE TABLE task_dependencies (
    task_id         VARCHAR(26) NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    depends_on_id   VARCHAR(26) NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    status          VARCHAR(20) DEFAULT 'pending',  -- pending, met, failed
    PRIMARY KEY (task_id, depends_on_id)
);
CREATE INDEX idx_task_deps_waiting ON task_dependencies (depends_on_id, status) WHERE status = 'pending';
```

### New Status: `waiting`

Tasks in `waiting` status:
- Cannot be claimed (returns 409 `waiting`)
- Not returned by poll
- Transition to `pending` when all dependencies are met

### API

#### Creating a task with dependencies

```json
POST /api/v1/hives/{hive}/tasks
{
  "type": "generate_report",
  "depends_on": {
    "tasks": ["tsk_a", "tsk_b"],
    "policy": "all",
    "inject_results": true,
    "on_dependency_failure": "fail"
  }
}
```

Response: status is `waiting` if any dependency is pending/in_progress, `pending` if all already complete.

#### depends_on fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `tasks` | `string[]` | required | Task IDs to wait for |
| `policy` | `all\|any` | `all` | When to release (currently `all` is enforced) |
| `inject_results` | `bool` | `false` | Inject dependency results into payload |
| `on_dependency_failure` | `fail\|partial\|wait` | `fail` | What to do when a dep fails |

#### Failure policies

| Policy | Behaviour |
|--------|-----------|
| `fail` | Waiting task fails immediately |
| `partial` | Waiting task becomes pending with partial results injected |
| `wait` | Task stays waiting (e.g. dep may be retried) |

#### Result injection

When `inject_results: true`, the task payload gains a `_dependencies` key on release:

```json
{
  "_dependencies": {
    "tsk_a": { "status": "completed", "result": { ... } },
    "tsk_b": { "status": "completed", "result": { ... } }
  }
}
```

Results exceeding 1 MB are replaced with a reference stub:
```json
{ "status": "completed", "_dependency_ref": "tsk_a" }
```
Retrieve the full result via `GET /api/v1/hives/{hive}/tasks/tsk_a`.

### Service: `TaskDependencyService`

- `register(Task, array)`: called at task creation; inserts dependency rows and sets task to `waiting`
- `evaluateDependents(Task)`: called after a task completes or fails; releases waiting tasks

### State machine

```
waiting → pending   (all deps met)
waiting → failed    (dep failed, policy=fail)
waiting → pending   (dep failed, policy=partial)
waiting → waiting   (dep failed, policy=wait)
```
