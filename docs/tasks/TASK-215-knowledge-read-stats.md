# TASK-215: Knowledge read stats tracking

**Status:** done
**Branch:** `task/215-knowledge-read-stats`
**Depends on:** TASK-009
**Blocks:** TASK-225
**Edition:** shared
**Feature doc:** [FEATURE_KNOWLEDGE_GRAPH.md](../features/list-1/FEATURE_KNOWLEDGE_GRAPH.md) §10

## Objective

Track read access on knowledge entries: read_count, last_read_at, last_read_by. This data feeds staleness detection (curator identifies entries nobody reads) and agent knowledge maps.

## Requirements

### Functional

- [ ] FR-1: Add columns to `knowledge_entries`: `read_count` (integer, default 0), `last_read_at` (timestamp, nullable), `last_read_by` (varchar, nullable — agent_id)
- [ ] FR-2: Increment read_count and update last_read_at/last_read_by on every GET by key or GET by id
- [ ] FR-3: Bulk reads (list/search) do NOT increment read stats (only explicit single-entry reads)
- [ ] FR-4: Stats visible in entry response: `stats: { read_count, last_read_at, last_read_by }`
- [ ] FR-5: Async update (queue job or after-response) to avoid slowing read requests
- [ ] FR-6: `GET /api/v1/hives/{hive}/knowledge?sort=least_read` — sort by read_count ascending (find neglected entries)
- [ ] FR-7: `GET /api/v1/hives/{hive}/knowledge?stale_days=30` — entries not read in N days
