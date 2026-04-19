# TASK-219: Auto-index entries + update job

**Status:** done
**Branch:** `task/219-auto-index-entries`
**Depends on:** TASK-214, TASK-216
**Edition:** shared
**Feature doc:** [FEATURE_KNOWLEDGE_GRAPH.md](../features/list-1/FEATURE_KNOWLEDGE_GRAPH.md) §4

## Objective

Implement system-maintained index entries that provide a compact overview of the knowledge base. Three index types: _index:topics, _index:decisions, _index:agent:{id}. A scheduled job keeps them fresh.

## Requirements

### Functional

- [ ] FR-1: `_index:topics` entry: list of topics with entry_count, key_entries, summary, last_updated — auto-classified from tags
- [ ] FR-2: `_index:decisions` entry: chronological decision log extracted from entries with confidence=high and tags containing "decision"
- [ ] FR-3: `_index:agent:{id}` entries: per-agent knowledge map with frequently_read, authored, expertise_topics
- [ ] FR-4: Scheduled artisan command (every 5 minutes or configurable) to update index entries
- [ ] FR-5: For small knowledge bases (<500 entries): full recompute
- [ ] FR-6: For large (>500): incremental — only process entries changed since last run
- [ ] FR-7: Index entries use scope `hive` and are readable by all agents in the hive
- [ ] FR-8: Index entries have `_index:` key prefix — reserved namespace, cannot be created by agents directly
- [ ] FR-9: Topic classification: derive from tags, or keyword-based grouping for untagged entries
