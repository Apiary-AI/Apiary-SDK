# TASK-221: Channel resolution -> knowledge entry

**Status:** done
**Branch:** `task/221-channel-resolution-knowledge`
**Depends on:** TASK-207, TASK-216
**Edition:** shared
**Feature doc:** [FEATURE_KNOWLEDGE_GRAPH.md](../features/list-1/FEATURE_KNOWLEDGE_GRAPH.md) §8.2

## Objective

When a channel resolves, automatically create a knowledge entry capturing the decision. Decisions become institutional memory without manual effort. Links the entry to the channel via `decided_in`.

## Requirements

### Functional

- [ ] FR-1: On channel resolution (when `on_resolve.update_knowledge` is configured), auto-create knowledge entry
- [ ] FR-2: Entry key: `decisions:{channel_slug}` or configurable template
- [ ] FR-3: Entry value includes: title, summary (from resolution outcome), content (auto-generated from discussion), participants, date, tags
- [ ] FR-4: Auto-create `decided_in` link to the channel
- [ ] FR-5: Auto-create `relates_to` links via keyword matching with existing entries
- [ ] FR-6: Entry confidence defaults to `high` (it's a confirmed decision)
- [ ] FR-7: Works even if `on_resolve.update_knowledge` is not configured — configurable at hive level as default behavior
- [ ] FR-8: Summary generation from channel messages (template-based: extract key proposals + votes + decision)
