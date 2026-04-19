# TASK-213: Knowledge FTS — tsvector + gin index + search API

**Status:** done
**Branch:** `task/213-knowledge-fts`
**Depends on:** TASK-009
**Edition:** shared
**Feature doc:** [FEATURE_KNOWLEDGE_GRAPH.md](../features/list-1/FEATURE_KNOWLEDGE_GRAPH.md) §3 Layer 1

## Objective

Add full-text search to the Knowledge Store using PostgreSQL native tsvector. Zero new dependencies. Agents can search knowledge by natural language query instead of exact key.

## Requirements

### Functional

- [ ] FR-1: Add `search_vector` tsvector column to `knowledge_entries`, generated from key + value->title + value->content + value->summary
- [ ] FR-2: GIN index on `search_vector`
- [ ] FR-3: `GET /api/v1/hives/{hive}/knowledge/search?q={query}&limit={n}` — full-text search endpoint
- [ ] FR-4: Response includes: id, key, score (ts_rank), snippet (ts_headline), value
- [ ] FR-5: Results ordered by relevance score descending
- [ ] FR-6: Hive-scoped: only search entries in the agent's hive (+ apiary-scoped if permitted)
- [ ] FR-7: Handle empty query gracefully (return empty results, not error)
- [ ] FR-8: Configurable language for tsvector (default: english)
- [ ] FR-9: Migration to backfill search_vector for existing entries

### Non-Functional

- [ ] NFR-1: No external dependencies — pure PostgreSQL
- [ ] NFR-2: Search should complete under 100ms for knowledge bases up to 10k entries
