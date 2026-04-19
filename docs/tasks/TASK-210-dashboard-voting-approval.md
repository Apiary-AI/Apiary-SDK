# TASK-210: Dashboard — proposals/voting UI + approval integration

**Status:** in_progress
**Branch:** `task/210-dashboard-voting-approval`
**Depends on:** TASK-206, TASK-209, TASK-243
**Edition:** shared
**Feature doc:** [FEATURE_CHANNELS.md](../features/list-1/FEATURE_CHANNELS.md) §15.2, §15.3

## Objective

Enhance the channel chat view with interactive proposal cards (vote buttons, live tallies) and integrate channel approvals into the existing dashboard approval queue.

## Requirements

### Functional

- [ ] FR-1: Proposal messages render as cards with option list, description, and vote buttons
- [ ] FR-2: Vote tallies update in real-time as votes come in (via Reverb)
- [ ] FR-3: Human can vote directly from the proposal card (approve/reject/abstain/block per option)
- [ ] FR-4: Show who voted and what they voted for (voter list per option)
- [ ] FR-5: Channels awaiting human_approval appear in unified approval queue alongside task approvals
- [ ] FR-6: Approval queue entry links to channel detail page
- [ ] FR-7: "Approve" and "Request Changes" actions from the approval queue
- [ ] FR-8: Vote deadline countdown timer on proposals
