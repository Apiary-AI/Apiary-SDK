# TASK-225: Knowledge Curator template + health score API

**Status:** done
**Branch:** `task/225-knowledge-curator-health`
**Depends on:** TASK-215, TASK-216
**Edition:** shared
**Feature doc:** [FEATURE_KNOWLEDGE_GRAPH.md](../features/list-1/FEATURE_KNOWLEDGE_GRAPH.md) §6

## Objective

Create the Knowledge Curator persona template (scheduled maintenance agent) and the health score API. The curator finds stale entries, contradictions, broken links, duplicates, and gaps. The health API exposes a score + recommendations.

## Requirements

### Functional

- [ ] FR-1: `GET /api/v1/hives/{hive}/knowledge/health` — health score (0-100), grade (A+ to F), and metrics
- [ ] FR-2: Metrics: total_entries, linked_percentage, avg_links_per_entry, stale_entries, broken_links, orphan_entries, index_freshness, topic_coverage
- [ ] FR-3: Recommendations array: actionable suggestions (contradictions, orphans, thin topics)
- [ ] FR-4: Curator persona template with SOUL + AGENT documents defining daily/weekly routines
- [ ] FR-5: Daily checks: stale entries (no reads in 30 days), broken links, index freshness, duplicates
- [ ] FR-6: Weekly checks: contradiction detection, gap detection, missing links, confidence decay
- [ ] FR-7: Curator writes health report to knowledge store as `_health:latest` entry
- [ ] FR-8: Curator can be scheduled via TASK-078 schedule system (default: daily at 2 AM)
- [ ] FR-9: Dashboard health widget: score badge + top 3 recommendations on Knowledge Explorer page
