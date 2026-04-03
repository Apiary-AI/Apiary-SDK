# TASK-134 — Dashboard: Template Selector

## Status: Done
## Edition: shared
## Depends On: 133 (Persona templates), 129 (Dashboard persona editor page)

---

## Problem

The `TemplatePickerPanel` shipped in TASK-133 only appeared for agents with no
persona and offered no way to preview template content before committing.
Operators had no way to apply a template to an existing agent (to reset or
re-baseline a persona) and could not inspect document content before choosing.

---

## Solution

### Backend (TASK-134)

Add a new **replace** endpoint:

```
POST /dashboard/agents/{agent}/persona/from-template/replace
```

Unlike the existing `from-template` (apply) endpoint — which fails with 409 when
a persona already exists — `replace` calls `PersonaService::createPersona()`
directly, creating a new persona version from the template while preserving the
previous version in history.  An optional `message` field lets the operator
provide a custom commit message.

Fails with 409 (`persona_not_found`) when the agent has no active persona (use
`from-template` to bootstrap instead).

### Frontend (TASK-134)

**`TemplatePickerPanel` enhancements:**

1. **`hasPersona` prop** — controls which endpoint to call on apply (`from-template`
   vs `from-template/replace`) and adjusts UI copy accordingly.

2. **`TemplatePreviewPane` component** — dedicated preview panel rendered beside
   the card list when an operator clicks "Preview" on a template card.  Fetches
   the full template from `GET /dashboard/persona-templates/{id}` and displays
   document content in a tabbed viewer (one tab per document).  An "Use This
   Template" button in the preview footer triggers apply directly from the preview.

3. **Two-column layout** — when a preview is open the template card list narrows
   and sits beside the preview pane (responsive: stacks vertically on small screens).

4. **"Browse Templates" header button** — added to the Persona Editor header for
   agents that already have an active persona.  Toggles `templateBrowserOpen` state,
   which renders `TemplatePickerPanel` with `hasPersona={true}` above the editor.
   For fresh agents the original inline panel behaviour is unchanged.

---

## API Endpoints (new in TASK-134)

| Method | URL | Description |
|--------|-----|-------------|
| `POST` | `/dashboard/agents/{agent}/persona/from-template/replace` | Apply template as new version for existing persona |

---

## Files Changed

| File | Change |
|------|--------|
| `docs/tasks/TASK-134-dashboard-template-selector.md` | New task file |
| `app/Http/Controllers/Dashboard/PersonaTemplateDashboardController.php` | Add `replace()` method |
| `routes/web.php` | Add `from-template/replace` route |
| `resources/js/Pages/Agents/Persona.jsx` | Add `TemplatePreviewPane`, enhance `TemplatePickerPanel`, add header "Browse Templates" button |
| `tests/Feature/Dashboard/TemplateSelectorTest.php` | Feature tests for TASK-134 |

---

## Test Plan

- `TemplateSelectorTest` — replace endpoint: creates new version, preserves history,
  409 for fresh agent, 422 for unknown template, 404 for unknown agent, auth guard
- Custom message field accepted; default message includes template name
- All built-in templates work with replace
- apply (TASK-133) still returns 409 when persona exists
- Sequential apply → replace increments version correctly
