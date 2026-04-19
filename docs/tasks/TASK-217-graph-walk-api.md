# TASK-217: Graph walk API

**Status:** done
**Branch:** `task/217-graph-walk-api`
**Depends on:** TASK-216
**Blocks:** TASK-223, TASK-224
**Edition:** shared
**Feature doc:** [FEATURE_KNOWLEDGE_GRAPH.md](../features/list-1/FEATURE_KNOWLEDGE_GRAPH.md) §3 Layer 2

## Objective

Implement the graph walk API: "give me everything connected to this entry, N hops deep." This is the foundation for context assembly — walking the graph from task-related entries to discover relevant context.

## Requirements

### Functional

- [ ] FR-1: `GET /api/v1/hives/{hive}/knowledge/{id}/graph?depth={n}&link_types={csv}` — walk graph from entry
- [ ] FR-2: Response includes `nodes` array (id, key, depth, link type that reached it) and `edges` array (from, to, type)
- [ ] FR-3: Default depth: 2, max depth: 5
- [ ] FR-4: Filter by link_types: only follow specified link types (optional, default all)
- [ ] FR-5: Deduplicate nodes — if reached via multiple paths, include once at shallowest depth
- [ ] FR-6: Respect hive scoping — only include nodes the requesting agent can see
- [ ] FR-7: Max nodes limit (default 50) to prevent explosion on highly-connected graphs
- [ ] FR-8: Include the root node at depth 0
- [ ] FR-9: Efficient implementation using recursive CTE or iterative BFS with the links table
