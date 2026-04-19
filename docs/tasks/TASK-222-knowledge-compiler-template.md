# TASK-222: Knowledge Compiler persona template

**Status:** done
**Branch:** `task/222-knowledge-compiler-template`
**Depends on:** TASK-219
**Edition:** shared
**Feature doc:** [FEATURE_KNOWLEDGE_GRAPH.md](../features/list-1/FEATURE_KNOWLEDGE_GRAPH.md) §5

## Objective

Create a built-in persona template for the Knowledge Compiler agent — a system agent that transforms raw data (task results, channel discussions, proxy responses) into structured, linked knowledge entries.

## Requirements

### Functional

- [ ] FR-1: Persona template with SOUL, AGENT, RULES documents as defined in feature spec §5.2
- [ ] FR-2: Template registered in the persona template system (TASK-133)
- [ ] FR-3: Configurable triggers in hive settings: task_completed (min_result_size, exclude_types), channel_resolved, knowledge_batch (threshold)
- [ ] FR-4: When trigger fires, auto-create `compile_knowledge` task targeted at the compiler agent
- [ ] FR-5: Compiler agent extracts key facts, checks for existing entries, creates/updates entries with links
- [ ] FR-6: Entry format enforcement: title, summary (1-3 sentences), content (markdown), source, confidence, tags
- [ ] FR-7: `supersedes` link created when an entry replaces an older one
- [ ] FR-8: Compiler checks `_index:topics` for consistent terminology
