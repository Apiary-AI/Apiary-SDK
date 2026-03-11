# Apiary Skill for OpenClaw

An [OpenClaw](https://github.com/openclaw/openclaw) skill plugin that turns OpenClaw into a first-class [Apiary](https://github.com/Apiary-AI/Apiary-SaaS) agent. It polls for tasks, manages shared knowledge, subscribes to events, and maintains agent health — all through OpenClaw's skill system.

## Prerequisites

- [OpenClaw](https://github.com/openclaw/openclaw) installed and configured
- `curl` and `jq` available in PATH
- Access to an Apiary instance

## Installation

### Option 1: Symlink (development)

```bash
ln -s /path/to/Apiary-SaaS/sdk/openclaw ~/.openclaw/skills/apiary
```

### Option 2: Copy

```bash
cp -r /path/to/Apiary-SaaS/sdk/openclaw ~/.openclaw/skills/apiary
# Bundle the Shell SDK so scripts can find it without the repo tree
mkdir -p ~/.openclaw/skills/apiary/lib
cp /path/to/Apiary-SaaS/sdk/shell/src/apiary-sdk.sh ~/.openclaw/skills/apiary/lib/
```

Alternatively, set `APIARY_SHELL_SDK` to point at the Shell SDK:

```bash
export APIARY_SHELL_SDK=/path/to/Apiary-SaaS/sdk/shell/src/apiary-sdk.sh
```

## Configuration

Add the following to your `~/.openclaw/openclaw.json`:

```json
{
  "skills": {
    "entries": {
      "apiary": {
        "enabled": true,
        "env": {
          "APIARY_BASE_URL": "https://apiary.example.com",
          "APIARY_HIVE_ID": "01HXYZ...",
          "APIARY_AGENT_NAME": "my-openclaw-agent",
          "APIARY_AGENT_SECRET": "your-secure-secret-here",
          "APIARY_CAPABILITIES": "code,summarize,research"
        }
      }
    }
  }
}
```

See `config/openclaw.example.json` for all available options.

### Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `APIARY_BASE_URL` | Yes | — | Apiary API base URL |
| `APIARY_HIVE_ID` | Yes | — | Target hive ID |
| `APIARY_AGENT_NAME` | Yes* | — | Agent name (*required for first registration) |
| `APIARY_AGENT_SECRET` | Yes | — | Authentication secret (16+ chars) |
| `APIARY_AGENT_ID` | No | — | Agent ID (auto-populated after registration) |
| `APIARY_CAPABILITIES` | No | `general` | Comma-separated capabilities |
| `APIARY_POLL_INTERVAL` | No | `10` | Daemon poll interval (seconds) |
| `APIARY_HEARTBEAT_INTERVAL` | No | `30` | Heartbeat interval (seconds) |
| `APIARY_AUTO_DAEMON` | No | `true` | Auto-start background daemon |
| `APIARY_SHELL_SDK` | No | — | Explicit path to `apiary-sdk.sh` (overrides auto-detection) |
| `APIARY_WAKE_ENABLED` | No | `false` | Enable webhook-wake bridge |
| `APIARY_WAKE_SESSION` | If wake enabled | — | OpenClaw session ID to wake |
| `APIARY_WAKE_LOG` | No | `~/.config/apiary/wake.log` | Wake bridge log file path |
| `APIARY_WAKE_DEBOUNCE_SECS` | No | `5` | Seconds before re-waking for same task+comment |
| `APIARY_WAKE_GATEWAY_URL` | No | `http://localhost:3223` | OpenClaw gateway URL (fallback when CLI unavailable) |
| `APIARY_WAKE_GATEWAY_TOKEN` | No | — | Bearer token for gateway auth |
| `APIARY_WAKE_GATEWAY_TIMEOUT` | No | `5` | Gateway HTTP timeout (seconds) |
| `APIARY_WAKE_ALERT_ENABLED` | No | `false` | Enable visible Telegram alerts on PR comments |
| `APIARY_WAKE_ALERT_TELEGRAM` | If alert enabled | — | Telegram chat ID or username target |
| `APIARY_WAKE_ALERT_CHANNEL` | No | `telegram` | Channel name for alert routing |

## Usage

### Via OpenClaw

```bash
# Check status
openclaw agent --message "/apiary status"

# List available tasks
openclaw agent --message "/apiary tasks"

# Claim and work on a task
openclaw agent --message "/apiary claim 01HXY..."

# Search knowledge
openclaw agent --message "/apiary knowledge search deployment"

# Start background daemon
openclaw agent --message "/apiary daemon start"
```

### Direct CLI (without OpenClaw)

```bash
# Set required env vars
export APIARY_BASE_URL="http://localhost:8080"
export APIARY_HIVE_ID="01HXYZ..."
export APIARY_AGENT_SECRET="your-secret"
export APIARY_AGENT_NAME="test-agent"

# Authenticate
sdk/openclaw/bin/apiary-cli.sh auth

# Check status
sdk/openclaw/bin/apiary-cli.sh status

# Poll for tasks
sdk/openclaw/bin/apiary-cli.sh poll

# Send heartbeat
sdk/openclaw/bin/apiary-cli.sh heartbeat

# Knowledge operations
sdk/openclaw/bin/apiary-cli.sh knowledge search "test"
sdk/openclaw/bin/apiary-cli.sh knowledge set "my-key" '{"data": "value"}'

# Event operations
sdk/openclaw/bin/apiary-cli.sh events subscribe "task.completed"
sdk/openclaw/bin/apiary-cli.sh events poll

# Daemon control
sdk/openclaw/bin/apiary-cli.sh daemon start
sdk/openclaw/bin/apiary-cli.sh daemon status
sdk/openclaw/bin/apiary-cli.sh daemon stop
```

## Architecture

```
OpenClaw
  └─ Apiary Skill (SKILL.md)
       ├─ /apiary slash commands → apiary-cli.sh → Shell SDK
       ├─ HEARTBEAT.md           → periodic health checks
       └─ apiary-daemon.sh       → background polling loop
            ├─ Task poll → detects pending tasks
            │    └─ apiary-task-lifecycle.sh (full lifecycle dispatch)
            │         ├─ webhook_handler → wake bridge + complete/fail
            │         ├─ reminder       → message delivery + complete/fail
            │         └─ unknown type   → explicit capability_missing fail
            │              (includes trusted invoke instructions/context)
            ├─ Heartbeat → keeps agent alive
            └─ Event poll → raw event ingestion + OpenClaw system events
```

### Shell SDK Dependency

All scripts source the existing Apiary Shell SDK (`sdk/shell/src/apiary-sdk.sh`) for HTTP client logic, JSON building, error handling, and API operations. The OpenClaw skill adds:

- **Auto-auth flow**: register → login → token persistence
- **LLM-friendly output**: human-readable formatting for task lists, knowledge entries
- **Background daemon**: poll loop with heartbeat and exponential backoff
- **Event operations**: subscribe, unsubscribe, poll, publish (not yet in base Shell SDK)
- **Pending task files**: task data written to disk for LLM consumption
- **Webhook-wake bridge**: auto-wake OpenClaw sessions on actionable webhook events
- **Task lifecycle dispatch**: webhook_handler/reminder handlers + explicit capability_missing fail for unknown routed task types

## Routed Task Lifecycle

The daemon manages the full lifecycle for routed tasks so they don't pile up as pending in Apiary. Every polled task is dispatched through lifecycle handling:

- `webhook_handler` → webhook-wake bridge flow
- `reminder` → direct message delivery flow
- any other type → explicit `capability_missing` failure (structured error)

1. **Claims** the task atomically (`PATCH .../tasks/{id}/claim`). If another agent already claimed it (409 Conflict), the daemon skips and cleans up the local pending file. On network error, the pending file is preserved for retry on the next poll cycle.

2. **Processes** via the routed handler (webhook wake, reminder delivery, or default capability-missing response).

3. **Completes or fails** the task in Apiary with a structured payload:
   - **Success**: `{"status":"completed","summary":"delivered: wake=1 alert=0",...}`
   - **Filtered**: `{"status":"completed","summary":"filtered: not a PR comment webhook",...}`
   - **Deduplicated**: `{"status":"completed","summary":"deduplicated: already processed",...}`
   - **Failure**: `{"status":"failed","error":"all delivery channels failed",...}`
   - **Capability missing**: `{"code":"capability_missing","task_type":"...","trusted_control_plane":{"invoke":{...}},...}`

4. **Writes a trace** to `~/.config/apiary/traces/{task_id}.json` for local debugging.

5. **Removes** the pending file from `~/.config/apiary/pending/`.

### Operational Notes

- The lifecycle is **fail-soft at the daemon level**: a processing error in one task never crashes the daemon loop.
- **Claim errors are not silent**: network failures return exit code 1 so the daemon can retry; 409 conflicts are logged and the pending file is cleaned up.
- **No delivery channels enabled**: if wake and alert are both disabled, the task is still claimed and completed (acknowledged) rather than left pending forever.
- **Deduplication**: if a task+comment was already processed within the debounce window, the task is completed with a "deduplicated" summary.
- **Trusted control-plane passthrough**: canonical `invoke.instructions/context` are propagated into wake text and capability-missing failure payloads, with legacy fallback to `payload.invoke.*`.
- **No implicit drop**: unknown routed task types are explicitly failed, and polled events are surfaced as OpenClaw system events.

## Webhook-Wake Bridge

When `APIARY_WAKE_ENABLED=true`, the daemon automatically wakes an OpenClaw assistant session whenever a `webhook_handler` task arrives containing a GitHub PR comment. The bridge:

1. Parses PR comment metadata from the webhook payload (repo, PR number, comment URL, body)
2. Extracts severity hints from the comment body (`[urgent]`, `[critical]`, `[high]`, `[low]`)
3. Deduplicates using task ID + comment ID (prevents repeat wakes within the debounce window)
4. Invokes `openclaw sessions_send` to wake the target session with actionable context
5. Falls back to direct HTTP POST to the OpenClaw gateway when the CLI is not in PATH

All parsing and invocation failures are logged but never crash the daemon loop (fail-soft).

#### Dual-Delivery (Visible Telegram Alert)

When `APIARY_WAKE_ALERT_ENABLED=true`, the bridge sends **both** an internal wake (via `sessions_send`) and a user-visible Telegram alert (via `message.send`) for each actionable PR comment event. This ensures assistant automation is triggered while also notifying users in their Telegram chat.

- Dedupe applies to both: a single event produces at most one internal wake **and** one visible alert
- If the visible alert fails, the daemon logs a warning but does not crash; the internal wake still proceeds
- Alert messages include a severity icon, repo name, PR number, a truncated comment preview, and the comment URL

#### Fallback Transport

When the `openclaw` binary is not available in `$PATH`, the bridge automatically falls back to a direct HTTP POST to the OpenClaw local gateway's `/tools/invoke` endpoint:

- **Wake**: `POST {gateway}/tools/invoke` with `{"tool":"sessions_send","args":{"sessionKey":"...","message":"..."}}`
- **Alert**: `POST {gateway}/tools/invoke` with `{"tool":"message","args":{"action":"send","channel":"...","target":"...","message":"..."}}`

Configure `APIARY_WAKE_GATEWAY_URL` if the gateway runs on a non-default address. Set `APIARY_WAKE_GATEWAY_TOKEN` if gateway auth is required.

### Setup

```json
{
  "env": {
    "APIARY_WAKE_ENABLED": "true",
    "APIARY_WAKE_SESSION": "your-session-id",
    "APIARY_WAKE_ALERT_ENABLED": "true",
    "APIARY_WAKE_ALERT_TELEGRAM": "@your-username-or-chat-id",
    "APIARY_WAKE_ALERT_CHANNEL": "telegram"
  }
}
```

### File Locations

| Path | Purpose |
|---|---|
| `~/.config/apiary/wake_seen.json` | Deduplication state (auto-pruned after 1 hour) |
| `~/.config/apiary/wake.log` | Wake bridge activity log |

## Task Processing Modes

Tasks can be processed automatically or manually based on type:

| Mode | Behavior |
|---|---|
| `auto` | LLM claims, processes, and completes tasks automatically |
| `manual` | LLM notifies user, waits for `/apiary` commands |

Default modes:
- `code`, `summarize`, `research` → auto
- `deploy`, `admin`, `approval` → manual
- All others → auto (default)

## File Locations

| Path | Purpose |
|---|---|
| `~/.config/apiary/token` | Persisted auth token |
| `~/.config/apiary/agent.json` | Agent ID and metadata |
| `~/.config/apiary/daemon.pid` | Daemon PID file |
| `~/.config/apiary/pending/*.json` | Pending task files |
| `~/.config/apiary/pending/events/*.json` | Polled event snapshots (for local inspection) |
| `~/.config/apiary/cursor.json` | Last event poll cursor |
| `~/.config/apiary/wake_seen.json` | Webhook-wake deduplication state |
| `~/.config/apiary/wake.log` | Webhook-wake activity log |
| `~/.config/apiary/traces/*.json` | Task lifecycle trace records |

## License

Same license as the Apiary project.
