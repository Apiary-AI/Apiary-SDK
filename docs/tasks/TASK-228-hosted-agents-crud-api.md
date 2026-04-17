# TASK-228: Hosted agents CRUD API

**Status:** pending
**Branch:** `task/228-hosted-agents-crud-api`
**PR:** —
**Depends on:** TASK-227, TASK-253
**Blocks:** TASK-230, TASK-241
**Edition:** cloud
**Feature doc:** [FEATURE_HOSTED_AGENTS.md](../features/list-1/FEATURE_HOSTED_AGENTS.md) §10.1, §10.3, §10.4, §10.5

## Objective

Expose REST endpoints that let an apiary owner create, list, read, update,
and destroy a hosted agent — including the preset catalogue feeding the
dashboard wizard. Writes only persist DB state; actual deploy is dispatched
to the job added in TASK-230.

## Requirements

### Functional

- [ ] FR-1: `GET /api/v1/hives/{hive}/hosted-agents` — paginated list
  scoped to the hive, returns summary view (no `user_env`).
- [ ] FR-2: `POST /api/v1/hives/{hive}/hosted-agents` — create. Validates
  `preset_key` exists in registry, `model` is in the preset's allowed
  list, and every key in `user_env` matches the preset's `user_env`
  schema (required keys present). Creates:
    - a new `Agent` row (type: `hosted`, token issued via existing
      `AgentRegistrationService`),
    - a `HostedAgent` row (status=`deploying`, novps handles null until
      the deploy job runs). The creator-facing contract is
      `status=deploying` immediately on successful create — matches
      FEATURE_HOSTED_AGENTS.md §5 and §10.5. The deploy job transitions
      `deploying → running | error` from there.
  Enqueues `DeployHostedAgentJob` (TASK-230) in the `afterCommit` hook.
- [ ] FR-3: `GET /api/v1/hives/{hive}/hosted-agents/{id}` — full view with
  latest deployment summary (masked `user_env` — show keys + `***` per value).
- [ ] FR-4: `PATCH /api/v1/hives/{hive}/hosted-agents/{id}` — accepts
  `model`, `user_env`, `replicas`. Any change enqueues a redeploy.
- [ ] FR-5: `DELETE /api/v1/hives/{hive}/hosted-agents/{id}` — enqueues a
  destroy job; response returns 202 with the pending status.
- [ ] FR-6: `GET /api/v1/hosted-agent-presets` — returns the sanitized
  preset catalogue (labels, models, required env-key schema). **Does not**
  expose image repo name, registry credential id, or command.
- [ ] FR-7: `GET /api/v1/hives/{hive}/hosted-agents/{id}/status` — live
  status endpoint polled by the dashboard for convergence after
  lifecycle ops (TASK-233 FR-6). Returns the cached
  `hosted_agents.status` plus a fresh novps probe via
  `NovpsClient::getApp($appId)` when the row is in a non-terminal state
  (`deploying`). Response shape:
  ```json
  {
    "data": {
      "id": "hag_01J...",
      "status": "deploying",
      "novps_status": "building",
      "latest_deployment": {
        "id": "had_01J...",
        "status": "building",
        "started_at": "2026-04-16T10:00:00Z"
      },
      "checked_at": "2026-04-16T10:00:05Z"
    }
  }
  ```
  No `user_env` ever surfaces. When the row is terminal (`running`,
  `stopped`, `error`, `deleted`) the endpoint returns the cached row
  without a remote round-trip.
- [ ] FR-8: All endpoints 404 when `apiary.hosted_agents.enabled === false`.
- [ ] FR-9: Responses use the standard `{ data, meta, errors }` envelope.

### Non-Functional

- [ ] NFR-1: Controller lives at `app/Cloud/Http/Controllers/Api/HostedAgentController.php`.
- [ ] NFR-2: Form Requests: `CreateHostedAgentRequest`,
  `UpdateHostedAgentRequest` under `app/Cloud/Http/Requests/`.
- [ ] NFR-3: API Resource classes mask `user_env` values (only keys
  surface in responses).
- [ ] NFR-4: Every mutation writes to `activity_log` with action
  `hosted_agent.{created|updated|destroyed}` and does **not** include the
  raw `user_env`.
- [ ] NFR-5: Route group guarded by `apiary.hosted.enabled` middleware
  (added in this task).

## Architecture & Design

### Files to Create / Modify

| Action | Path | Purpose |
|--------|------|---------|
| Create | `app/Cloud/Http/Controllers/Api/HostedAgentController.php` | CRUD |
| Create | `app/Cloud/Http/Controllers/Api/HostedAgentPresetController.php` | GET presets |
| Create | `app/Cloud/Http/Requests/CreateHostedAgentRequest.php` | Validation |
| Create | `app/Cloud/Http/Requests/UpdateHostedAgentRequest.php` | Validation |
| Create | `app/Cloud/Http/Resources/HostedAgentResource.php` | Masked view |
| Create | `app/Cloud/Http/Middleware/EnsureHostedAgentsEnabled.php` | 404 gate |
| Modify | `routes/api.php` | Register routes behind middleware |
| Modify | `bootstrap/app.php` | Register the middleware alias |

### Key Design Decisions

- **Create flow is synchronous for DB state, async for deploy.**
  The controller returns 201 as soon as `HostedAgent` is persisted, with
  `status: "deploying"` and `deployment: null`. This keeps the request
  fast and avoids HTTP timeouts on a slow novps round-trip. The deploy
  job transitions the row to `running` or `error` once novps reports a
  terminal deployment state.
- **No separate "update env" endpoint.** Everything mutable funnels through
  PATCH; the API resource is responsible for diffing and deciding whether a
  redeploy is required.
- **Preset validation is strict.** `user_env` keys not declared by the
  preset are rejected — prevents users from smuggling arbitrary envs into
  the worker container.

## API Changes

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET    | `/api/v1/hives/{hive}/hosted-agents` | List |
| POST   | `/api/v1/hives/{hive}/hosted-agents` | Create + enqueue deploy |
| GET    | `/api/v1/hives/{hive}/hosted-agents/{id}` | Show |
| PATCH  | `/api/v1/hives/{hive}/hosted-agents/{id}` | Update (redeploy on change) |
| DELETE | `/api/v1/hives/{hive}/hosted-agents/{id}` | Destroy (async) |
| GET    | `/api/v1/hives/{hive}/hosted-agents/{id}/status` | Live status (dashboard polls) |
| GET    | `/api/v1/hosted-agent-presets` | Public preset catalogue |

Request payload example — see FEATURE_HOSTED_AGENTS.md §10.5.

## Test Plan

### Unit Tests

- [ ] `CreateHostedAgentRequest` rejects unknown preset_key.
- [ ] `CreateHostedAgentRequest` rejects model not in preset list.
- [ ] `CreateHostedAgentRequest` rejects unknown `user_env` key.
- [ ] `CreateHostedAgentRequest` requires all preset-declared required envs.
- [ ] `HostedAgentResource` masks secret env values.

### Feature Tests

- [ ] POST creates an agent + hosted_agent + enqueues job.
- [ ] Routes 404 when hosted_agents.enabled is false.
- [ ] PATCH changing the model enqueues a redeploy job.
- [ ] PATCH with identical payload does not enqueue.
- [ ] DELETE returns 202 and enqueues destroy job.
- [ ] Hive scoping prevents cross-hive access.
- [ ] Preset endpoint does not leak image names or credentials.
- [ ] `GET /status` on a `deploying` row probes novps once and returns
  the merged shape (cached + `novps_status` + `latest_deployment`).
- [ ] `GET /status` on a terminal row (`running`/`stopped`/`error`/
  `deleted`) returns the cached row without calling novps.
- [ ] `GET /status` never surfaces `user_env` values.

## Validation Checklist

- [ ] All tests pass
- [ ] PSR-12 compliant
- [ ] Activity logging on create/update/destroy
- [ ] API envelope `{ data, meta, errors }`
- [ ] Form Request validation
- [ ] `user_env` values never surfaced in responses/logs
