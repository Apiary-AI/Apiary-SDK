# TASK-205: Resolution engine

**Status:** done
**Branch:** `task/205-resolution-engine`
**Depends on:** TASK-202
**Blocks:** TASK-206, TASK-207, TASK-208
**Edition:** shared
**Feature doc:** [FEATURE_CHANNELS.md](../features/list-1/FEATURE_CHANNELS.md) §5, §10.4

## Objective

Implement the resolution engine that evaluates whether a channel's resolution_policy conditions are met and transitions it to `resolved`. Three base policy types: agent_decision, consensus, human_approval. Also implement manual resolve and reopen endpoints.

## Requirements

### Functional

- [ ] FR-1: `POST /api/v1/hives/{hive}/channels/{id}/resolve` — manual resolution by authorized participant
- [ ] FR-2: `POST /api/v1/hives/{hive}/channels/{id}/reopen` — reopen a stale or resolved channel back to deliberating
- [ ] FR-3: `ResolutionEngine` service that evaluates policy conditions
- [ ] FR-4: `agent_decision` policy: any participant with role in `allowed_roles` can resolve by posting a `decision` message
- [ ] FR-5: `consensus` policy: auto-resolve when vote threshold met and min_votes reached, with no `block` votes
- [ ] FR-6: `human_approval` policy: resolve when required number of human approvals received
- [ ] FR-7: On timeout: support `majority_wins`, `fail` (mark stale), `extend` strategies
- [ ] FR-8: Store resolution data: type, outcome, materialized_tasks, decided_by, decided_at
- [ ] FR-9: Activity log on resolve and reopen
- [ ] FR-10: Broadcast resolution event via Reverb
- [ ] FR-11: Block vote = hard veto, always prevents resolution regardless of threshold
