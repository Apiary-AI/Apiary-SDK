# TASK-129 — Dashboard: Persona Editor Page

## Status: Done
## Edition: shared
## Depends On: 124 (Persona management API), 022 (Inertia/React), 024 (Agents dashboard)

---

## Problem

Agents' personas can be managed via API (Task 124), but there is no dashboard UI for
viewing or editing them. Operators must use raw HTTP calls to create/update personas.

---

## Solution

Add a dedicated **Persona Editor** page in the dashboard, reachable from the Agent Show
page via an "Edit Persona" button. The page exposes:

- Per-document tabs (SOUL, AGENT, MEMORY, RULES, STYLE, EXAMPLES, CONFIG)
- Full-page textarea editor for the selected document
- JSON editor for the CONFIG tab
- "Save New Version" button with an optional version message
- Version history table with one-click rollback

---

## Requirements

### Page URL

```
GET /dashboard/agents/{agent}/persona
```

The existing endpoint returns JSON for `Accept: application/json` requests (unchanged).
For `X-Inertia` requests (browser navigation), it renders the `Agents/Persona` component.

### Editor

- Shows all six document tabs + a CONFIG tab in a left sidebar
- Locked documents (🔒) show as read-only
- Editing any tab marks changes as pending; the Save button persists them via
  `PUT /dashboard/agents/{agent}/persona` with all current documents + config
- If no persona exists yet, the same Save button creates the first version
- Version message input is optional

### Version History

- Accordion card below the editor lists all versions (newest first)
- Each row: version number, active badge, message, author type, change count, age
- Non-active versions have a "Rollback" button that calls
  `POST /dashboard/agents/{agent}/persona/rollback`
- After save or rollback, the version list and editor state refresh in-place

### Agent Show page

- Add an "Edit Persona" button linking to `/dashboard/agents/{agent}/persona`

---

## Files Changed

| File | Change |
|------|--------|
| `docs/tasks/TASK-129-dashboard-persona-editor.md` | New task file |
| `app/Http/Controllers/Dashboard/PersonaDashboardController.php` | `show()` returns Inertia page for X-Inertia requests |
| `resources/js/Pages/Agents/Persona.jsx` | New persona editor page |
| `resources/js/Pages/Agents/Show.jsx` | Add "Edit Persona" button |
| `tests/Feature/Dashboard/PersonaEditorPageTest.php` | New Inertia page tests |

---

## Test Plan

- `PersonaEditorPageTest` — Inertia page rendering, props, auth guard, no-persona state
- Existing `PersonaDashboardTest` — JSON API still passing (no regression)
- Existing `PersonaVersioningDashboardTest` — Versioning JSON API still passing
