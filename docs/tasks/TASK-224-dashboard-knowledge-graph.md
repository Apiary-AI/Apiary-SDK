# TASK-224: Dashboard — Knowledge Explorer graph view

**Status:** in_progress
**Branch:** `task/224-dashboard-knowledge-graph`
**Depends on:** TASK-216, TASK-217
**Edition:** shared
**Feature doc:** [FEATURE_KNOWLEDGE_GRAPH.md](../features/list-1/FEATURE_KNOWLEDGE_GRAPH.md) §9

## Objective

Build an interactive graph visualization for the Knowledge Explorer dashboard page. Nodes are entries, edges are links. Users can click, filter by topic, and explore the knowledge graph visually.

## Requirements

### Functional

- [ ] FR-1: Graph view on `/dashboard/knowledge/graph` using a JS graph library (e.g., react-force-graph, d3-force, or vis-network)
- [ ] FR-2: Nodes represent knowledge entries, sized by link_count, colored by topic/tags
- [ ] FR-3: Edges represent links, labeled by link_type, styled by type (dashed for suggested, solid for confirmed)
- [ ] FR-4: Click node -> sidebar showing entry content, all links, stats (read_count, last_read_at)
- [ ] FR-5: Click topic filter -> show only entries in that topic
- [ ] FR-6: Search bar to find and focus on specific entries
- [ ] FR-7: Health summary bar: total entries, linked %, stale count, orphan count
- [ ] FR-8: Zoom, pan, and drag support
- [ ] FR-9: Toggle between graph view and existing list/table view
- [ ] FR-10: Performance: lazy-load nodes, limit to ~200 visible at once, paginate or cluster for larger graphs
