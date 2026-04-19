# TASK-214: Enhanced knowledge entry structure

**Status:** done
**Branch:** `task/214-knowledge-enhanced-structure`
**Depends on:** TASK-009
**Blocks:** TASK-219, TASK-223
**Edition:** shared
**Feature doc:** [FEATURE_KNOWLEDGE_GRAPH.md](../features/list-1/FEATURE_KNOWLEDGE_GRAPH.md) §10

## Objective

Enrich the knowledge entry value structure with standardized fields: title, summary, content, source, confidence, tags, format. This makes entries self-describing and enables topic classification, staleness detection, and better context assembly.

## Requirements

### Functional

- [ ] FR-1: Knowledge API accepts and returns enriched value structure: title, summary, content, source, confidence, tags, format
- [ ] FR-2: `confidence` values: high, medium, low — optional, defaults to null
- [ ] FR-3: `tags` is an array of topic tags — optional, defaults to empty
- [ ] FR-4: `format` indicates content format: markdown (default), json, text
- [ ] FR-5: Existing entries without enriched fields continue to work (backward compatible)
- [ ] FR-6: Search and listing endpoints can filter by tags
- [ ] FR-7: `GET /api/v1/hives/{hive}/knowledge?tags=authentication,cache` — filter by tag intersection
- [ ] FR-8: Validation: summary max 500 chars, tags max 20 items, title max 255 chars
- [ ] FR-9: GIN index on value->'tags' for efficient tag filtering
