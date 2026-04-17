# TASK-244: Hosted agent usage data collection

**Status:** pending
**Branch:** `task/244-hosted-agent-usage-collection`
**PR:** —
**Depends on:** TASK-229, TASK-230
**Blocks:** —
**Edition:** cloud
**Feature doc:** [FEATURE_HOSTED_AGENTS.md](../features/list-1/FEATURE_HOSTED_AGENTS.md) §14

## Objective

Capture per-agent runtime usage (replica × time online) so Cloud billing
can charge compute hours. Data collection only — billing rollup lives in
the existing Cloud billing stack.

## Requirements

### Functional

- [ ] FR-1: Scheduled job `CollectHostedAgentUsageJob` runs every 5
  minutes over all `hosted_agents` with `status IN ('running','deploying')`.
- [ ] FR-2: For each agent, calls a novps endpoint that returns current
  replica count + size (likely `GET /public-api/apps/{id}/resources` —
  confirm at implementation time, fall back to `resource.replicas` from
  the last `applyApp` response).
- [ ] FR-3: Writes samples into `hosted_agent_usage_samples`:
    - `id` ULID
    - `hosted_agent_id` FK
    - `sampled_at` timestamp
    - `replica_size` VARCHAR(4) — nullable; **must** be `NULL` when
      `source = 'unavailable'`, **must** be non-null otherwise
    - `replica_count` SMALLINT — nullable; same rule as `replica_size`
    - `source` VARCHAR(20) — one of the enum values
      `'novps-api'` | `'cached-last-apply'` | `'unavailable'` (see FR-3a)
- [ ] FR-3a: `source` enum semantics:
    - `'novps-api'` — fresh reading from the novps public API.
    - `'cached-last-apply'` — novps returned a 5xx / transport error and
      the sampler reused `resource.replicas` from the last successful
      `applyApp` response for that agent.
    - `'unavailable'` — novps was unreachable **and** no cached
      last-apply value is available (e.g. first sample after deploy, or
      cache evicted). Metric columns are `NULL`; the row exists purely
      so rollup/coverage reporting can see the gap.
- [ ] FR-4: Daily rollup job `RollupHostedAgentUsageJob` runs at 02:00
  UTC and writes `hosted_agent_usage_daily` (agent, day, total seconds
  × size-weighted multiplier) — feeds the existing
  `billing_usage_records` table via an adapter in the Cloud billing
  service. Rollup treatment by `source`:
    - `'novps-api'` and `'cached-last-apply'` rows contribute to
      `weighted_seconds` and `sample_count` normally.
    - `'unavailable'` rows are **excluded** from `weighted_seconds`
      (we never bill users for novps outages) but are counted in
      `unavailable_sample_count` so coverage / availability reporting
      can surface gaps. Interpolation across an `'unavailable'` gap is
      explicitly **not** performed in v1 — gaps stay as gaps.
- [ ] FR-5: Failure mode: if sampling throws, job logs and continues with
  the next agent — never blocks other samples.
- [ ] FR-6: Usage tables live under `database/migrations/cloud/` (cloud
  only).

### Non-Functional

- [ ] NFR-1: Sampling must be resilient to novps API outages — when the
  novps API is unreachable and no cached last-apply value is available,
  the sampler records a row with `source = 'unavailable'` and null
  metric values (per FR-3a) rather than failing or skipping the agent.
- [ ] NFR-2: Rollup multiplier lives in
  `config('apiary.hosted_agents.size_multipliers')` so pricing can be
  adjusted without a code change.

## Architecture & Design

### Files to Create / Modify

| Action | Path | Purpose |
|--------|------|---------|
| Create | `database/migrations/cloud/YYYY_create_hosted_agent_usage_samples.php` | Sample table |
| Create | `database/migrations/cloud/YYYY_create_hosted_agent_usage_daily.php` | Daily rollup |
| Create | `app/Cloud/Jobs/CollectHostedAgentUsageJob.php` | 5-min sampler |
| Create | `app/Cloud/Jobs/RollupHostedAgentUsageJob.php` | Daily aggregate |
| Create | `app/Cloud/Services/HostedAgentUsageSampler.php` | Novps read + persist |
| Modify | `app/Console/Kernel.php` (or `routes/console.php`) | Schedule both jobs |
| Modify | `config/apiary.php` | `hosted_agents.size_multipliers` |

### Key Design Decisions

- **Samples + rollup, not continuous metering.** 5-min sampling is
  accurate enough given replicas change infrequently. Eliminates the
  need for a metering daemon.
- **Size multipliers as data, not code.** Price changes happen monthly —
  config-driven.
- **Cached-last-apply fallback.** Treats a 5xx from novps as "assume
  unchanged since last successful observation." Avoids billing users for
  novps outages.
- **`unavailable` is a first-class source value.** When neither a live
  novps reading nor a cached last-apply value is available, the sampler
  still writes a row, but with `source = 'unavailable'` and null
  metrics. This keeps the sample stream gap-free for coverage
  reporting, and the rollup explicitly excludes those rows from billed
  `weighted_seconds`.

## Database Changes

```sql
CREATE TABLE hosted_agent_usage_samples (
    id               VARCHAR(26) PRIMARY KEY,
    hosted_agent_id  VARCHAR(26) NOT NULL REFERENCES hosted_agents(id),
    sampled_at       TIMESTAMP NOT NULL,
    replica_size     VARCHAR(4),    -- NULL iff source = 'unavailable'
    replica_count    SMALLINT,      -- NULL iff source = 'unavailable'
    source           VARCHAR(20) NOT NULL,
    CONSTRAINT hosted_agent_usage_samples_source_chk
        CHECK (source IN ('novps-api', 'cached-last-apply', 'unavailable')),
    CONSTRAINT hosted_agent_usage_samples_metrics_chk
        CHECK (
            (source = 'unavailable' AND replica_size IS NULL AND replica_count IS NULL)
            OR
            (source <> 'unavailable' AND replica_size IS NOT NULL AND replica_count IS NOT NULL)
        )
);

CREATE INDEX idx_hosted_agent_usage_samples_agent_time
    ON hosted_agent_usage_samples (hosted_agent_id, sampled_at DESC);

CREATE TABLE hosted_agent_usage_daily (
    id                         VARCHAR(26) PRIMARY KEY,
    hosted_agent_id            VARCHAR(26) NOT NULL REFERENCES hosted_agents(id),
    day                        DATE NOT NULL,
    weighted_seconds           INTEGER NOT NULL DEFAULT 0,
    sample_count               INTEGER NOT NULL DEFAULT 0,
    unavailable_sample_count   INTEGER NOT NULL DEFAULT 0,

    UNIQUE (hosted_agent_id, day)
);
```

## Test Plan

### Unit Tests

- [ ] Sampler writes `source = 'cached-last-apply'` on novps 5xx when a
  cached last-apply value exists for the agent.
- [ ] Sampler writes `source = 'unavailable'` with null
  `replica_size` / `replica_count` on novps 5xx when no cached
  last-apply value exists.
- [ ] DB rejects an `unavailable` row that has non-null metrics, and
  rejects a non-`unavailable` row that has null metrics (CHECK
  constraint).
- [ ] Rollup weights sizes per config multipliers and excludes
  `unavailable` rows from `weighted_seconds` while incrementing
  `unavailable_sample_count`.
- [ ] Rollup is idempotent on re-run (upsert on (agent, day)).

### Feature Tests

- [ ] Scheduler registration: both jobs appear in `schedule:list`.
- [ ] Sampler run against fake novps produces expected sample row.
- [ ] Destroyed agent stops appearing in sample set.

## Validation Checklist

- [ ] All tests pass
- [ ] PSR-12 compliant
- [ ] No credentials logged
- [ ] Migrations cloud-only
