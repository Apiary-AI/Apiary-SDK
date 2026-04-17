# TASK-218: Auto-linking on knowledge create

**Status:** done
**Branch:** `task/218-auto-linking`
**Depends on:** TASK-216
**Edition:** shared
**Feature doc:** [FEATURE_KNOWLEDGE_GRAPH.md](../features/list-1/FEATURE_KNOWLEDGE_GRAPH.md) §3 Layer 2

## Objective

When a knowledge entry is created, automatically detect and suggest/create links to related entries. Uses keyword overlap and entity extraction (file paths, PR numbers, agent names).

## Requirements

### Functional

- [ ] FR-1: On knowledge entry create/update, run auto-link detection as async job
- [ ] FR-2: Keyword overlap: find entries sharing significant terms with the new entry -> suggest `relates_to` links
- [ ] FR-3: Entity extraction: detect references to tasks (tsk_*), agents (agt_*), channels (ch_*), file paths, PR numbers -> auto-link to those entities
- [ ] FR-4: Tag matching: entries sharing 2+ tags -> suggest `relates_to` links
- [ ] FR-5: Each auto-link gets a `confidence` score in metadata (0-1)
- [ ] FR-6: High confidence (>0.8) -> auto-created. Low confidence -> suggested (stored with `status: suggested`)
- [ ] FR-7: `GET /api/v1/hives/{hive}/knowledge/{id}/suggested-links` — list suggested links for confirmation
- [ ] FR-8: `POST /api/v1/hives/{hive}/knowledge/links/{id}/confirm` — confirm a suggested link
- [ ] FR-9: `DELETE /api/v1/hives/{hive}/knowledge/links/{id}/dismiss` — dismiss a suggestion
- [ ] FR-10: Configurable per-hive: `knowledge.auto_link.enabled` (default true)
