# TASK-209: Dashboard — channel list + chat view

**Status:** done
**Branch:** `task/209-dashboard-channels`
**Depends on:** TASK-201, TASK-202
**Blocks:** TASK-210
**Edition:** shared
**Feature doc:** [FEATURE_CHANNELS.md](../features/list-1/FEATURE_CHANNELS.md) §15

## Objective

Build the dashboard UI for channels: a list page with filtering and a detail page with a real-time chat view. This is the primary human interface for deliberation.

## Requirements

### Functional

- [ ] FR-1: Channel list page at `/dashboard/channels` with status filters: All, Deliberating, Needs My Approval, Resolved
- [ ] FR-2: Each channel card shows: title, type badge, status indicator, participant count, message count, last message time, pending action (waiting for approval, voting progress)
- [ ] FR-3: Channel detail page at `/dashboard/channels/{id}` with chat-style message timeline
- [ ] FR-4: Message rendering by type: plain text for discussion, card UI for proposals (with vote buttons), banner for decisions, muted for system messages
- [ ] FR-5: Participant sidebar with roles and online status
- [ ] FR-6: "New Channel" button with create form (title, type, participants, resolution policy)
- [ ] FR-7: Real-time updates via Reverb WebSocket — new messages appear without page refresh
- [ ] FR-8: Human can post messages directly from the chat view
- [ ] FR-9: Linked references panel showing related tasks, knowledge entries
- [ ] FR-10: Resolution banner when channel is resolved, showing outcome
- [ ] FR-11: "Create Task" button that pre-fills from channel context
- [ ] FR-12: Unread indicator and badge count in navigation
