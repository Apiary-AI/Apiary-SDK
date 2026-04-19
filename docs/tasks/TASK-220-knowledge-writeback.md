# TASK-220: Task completion -> knowledge write-back + auto-linking

**Status:** done
**Branch:** `task/220-knowledge-writeback`
**Depends on:** TASK-216, TASK-018, TASK-218, TASK-219
**Edition:** shared
**Feature doc:** [FEATURE_KNOWLEDGE_GRAPH.md](../features/list-1/FEATURE_KNOWLEDGE_GRAPH.md) §8.1

## Objective

Enhance the task completion flow so that `knowledge_entries` in the completion payload automatically get linked to the task, the completing agent, and related entries. The `auto_link: true` flag triggers the full write-back pipeline.

## Requirements

### Functional

- [ ] FR-1: On task completion with `knowledge_entries` and `auto_link: true`, auto-create links:
  - `derived_from` -> the completed task
  - `authored_by` -> the completing agent
- [ ] FR-2: Scan new entry tags/keywords against existing entries -> suggest/create `relates_to` links (reuse TASK-218 auto-linking)
- [ ] FR-3: Update `_index:topics` for affected topic (reuse TASK-219 index updater)
- [ ] FR-4: Queue `compile_knowledge` task if auto-compile is enabled in hive settings
- [ ] FR-5: `auto_link` flag is optional, defaults to false for backward compatibility
- [ ] FR-6: All write-back processing happens async (queued job) to not slow down task completion
- [ ] FR-7: Activity log entries for auto-created links
