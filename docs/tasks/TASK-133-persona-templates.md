# TASK-133 — Persona Templates (Built-in Starter Templates)

## Status: Done
## Edition: shared
## Depends On: 123 (Persona service)

---

## Problem

Creating a persona from scratch requires operators to know what documents to write and how
to structure them.  New users have no starting point and must discover the document model
by trial and error.

---

## Solution

Ship a catalogue of **five built-in starter templates** that pre-fill persona documents and
config for common agent archetypes.  Templates are pure PHP data — no database storage —
exposed via two read endpoints and one apply endpoint.

---

## Templates Included

| ID | Name | Tags |
|----|------|------|
| `general-assistant` | General Assistant | general, starter |
| `code-review-bot` | Code Review Bot | engineering, code, github |
| `customer-support` | Customer Support Agent | support, customer-facing |
| `data-analyst` | Data Analyst | data, analytics, sql |
| `ci-cd-bot` | CI/CD Bot | devops, ci, github-actions |

Each template provides: `SOUL`, `AGENT`, `RULES`, `STYLE` documents and a default `config`.

---

## API Endpoints

| Method | URL | Description |
|--------|-----|-------------|
| `GET` | `/dashboard/persona-templates` | List all templates (summary, no document content) |
| `GET` | `/dashboard/persona-templates/{id}` | Get a single template with full document content |
| `POST` | `/dashboard/agents/{agent}/persona/from-template` | Apply template to create first persona version |

The `from-template` endpoint returns `409` when the agent already has an active persona
(prevents accidental overwrites — use `PUT /persona` for subsequent edits).

---

## UI Changes

The **Persona Editor** page gains a **Template Picker** panel that appears only when the
agent has no persona yet.  It shows a "Browse Templates" button; once clicked, a card grid
renders all templates with tags, doc list, and a "Use Template" action button.  After apply,
the editor state is refreshed in-place without a page reload.

---

## Files Changed

| File | Change |
|------|--------|
| `docs/tasks/TASK-133-persona-templates.md` | New task file |
| `app/Services/PersonaTemplateService.php` | New — built-in template definitions |
| `app/Http/Controllers/Dashboard/PersonaTemplateDashboardController.php` | New — `index`, `show`, `apply` endpoints |
| `routes/web.php` | Add three new persona-template routes |
| `resources/js/Pages/Agents/Persona.jsx` | Add `TemplatePickerPanel` component and `handleTemplateApplied` handler |
| `tests/Feature/Dashboard/PersonaTemplateTest.php` | Feature + unit tests |

---

## Test Plan

- `PersonaTemplateTest` — service unit tests, HTTP endpoint tests, auth guards, edge cases
- All built-in templates apply successfully for fresh agents
- `409` returned when persona already exists
- `404` returned for unknown template id
- Authentication required on all three endpoints
