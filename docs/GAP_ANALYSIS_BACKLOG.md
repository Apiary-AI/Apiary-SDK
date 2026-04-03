# Gap Analysis Backlog

> Generated 2026-04-03 from analysis of the last ~100 merged PRs.
> These are **integration gaps** — features that are partially implemented,
> missing their UI/API/SDK counterpart, or architecturally incomplete.
> Each item has a short spec describing what's needed.

---

## Priority 1 — SDK & API Coverage

### GAP-001: SDK methods for workflows, templates, experiments

**Problem:** The Python and Shell SDKs have no methods for features shipped
in the last 2 weeks: workflows, agent templates, experiments.
Every agent using these features must make raw HTTP calls.

**Scope:** Python SDK (`sdk/python/src/apiary_sdk/client.py`) + Shell SDK (`sdk/shell/src/apiary-sdk.sh`)

**Spec:**

Python SDK additions to `ApiaryClient`:
```python
# Workflows
def list_workflows(hive_id) -> list
def get_workflow(hive_id, workflow_id) -> dict
def run_workflow(hive_id, workflow_id, payload={}) -> dict  # returns run
def get_workflow_run(hive_id, workflow_id, run_id) -> dict
def cancel_workflow_run(hive_id, workflow_id, run_id) -> dict

# Agent Templates
def list_agent_templates(hive_id) -> list
def get_agent_template(hive_id, template_id) -> dict
def install_agent_template(hive_id, template_id) -> dict

# Experiments
def create_experiment(hive_id, agent_id, variant_persona_id, ...) -> dict
def get_experiment(hive_id, experiment_id) -> dict
def get_experiment_results(hive_id, experiment_id) -> dict
```

Shell SDK: equivalent functions using curl + jq.

**Depends on:** Existing API endpoints (all already exist in `routes/api.php`)

---

### GAP-002: Expose marketplace at `/api/v1/agent-templates/`

**Problem:** Agent templates are only accessible through dashboard controllers.
Agents cannot browse or install templates programmatically via the agent API.

**Scope:** New API controller + routes

**Spec:**

```
GET    /api/v1/hives/{hive}/agent-templates             List available templates
GET    /api/v1/hives/{hive}/agent-templates/{template}   Get template details
POST   /api/v1/hives/{hive}/agent-templates/{template}/install  Install template
```

- Requires `marketplace.read` permission for browsing
- Requires `marketplace.install` permission for installation
- Install creates the agent + persona in the caller's hive
- Response format matches existing API envelope (`{ data, meta, errors }`)

**Depends on:** TASK-165 (agent template model, ✅), TASK-166 (marketplace API, ✅)

---

## Priority 2 — Incomplete Feature Wiring

### GAP-003: TASK-192 — Knowledge references need CRUD API + builder UI

**Problem:** `WorkflowStepKnowledge` model and migration exist, but there's no
API to attach/detach knowledge entries to workflow steps, and the visual builder
doesn't expose this capability.

**Scope:** API controller + workflow builder UI

**Spec:**

API:
```
POST   /api/v1/hives/{hive}/workflows/{workflow}/steps/{step}/knowledge
       { knowledge_entry_id, role: "context"|"instruction"|"example" }
GET    /api/v1/hives/{hive}/workflows/{workflow}/steps/{step}/knowledge
DELETE /api/v1/hives/{hive}/workflows/{workflow}/steps/{step}/knowledge/{id}
```

Builder UI:
- Section in the step panel: "Knowledge Context"
- Dropdown to select from hive's knowledge entries
- Role selector (context / instruction / example)
- List of attached entries with remove button
- Attached knowledge is injected into the step's prompt context at runtime

**Depends on:** TASK-192 model (merged), Knowledge API (TASK-020, ✅)

---

### GAP-004: TASK-193 — Built-in workflow templates

**Problem:** The loop step (TASK-191) and workflow engine are ready, but there
are no pre-built templates. Users must build workflows from scratch.

**Scope:** Seed data + template selector UI in workflow builder

**Spec:**

Templates to ship:
1. **Plan-Build-QA** — 3 agent steps: plan → build → evaluate (with condition for retry)
2. **Code Review Pipeline** — webhook trigger → parallel file review (fan_out) → aggregate → comment
3. **Generator-Evaluator Loop** — loop step with generator (coding) and evaluator (qa)
4. **Data Pipeline** — schedule trigger → fetch → transform → validate (loop) → load

Each template is a JSON workflow definition stored in a seeder.

UI:
- "Start from template" button on the workflow list page
- Template picker modal showing name, description, step count, preview diagram
- Selecting a template pre-fills the builder with the template's steps

**Depends on:** TASK-191 (loop step, ✅), TASK-177 (workflow CRUD API, ✅)

---

### GAP-005: TASK-194 — QA evaluator persona template

**Problem:** The loop step enables generator-evaluator patterns, but there's
no persona template tuned for skeptical evaluation.

**Scope:** Persona template seed data

**Spec:**

Template name: "QA Evaluator"

SOUL document:
```
You are a rigorous QA reviewer. Your job is to find problems, not to be
encouraging. A pass means the work is genuinely excellent. Grade honestly.
```

EXAMPLES document: 3-5 calibrated grading examples with scores and reasoning.

RULES document:
```
- Always return structured JSON: { score: number, pass: boolean, feedback: string }
- Score 1-10, pass threshold is 7
- Be specific in feedback — say what's wrong and how to fix it
- Never say "looks good" without evidence
```

Add to PersonaTemplateSeeder alongside existing templates.

**Depends on:** TASK-133 (persona templates, ✅)

---

### GAP-006: TASK-196 — Verify and complete workflow cost dashboard

**Problem:** Routes and controller methods exist for workflow cost summary,
but the frontend page may not render correctly or aggregate step costs.

**Scope:** Verify existing + fix if needed

**Spec:**

Dashboard route: `GET /dashboard/workflows/{workflow}/cost`
Should show:
- Total cost per workflow run
- Per-step cost breakdown (table: step name, tokens in/out, cost, duration)
- Historical cost chart (runs over time)
- Average cost per run

Data source: `llm_usage` table joined with `tasks` via `workflow_run_id` + `workflow_step_key`

**Depends on:** TASK-195 (LLM cost tracking, ✅), TASK-184 (run viewer, ✅)

---

## Priority 3 — Polish & Discoverability

### GAP-007: Stream delivery monitoring UI

**Problem:** Stream delivery API exists (`POST /tasks/{task}/stream-chunk`,
`GET /tasks/{task}/stream-chunks`) but there's no dashboard view to monitor
streaming tasks.

**Scope:** Task detail page enhancement

**Spec:**

In the task detail view, when a task has `delivery_mode = 'stream'`:
- Show a "Stream Chunks" section
- List chunks in order (index, size, created_at)
- Show stream status (in-progress, finalized)
- Allow downloading the full assembled result

**Depends on:** TASK-142 (stream delivery, ✅)

---

### GAP-008: Service catalog real-time health

**Problem:** Service catalog page exists but may lack real-time health
indicators for service workers (online/offline, error rate, response time).

**Scope:** Service catalog page enhancement

**Spec:**

Enhance `ServiceCatalog.jsx`:
- Show per-worker online status (green/red dot based on last heartbeat)
- Show requests/minute and error rate (from recent task history)
- Auto-refresh every 30s or use WebSocket for live updates
- Show "No workers online" warning when a registered capability has zero active agents

**Depends on:** TASK-102 (service catalog API, ✅), TASK-143 (dashboard, ✅)

---

### GAP-009: Navigation link to workflow cost dashboard

**Problem:** Workflow cost dashboard is only accessible from the workflow detail
view. Not discoverable from the sidebar or workflow list.

**Scope:** UI only

**Spec:**

- Add a cost icon button (DollarSign) to each workflow row in the workflow list page
- Links to `/dashboard/workflows/{id}/cost`
- Same pattern as the existing History (clock) and Edit (pencil) buttons

---

### GAP-010: TASKS.md status sync

**Problem:** Several tasks are ✅ in the codebase but ⬜ in TASKS.md, or have
incorrect PR links.

**Scope:** TASKS.md update

**Spec:**

Cross-reference `git log` with TASKS.md and update:
- Any task with merged code → ✅ with PR link
- Any task marked ✅ without a PR link → add link
- Remove stale entries from "Standalone Improvements" that duplicate numbered tasks

---

## Summary

| # | Gap | Priority | Effort |
|---|-----|----------|--------|
| GAP-001 | SDK methods for workflows, templates, experiments | P1 | 2-3 days |
| GAP-002 | Marketplace agent API endpoints | P1 | 1 day |
| GAP-003 | Knowledge references CRUD + builder UI (TASK-192) | P2 | 1-2 days |
| GAP-004 | Built-in workflow templates (TASK-193) | P2 | 1 day |
| GAP-005 | QA evaluator persona template (TASK-194) | P2 | 0.5 day |
| GAP-006 | Verify workflow cost dashboard (TASK-196) | P2 | 0.5-1 day |
| GAP-007 | Stream delivery monitoring UI | P3 | 1 day |
| GAP-008 | Service catalog real-time health | P3 | 1 day |
| GAP-009 | Nav link to workflow cost | P3 | 0.5 hour |
| GAP-010 | TASKS.md status sync | P3 | 0.5 hour |
