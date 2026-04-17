# TASK-208: Staged resolution policy

**Status:** done
**Branch:** `task/208-staged-resolution`
**Depends on:** TASK-205
**Edition:** shared
**Feature doc:** [FEATURE_CHANNELS.md](../features/list-1/FEATURE_CHANNELS.md) §5.4

## Objective

Implement the `staged` resolution policy type that chains multiple resolution stages. Common pattern: agents deliberate + reach consensus (stage 1), then human reviews and approves (stage 2).

## Requirements

### Functional

- [ ] FR-1: `staged` resolution_policy with ordered array of stages, each with name, type, and type-specific config
- [ ] FR-2: Track current active stage in channel resolution state
- [ ] FR-3: When current stage conditions are met, auto-advance to next stage
- [ ] FR-4: Each stage output can be referenced by the next stage (e.g., agent proposal feeds human review)
- [ ] FR-5: Channel only resolves when all stages complete
- [ ] FR-6: Stage-specific notifications: "Stage 1 complete, awaiting human approval"
- [ ] FR-7: Reopen sends channel back to first incomplete stage
- [ ] FR-8: Dashboard shows current stage progress indicator
