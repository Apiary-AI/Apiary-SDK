# TASK-203: Channel participants API

**Status:** done
**Branch:** `task/203-channel-participants-api`
**Depends on:** TASK-201
**Edition:** shared
**Feature doc:** [FEATURE_CHANNELS.md](../features/list-1/FEATURE_CHANNELS.md) §10.3

## Objective

Implement participant management endpoints for channels: add, remove, and change roles. Roles: initiator, contributor, reviewer, observer, decider.

## Requirements

### Functional

- [ ] FR-1: `POST /api/v1/hives/{hive}/channels/{id}/participants` — add participant (agent_id or user_id, role, mention_policy)
- [ ] FR-2: `DELETE /api/v1/hives/{hive}/channels/{id}/participants/{participant_id}` — remove participant
- [ ] FR-3: `PATCH /api/v1/hives/{hive}/channels/{id}/participants/{participant_id}` — change role or mention_policy
- [ ] FR-4: Validate role against allowed values: initiator, contributor, reviewer, observer, decider
- [ ] FR-5: Validate mention_policy: all, mention_only
- [ ] FR-6: Prevent removing the last `decider` if resolution_policy requires one
- [ ] FR-7: System message auto-posted when participant joins or leaves
- [ ] FR-8: Activity log on participant changes
