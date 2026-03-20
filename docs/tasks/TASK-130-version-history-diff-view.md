# TASK-130 — Dashboard: Version History + Diff View

## Status: Done
## Edition: shared
## Depends On: 125 (Persona versioning API), 129 (Dashboard persona editor)

---

## Problem

The persona editor page (Task 129) shows a version history table with rollback support,
but operators have no way to inspect **what changed** between versions without using
the raw API. Comparing two persona snapshots requires manual API calls and eyeballing
the results.

---

## Solution

Add an inline **diff panel** to the persona editor page. Each non-active version row
in the history table gains a **Diff** button. Clicking it expands a panel beneath the
table that shows a colour-coded line-level diff between that version and the current
active version.

---

## Requirements

### Diff Button

- Rendered for every non-active version in the Version History table
- Toggles the diff panel open/closed for that version
- Active state is highlighted (primary tint background)

### Diff Panel

- Fetches three endpoints in parallel:
  - `GET /dashboard/agents/{agent}/persona/diff?from={version}&to={activeVersion}`
  - `GET /dashboard/agents/{agent}/persona/versions/{version}`
  - `GET /dashboard/agents/{agent}/persona/versions/{activeVersion}`
- Shows a loading state while fetching
- Shows an error message if any fetch fails
- Left sidebar lists all documents from the diff summary, each labelled with their
  change type (Added / Changed / Removed / Unchanged)
- Right panel shows a colour-coded line-level diff for the selected document:
  - Added lines: green background with `+` prefix
  - Removed lines: red background with `-` prefix
  - Unchanged lines: muted, collapsed in context groups (3 lines of context kept)
- Defaults to the first changed document (not `unchanged`) on open
- CONFIG document shows JSON diff
- Close button (`X`) dismisses the panel
- Clicking the same Diff button again also dismisses the panel

### Diff Algorithm

A standard LCS-based line-level diff (no external library). Performance is acceptable
for persona documents (typically < 200 lines). Context groups collapse long runs of
equal lines, keeping 3 lines of context on each side.

---

## Files Changed

| File | Change |
|------|--------|
| `docs/tasks/TASK-130-version-history-diff-view.md` | New task file |
| `resources/js/Pages/Agents/Persona.jsx` | Diff button + `VersionDiffPanel` + `DiffLines` + `DiffLine` + `lineDiff` helper |
| `resources/js/Pages/Agents/Persona.diff.test.jsx` | New: 10 tests covering diff UI behaviour |
| `resources/js/Pages/Agents/Persona.rollback.test.jsx` | Add `GitCompare` to lucide mock; fix `getRollbackButton` selector |
| `resources/js/Pages/Agents/Persona.versions.test.jsx` | Add `GitCompare` to lucide mock |
| `resources/js/Pages/Agents/Persona.save-locked.test.jsx` | Add `GitCompare` to lucide mock |

---

## Test Plan

- `Persona.diff.test.jsx` — 10 tests:
  - Diff button rendered only for non-active versions
  - Panel not shown initially
  - Loading state shown during fetch
  - Document tabs and diff content rendered after fetch
  - Content diff shows added/removed lines correctly
  - Close button dismisses panel
  - Toggle (click same button) dismisses panel
  - Error message shown on fetch failure
  - Tab switching changes displayed document
  - Correct API URLs called (diff + showVersion × 2)
- All 33 existing Persona tests continue to pass
