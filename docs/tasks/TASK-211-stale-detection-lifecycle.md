# TASK-211: Stale detection job + channel lifecycle

**Status:** planning
**Branch:** `task/211-stale-detection-lifecycle`
**Depends on:** TASK-200, TASK-202, TASK-205, TASK-206
**Edition:** shared
**Feature doc:** [FEATURE_CHANNELS.md](../features/list-1/FEATURE_CHANNELS.md) §4

## Objective

Implement the scheduled job that detects stale channels (no activity for `stale_after` seconds) and transitions them. Also handle the full lifecycle state machine: open -> deliberating -> resolved/stale/archived.

## Requirements

### Functional

- [ ] FR-1: Scheduled artisan command that runs every 5 minutes
- [ ] FR-2: Finds channels with status in (open, deliberating) where `last_message_at` + `stale_after` < now
- [ ] FR-3: Transitions matching channels to `stale` status
- [ ] FR-4: Notifies participants that the channel went stale (system message)
- [ ] FR-5: Any new message on a `stale` channel reopens it to `deliberating`
- [ ] FR-6: Vote timeout handling: check proposals past their vote_deadline, apply timeout strategy
- [ ] FR-7: Auto-archive resolved channels after configurable period (default 30 days)
- [ ] FR-8: Activity log on all status transitions
