# TASK-223: Context Assembly pipeline

**Status:** done
**Branch:** `task/223-context-assembly`
**Depends on:** TASK-217, TASK-214
**Edition:** shared
**Feature doc:** [FEATURE_KNOWLEDGE_GRAPH.md](../features/list-1/FEATURE_KNOWLEDGE_GRAPH.md) §7

## Objective

Implement the Context Assembly pipeline — the payoff of the knowledge graph. When an agent gets a task, the system automatically assembles a rich context window from persona, task payload, explicit references, graph walks, and agent memory. This is what makes agents automatically smarter.

## Requirements

### Functional

- [ ] FR-1: `ContextAssemblyService` that runs the 8-step pipeline: persona -> task context -> explicit refs -> graph walk -> (semantic search placeholder) -> agent memory -> compress & rank -> format
- [ ] FR-2: Assembled context delivered in task poll/claim response under `context` key
- [ ] FR-3: Each context section has: type, key/id, title, summary, relevance score, source (which pipeline step)
- [ ] FR-4: Token budget system: configurable per-hive and per-task-type (default 12,000 tokens)
- [ ] FR-5: Section priorities configurable (persona + task payload never dropped)
- [ ] FR-6: When over budget: summarize longer entries, drop lowest-relevance sections
- [ ] FR-7: Relevance ranking: score x freshness x link proximity
- [ ] FR-8: Opt-out: `include_context=false` on poll to skip assembly
- [ ] FR-9: Selective assembly: `context_sections=[explicit_refs, graph_walk]` to request specific sections
- [ ] FR-10: `POST /api/v1/hives/{hive}/context/preview` — preview what context would be assembled (for dashboard debugging)
- [ ] FR-11: Context budget configuration in hive settings (default_budget_tokens, budgets_per_type, section_priorities, compression strategy)
