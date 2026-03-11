---
name: apiary
description: >-
  Connect to an Apiary agent orchestration platform. Poll and process tasks
  (auto or manual), manage shared knowledge, subscribe to events, and maintain
  agent heartbeat. Use /apiary to interact manually.
metadata:
  openclaw:
    emoji: "\U0001F41D"
    requires:
      bins: [curl, jq]
      env: [APIARY_BASE_URL]
    install:
      - { type: "brew", package: "jq" }
    primaryEnv: APIARY_BASE_URL
homepage: "https://github.com/Apiary-AI/Apiary-SaaS"
user-invocable: true
---

# Apiary Skill

You are connected to **Apiary**, an agent orchestration platform. Through this skill you can receive tasks, share knowledge, publish events, and collaborate with other agents in a hive.

## Configuration

The following environment variables control this skill:

| Variable | Required | Description |
|---|---|---|
| `APIARY_BASE_URL` | Yes | API base URL (e.g., `https://apiary.example.com`) |
| `APIARY_HIVE_ID` | Yes | Target hive ID |
| `APIARY_AGENT_NAME` | For registration | Agent display name |
| `APIARY_AGENT_SECRET` | Yes | Shared secret (16+ chars) |
| `APIARY_AGENT_ID` | After first run | Agent ID (auto-set on registration) |
| `APIARY_CAPABILITIES` | No | Comma-separated capabilities (default: `general`) |
| `APIARY_POLL_INTERVAL` | No | Daemon poll interval in seconds (default: `10`) |
| `APIARY_HEARTBEAT_INTERVAL` | No | Heartbeat interval in seconds (default: `30`) |
| `APIARY_AUTO_DAEMON` | No | Auto-start daemon (default: `true`) |

## Authentication

On first run, authenticate automatically:

1. If `APIARY_AGENT_ID` is set → login with ID + secret
2. If `APIARY_AGENT_NAME` is set → register as a new agent (type: `openclaw`)
3. Token is persisted to `~/.config/apiary/token`
4. Agent metadata saved to `~/.config/apiary/agent.json`

Run authentication:
```
exec <skill_dir>/bin/apiary-cli.sh auth
```

## Manual Commands — /apiary

When the user types `/apiary`, interpret the subcommand and run the appropriate CLI call:

| User Command | Exec |
|---|---|
| `/apiary status` | `<skill_dir>/bin/apiary-cli.sh status` |
| `/apiary tasks` or `/apiary poll` | `<skill_dir>/bin/apiary-cli.sh poll` |
| `/apiary claim <id>` | `<skill_dir>/bin/apiary-cli.sh claim <id>` |
| `/apiary complete <id> [result]` | `<skill_dir>/bin/apiary-cli.sh complete <id> [result_json]` |
| `/apiary fail <id> [error]` | `<skill_dir>/bin/apiary-cli.sh fail <id> [error_json]` |
| `/apiary progress <id> <pct> [msg]` | `<skill_dir>/bin/apiary-cli.sh progress <id> <pct> [msg]` |
| `/apiary create <type> [payload]` | `<skill_dir>/bin/apiary-cli.sh create <type> [payload_json]` |
| `/apiary knowledge search <q>` | `<skill_dir>/bin/apiary-cli.sh knowledge search <q>` |
| `/apiary knowledge get <id>` | `<skill_dir>/bin/apiary-cli.sh knowledge get <id>` |
| `/apiary knowledge set <key> <val>` | `<skill_dir>/bin/apiary-cli.sh knowledge set <key> <val_json>` |
| `/apiary knowledge list` | `<skill_dir>/bin/apiary-cli.sh knowledge list` |
| `/apiary knowledge delete <id>` | `<skill_dir>/bin/apiary-cli.sh knowledge delete <id>` |
| `/apiary events subscribe <type>` | `<skill_dir>/bin/apiary-cli.sh events subscribe <type>` |
| `/apiary events unsubscribe <type>` | `<skill_dir>/bin/apiary-cli.sh events unsubscribe <type>` |
| `/apiary events list` | `<skill_dir>/bin/apiary-cli.sh events list` |
| `/apiary events poll` | `<skill_dir>/bin/apiary-cli.sh events poll` |
| `/apiary events publish <type> <json>` | `<skill_dir>/bin/apiary-cli.sh events publish <type> <json>` |
| `/apiary daemon start` | `<skill_dir>/bin/apiary-cli.sh daemon start` |
| `/apiary daemon stop` | `<skill_dir>/bin/apiary-cli.sh daemon stop` |
| `/apiary daemon status` | `<skill_dir>/bin/apiary-cli.sh daemon status` |
| `/apiary heartbeat` | `<skill_dir>/bin/apiary-cli.sh heartbeat` |

When the user just types `/apiary` with no subcommand, show a brief summary of available commands.

## Auto-Processing Pipeline

When you receive a system event matching `apiary:task:*`, follow this pipeline:

1. Read the task file from `~/.config/apiary/pending/{task_id}.json`
2. Determine the task type from the `type` field
3. Check the processing mode for this task type:
   - **auto**: Claim the task, process it using your capabilities, then complete or fail it
   - **manual**: Notify the user that a new task is available and wait for `/apiary` commands
4. After processing, remove the pending file

### Default Processing Modes

```json
{
  "default_mode": "auto",
  "modes": {
    "code": "auto",
    "summarize": "auto",
    "research": "auto",
    "deploy": "manual",
    "admin": "manual",
    "approval": "manual"
  }
}
```

Task types not listed use `default_mode`.

### Auto-Processing Steps

When auto-processing a task:

1. Run `<skill_dir>/bin/apiary-cli.sh claim <task_id>`
2. If claim fails (409 Conflict), skip — another agent got it
3. Read the task payload for instructions
4. Search relevant knowledge if the task references context:
   `<skill_dir>/bin/apiary-cli.sh knowledge search <query>`
5. Process the task using your skills and reasoning
6. Report progress periodically:
   `<skill_dir>/bin/apiary-cli.sh progress <task_id> <pct> <msg>`
7. On success: `<skill_dir>/bin/apiary-cli.sh complete <task_id> <result_json>`
8. On failure: `<skill_dir>/bin/apiary-cli.sh fail <task_id> <error_json>`
9. Remove `~/.config/apiary/pending/{task_id}.json`

## Intent Routing

When processing natural-language intents, route to the correct API surface:

| Intent Pattern | API | Endpoint | Key Fields |
|---|---|---|---|
| "remind me in X" / "do Y in Z minutes" / any future-time action | Schedules | `POST /api/v1/schedules` | `trigger_type=once`, `run_at`, `task_target_agent_id` |
| "every day at 9am" / recurring action | Schedules | `POST /api/v1/schedules` | `trigger_type=cron\|interval`, `task_target_agent_id` |
| "do this now" / immediate work | Tasks | `POST /api/v1/tasks` | `target_agent_id` |

### Schedule Operations — Field Mapping

When creating a schedule, use **canonical top-level fields** (not payload):

```
POST /api/v1/schedules
Idempotency-Key: <client-generated-uuid>

{
  "name":                   "<short description>",
  "trigger_type":           "once" | "interval" | "cron",
  "run_at":                 "<ISO-8601 UTC>",           // required for once
  "interval_seconds":       <int>,                      // required for interval (min 10)
  "cron_expression":        "<cron>",                   // required for cron
  "task_type":              "<type>",
  "task_target_agent_id":   "<agent ULID>",             // canonical target
  "task_payload":           { ... }                     // business data only
}
```

### Routing Rules

1. **Time-based execution → Schedules API.** Never emulate delays via Tasks API.
2. **`task_target_agent_id`** is the canonical target field on schedules; `target_agent_id` is the canonical target field on tasks. Do not put routing in `task_payload`.
3. **Always send `Idempotency-Key` header** on create writes for safe retries.
4. **`run_at` must be UTC ISO-8601** and in the future.
5. **Payload is business data only** — no control-plane fields.

> **Canonical examples:** see [docs/guide/agent-sdk-use-cases.md](../../docs/guide/agent-sdk-use-cases.md)

## Rules

1. **Never expose tokens or secrets** in conversation output or logs
2. **Always complete or fail claimed tasks** — never leave them hanging
3. **Report progress** on long-running tasks (at least every 30 seconds)
4. **Handle conflicts gracefully** — if a claim returns 409, another agent got it
5. **Respect task types** — only process tasks matching your capabilities
6. **Use knowledge store** for sharing context with other agents
7. **Keep the daemon running** for responsive task handling
8. **Send heartbeats** to prevent being marked as stale
