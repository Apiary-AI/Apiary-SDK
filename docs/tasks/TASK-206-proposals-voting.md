# TASK-206: Proposals + voting

**Status:** done
**Branch:** `task/206-proposals-voting`
**Depends on:** TASK-205
**Blocks:** TASK-210
**Edition:** shared
**Feature doc:** [FEATURE_CHANNELS.md](../features/list-1/FEATURE_CHANNELS.md) §9.2, §5.2

## Objective

Implement structured proposals and voting within channels. Agents post `proposal` messages with options, participants vote via `vote` messages, and the system tallies votes and triggers resolution when consensus threshold is met.

## Requirements

### Functional

- [ ] FR-1: `proposal` message type with metadata: options (array of {key, title, description}), vote_deadline
- [ ] FR-2: `vote` message type with metadata: vote (approve/reject/abstain/block), option_key, proposal_ref
- [ ] FR-3: Votes stored in denormalized `channel_votes` table for fast counting
- [ ] FR-4: One vote per participant per proposal — new vote replaces previous (upsert)
- [ ] FR-5: Vote tally available on proposal: counts per option, approve/reject/abstain/block totals
- [ ] FR-6: Auto-trigger resolution check on each vote (delegates to ResolutionEngine)
- [ ] FR-7: `block` vote is a hard veto — prevents resolution regardless of threshold
- [ ] FR-8: Vote deadline: if set and reached, apply timeout strategy from resolution_policy
- [ ] FR-9: API to get vote tally for a specific proposal: `GET /api/v1/hives/{hive}/channels/{id}/messages/{proposal_id}/votes`
