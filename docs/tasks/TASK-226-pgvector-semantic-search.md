# TASK-226: pgvector + embeddings + semantic search

**Status:** in_progress
**Branch:** `task/226-pgvector-semantic-search`
**Depends on:** TASK-213, TASK-223
**Edition:** shared
**Feature doc:** [FEATURE_KNOWLEDGE_GRAPH.md](../features/list-1/FEATURE_KNOWLEDGE_GRAPH.md) §3 Layer 3

## Objective

Add semantic search to the Knowledge Store using pgvector. Embeddings are computed on write (async job). Search combines FTS for exact matches + semantic for conceptual matches, merged and reranked.

## Requirements

### Functional

- [ ] FR-1: Install pgvector extension (`CREATE EXTENSION vector`)
- [ ] FR-2: Add `embedding` column (vector(1536)) to `knowledge_entries`
- [ ] FR-3: IVFFlat index on embedding column for cosine similarity
- [ ] FR-4: Async job `ComputeEmbedding` dispatched on every knowledge entry create/update
- [ ] FR-5: Embedding provider configurable: OpenAI ada-002 (default) or Anthropic, or local model
- [ ] FR-6: `GET /api/v1/hives/{hive}/knowledge/search?q={query}&semantic=true` — semantic search returning similarity scores
- [ ] FR-7: Hive-scoped: only search entries the agent can access
- [ ] FR-8: Backfill job to compute embeddings for existing entries
- [ ] FR-9: Skip embedding computation for entries under configurable minimum size

## Deferred

The following capabilities are deferred to a future task: combined search (FTS + semantic + reranking), context assembly semantic section integration.
