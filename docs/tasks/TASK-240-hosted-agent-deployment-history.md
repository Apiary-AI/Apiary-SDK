# TASK-240: Hosted agent deployment history + rollback

**Status:** pending
**Branch:** `task/240-hosted-agent-deployment-history`
**PR:** —
**Depends on:** TASK-230, TASK-233
**Blocks:** TASK-241
**Edition:** cloud
**Feature doc:** [FEATURE_HOSTED_AGENTS.md](../features/list-1/FEATURE_HOSTED_AGENTS.md) §9, §11.2

## Objective

Let users inspect past deployments and roll back to a previous image tag.
Builds on the `hosted_agent_deployments` table seeded by TASK-227. Rollback
is just a re-deploy with an image tag override.

## Requirements

### Functional

- [ ] FR-1: `GET /api/v1/hives/{hive}/hosted-agents/{id}/deployments`
  returns paginated `hosted_agent_deployments` rows (desc by created_at).
  Each row includes: id, status, image_tag, duration_seconds,
  triggered_by, started_at, completed_at.
- [ ] FR-2: `POST /api/v1/hives/{hive}/hosted-agents/{id}/deployments/{deployment_id}/rollback`
  — writes the historical deployment's `image_tag` to
  `hosted_agents.image_tag_override` (the schema column added in
  TASK-227), then enqueues `DeployHostedAgentJob`. The deploy job reads
  `image_tag_override` and uses it in place of the preset's default
  tag, so subsequent deploys stay pinned to the rolled-back value
  until the user explicitly clears or overwrites the column.
- [ ] FR-3: Rollback is only allowed when the target deployment's status
  is `success`. Non-success → 409.
- [ ] FR-4: Deploy job (TASK-230) captures `image_tag` on every run.
  Where the preset's configured `tag` is `latest`, capture novps's
  resolved image reference from the `apply` response instead so rollback
  targets an immutable digest.
- [ ] FR-5: Dashboard surfaces a table with a "Rollback" action on every
  successful past deployment.

### Non-Functional

- [ ] NFR-1: Rollback uses the same idempotent deploy path — no separate
  code path.
- [ ] NFR-2: Activity log: `hosted_agent.rollback.triggered` with the
  target deployment id.

## Architecture & Design

### Files to Create / Modify

| Action | Path | Purpose |
|--------|------|---------|
| Create | `app/Cloud/Http/Controllers/Api/HostedAgentDeploymentController.php` | List + rollback |
| Modify | `app/Cloud/Jobs/DeployHostedAgentJob.php` | Honor `image_tag_override` |
| Modify | `app/Cloud/Services/HostedAgentDeployer.php` | Capture resolved digest |
| Modify | `routes/api.php` | Register new routes |

### Key Design Decisions

- **Rollback ≠ restoring the old DB row.** Only `image_tag` is rolled
  back. User env, model, replica config stay at current values. If a user
  wants a "full revert" they edit the relevant fields manually.
- **Digest capture is best-effort.** If novps's `apply` response does not
  surface a resolved digest we store the tag as-provided and log a
  warning — rollback will still work on tag values.

## API Changes

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET    | `/api/v1/hives/{hive}/hosted-agents/{id}/deployments` | List |
| POST   | `/api/v1/hives/{hive}/hosted-agents/{id}/deployments/{deployment_id}/rollback` | Rollback |

## Test Plan

### Unit Tests

- [ ] Rollback sets `image_tag_override` on enqueued job.
- [ ] Rollback to a `failed` deployment returns 409.
- [ ] Deploy job persists resolved digest when available.

### Feature Tests

- [ ] List returns deployments in desc order, paginated.
- [ ] Rollback triggers a deploy job that pins the historical tag.
- [ ] Activity log row written.

## Validation Checklist

- [ ] All tests pass
- [ ] PSR-12 compliant
- [ ] Activity logging
- [ ] API envelope
