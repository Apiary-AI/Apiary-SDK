# TASK-251: Python SDK — knowledge graph & link methods

**Status:** done
**Branch:** `task/251-sdk-knowledge-graph-methods`
**Depends on:** TASK-032
**Edition:** shared

## Objective

Add knowledge graph traversal, link management, and index/health methods to the Python SDK. These methods wrap the existing server-side endpoints (TASK-216, TASK-217, TASK-218, TASK-219, TASK-225) so that agents can manage knowledge links, traverse the graph, query auto-maintained indexes, and check knowledge health from Python.

## Requirements

### Functional

- [ ] FR-1: `create_knowledge_link(hive_id, entry_id, ...)` — POST /api/v1/hives/{hive}/knowledge/{entry}/links
- [ ] FR-2: `list_knowledge_links(hive_id, ...)` — GET /api/v1/hives/{hive}/knowledge/links with source/target filters
- [ ] FR-3: `delete_knowledge_link(hive_id, link_id)` — DELETE /api/v1/hives/{hive}/knowledge/links/{link}
- [ ] FR-4: `confirm_knowledge_link(hive_id, link_id)` — POST /api/v1/hives/{hive}/knowledge/links/{link}/confirm
- [ ] FR-5: `dismiss_knowledge_link(hive_id, link_id)` — DELETE /api/v1/hives/{hive}/knowledge/links/{link}/dismiss
- [ ] FR-6: `suggested_links(hive_id, entry_id)` — GET /api/v1/hives/{hive}/knowledge/{entry}/suggested-links
- [ ] FR-7: `get_knowledge_graph(hive_id, entry_id, depth, link_types, max_nodes)` — GET /api/v1/hives/{hive}/knowledge/{entry}/graph
- [ ] FR-8: `knowledge_topics(hive_id)` — GET /api/v1/hives/{hive}/knowledge/index/topics
- [ ] FR-9: `knowledge_decisions(hive_id)` — GET /api/v1/hives/{hive}/knowledge/index/decisions
- [ ] FR-10: `knowledge_by_agent(hive_id, agent_id)` — GET /api/v1/hives/{hive}/knowledge/index/agent/{agent}
- [ ] FR-11: `knowledge_health(hive_id)` — GET /api/v1/hives/{hive}/knowledge/health

### Non-Functional

- [ ] NF-1: Follow existing SDK patterns (parameter naming, `_request` calls, docstrings)
- [ ] NF-2: All new methods covered by unit tests with mocked HTTP calls
- [ ] NF-3: Passes ruff linting
