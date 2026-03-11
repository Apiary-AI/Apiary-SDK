# TASK-047: Approval Decision Notification & Delivery Flow

**Status:** In Progress
**Phase:** 2 — Service Proxy & Security
**Branch:** `task/047-approval-decision-delivery`
**Depends On:** TASK-045 (Approval requests model + flow), TASK-046 (Approval API)

---

## Objective

Add real-time WebSocket broadcasting for approval request state changes so
the dashboard receives live updates and agents can discover decisions
efficiently. Follows the existing event broadcasting pattern used by
`TaskStatusChanged`, `AgentStatusChanged`, and `KnowledgeEntryChanged`.

## Requirements

### 1. ApprovalStatusChanged Event

Create `app/Events/ApprovalStatusChanged.php` that:

- Implements `ShouldBroadcastNow` (same as all existing events)
- Has a static `fromApproval()` factory method
- Broadcasts to `PrivateChannel("hive.{hiveId}")` (same channel as other events)
- Uses `broadcastAs()` returning `'approval.status_changed'`
- Includes a `changeType` field: `created | approved | denied | expired`
- Payload includes: id, status, agent_id, service_id, request_method,
  request_path, reason, decided_by, decided_at, expires_at

### 2. ApprovalManager Integration

Dispatch `ApprovalStatusChanged` from `ApprovalManager` on every state transition:

- `create()` → `changeType: 'created'`
- `approve()` → `changeType: 'approved'`
- `deny()` → `changeType: 'denied'`
- `expirePending()` → `changeType: 'expired'` (one event per expired record)

Use `DB::afterCommit()` with try/catch for safe dispatch (matching the
`ActivityLogger` pattern). Skip when broadcasting is disabled.

### 3. No Migration Required

No schema changes. This task adds event broadcasting only.

## Non-Goals

- Email / Slack / webhook notification channels (future: TASK-105 system webhooks)
- Dashboard UI for approval queue (TASK-049)
- New API endpoints (existing TASK-046 API sufficient for agent polling)

## Test Plan

- Verify `ApprovalStatusChanged` event is dispatched on create
- Verify event is dispatched on approve
- Verify event is dispatched on deny
- Verify events are dispatched on expirePending (one per record)
- Verify event payload contains correct fields and changeType
- Verify event broadcasts to correct hive channel
- Verify broadcast failure does not abort the state transition
- Verify no event dispatched when broadcasting is disabled

## Files

| File | Action |
|------|--------|
| `app/Events/ApprovalStatusChanged.php` | Create |
| `app/Services/ApprovalManager.php` | Modify (add event dispatch) |
| `tests/Feature/ApprovalDecisionDeliveryTest.php` | Create |
| `docs/tasks/TASK-047-approval-decision-delivery.md` | Create |
