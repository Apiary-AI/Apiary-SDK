# TASK-243: Channel approval queue backend integration

**Status:** done
**Branch:** `task/243-channel-approval-queue-backend`
**Depends on:** TASK-205, TASK-045, TASK-046, TASK-049
**Edition:** shared
**Feature doc:** [FEATURE_CHANNELS.md](../features/list-1/FEATURE_CHANNELS.md) §5.3, §12.5, §15.3

## Objective

Integrate channel `human_approval` resolution requests into the existing unified approval queue (TASK-049). When a channel reaches a state requiring human approval, an approval queue entry must be created so that pending channel approvals appear alongside pending task approvals in the dashboard.

## Background

The feature doc specifies that channels awaiting `human_approval` resolution appear in the same approval queue as task approvals (§5.3, §12.5, §15.3). The existing approval queue (TASK-049) only handles task/proxy approval requests. This task bridges the gap by making the resolution engine (TASK-205) emit approval queue entries for channels that require human sign-off.

This task depends on the full approval stack: the `ApprovalRequest` model and `ApprovalManager` service (TASK-045), the approval REST API endpoints (TASK-046), and the unified dashboard approval queue (TASK-049). These provide the data model, API layer, and dashboard integration that TASK-243 extends to support channel approvals.

## Requirements

### Functional

- [ ] FR-1: When a channel enters `human_approval` resolution, create an `ApprovalRequest` entry (or equivalent polymorphic record) linked to the channel
- [ ] FR-2: Approval queue entry includes: channel name, channel ID, hive ID, resolution policy details, link to channel detail page
- [ ] FR-3: "Approve" action on the queue entry triggers channel resolution via the resolution engine
- [ ] FR-4: "Request Changes" action posts a system message to the channel and keeps it in `deliberating` state
- [ ] FR-5: Approval entry expires when the channel's resolution timeout fires (if configured)
- [ ] FR-6: Activity log entry on approval queue creation, approval, and rejection
- [ ] FR-7: Real-time update via Reverb when channel approval status changes
- [ ] FR-8: Hive-scoped — channel approvals only visible in the same hive's approval queue

### Non-Functional

- [ ] NFR-1: Reuse existing `ApprovalRequest` model with a polymorphic `approvable` relationship (or add `type` discriminator) to support both task and channel approvals
- [ ] NFR-2: No breaking changes to existing task approval flow
