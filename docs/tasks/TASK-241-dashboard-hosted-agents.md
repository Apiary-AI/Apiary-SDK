# TASK-241: Dashboard — Hosted Agents wizard + list + detail

**Status:** pending
**Branch:** `task/241-dashboard-hosted-agents`
**PR:** —
**Depends on:** TASK-228, TASK-230, TASK-231, TASK-233, TASK-236, TASK-240
**Blocks:** —
**Edition:** cloud
**Feature doc:** [FEATURE_HOSTED_AGENTS.md](../features/list-1/FEATURE_HOSTED_AGENTS.md) §11

## Objective

React/Inertia dashboard surface for Hosted Agents: deploy wizard, list view
with live status, detail page with deployments / env / logs. The dashboard
section is hidden entirely on CE and only rendered when
`apiary.hosted_agents.enabled === true`.

## Requirements

### Functional

- [ ] FR-1: Navigation entry **Agents → Hosted** under the hive sidebar
  (hidden when not enabled).
- [ ] FR-2: `Pages/Cloud/HostedAgents/Index.jsx` — table with status
  badge, preset, model, replicas, last-deployed-at, action buttons
  (stop, start, restart). Live-updates via existing Reverb agent channel
  (`HostedAgentStatusChanged` event from TASK-230).
- [ ] FR-3: `Pages/Cloud/HostedAgents/Wizard.jsx` — 4-step wizard as in
  feature doc §11.1. Uses `GET /api/v1/hosted-agent-presets` to populate
  choices. Required-env fields render from the preset schema with
  secret masking.
- [ ] FR-4: `Pages/Cloud/HostedAgents/Show.jsx` — tabs: Overview,
  Deployments, Env, Logs.
    - **Overview**: status card, current image tag, model, last deployed,
      lifecycle buttons.
    - **Deployments**: table from TASK-240 with per-row Rollback button.
    - **Env**: edit user envs; save triggers redeploy toast.
    - **Logs**: live-follow viewer bound to the SSE endpoint from
      TASK-236. Filters: pod selector + free-text search + time range.
- [ ] FR-5: Destroy is a confirm-dialog action on the Overview tab,
  routes to `DELETE` with a typed-confirm input.
- [ ] FR-6: Every action uses the existing toast + activity-log feed so
  lifecycle events land in the hive activity stream automatically.

### Non-Functional

- [ ] NFR-1: All pages live under `resources/js/Pages/Cloud/HostedAgents/`.
- [ ] NFR-2: Shared components (preset picker, env-schema form, log
  viewer) live under `resources/js/Components/HostedAgents/`.
- [ ] NFR-3: Inertia shared prop `features.hostedAgents = true/false`
  gates the nav entry — routes + Inertia pages are not registered when
  disabled so CE payloads don't ship the code path.

## Architecture & Design

### Files to Create / Modify

| Action | Path | Purpose |
|--------|------|---------|
| Create | `resources/js/Pages/Cloud/HostedAgents/Index.jsx` | List view |
| Create | `resources/js/Pages/Cloud/HostedAgents/Wizard.jsx` | 4-step deploy flow |
| Create | `resources/js/Pages/Cloud/HostedAgents/Show.jsx` | Detail with tabs |
| Create | `resources/js/Components/HostedAgents/PresetPicker.jsx` | Preset + model step |
| Create | `resources/js/Components/HostedAgents/EnvSchemaForm.jsx` | Schema-driven env inputs |
| Create | `resources/js/Components/HostedAgents/LogViewer.jsx` | SSE follow |
| Create | `resources/js/Components/HostedAgents/DeploymentsTable.jsx` | History + rollback |
| Create | `app/Cloud/Http/Controllers/Dashboard/HostedAgentDashboardController.php` | Inertia controller |
| Modify | `app/Http/Middleware/HandleInertiaRequests.php` | Shared `features.hostedAgents` flag |
| Modify | `resources/js/Layouts/AppLayout.jsx` | Conditional nav entry |
| Modify | `routes/web.php` | Register dashboard routes behind middleware |

### Key Design Decisions

- **Wizard is client-only until submit.** Preset selection doesn't hit
  the API between steps — the catalogue is prefetched once on mount. One
  `POST` at the end creates everything.
- **No custom log viewer library.** Built on a small component — novps
  log entries are flat `{timestamp, line}`, no colour codes or structured
  fields worth investing in a terminal emulator for.
- **Rollback confirmation is a dedicated dialog**, not a toast — user
  should see image tag diff before confirming.

## Test Plan

### Unit Tests (Vitest / React Testing Library)

- [ ] PresetPicker renders only configured presets.
- [ ] EnvSchemaForm marks secret fields with password type + show/hide.
- [ ] Wizard blocks "Deploy" until all required envs are filled.
- [ ] LogViewer reconnects SSE on close.

### Feature Tests (PHPUnit / Inertia)

- [ ] Dashboard routes 404 when hosted_agents.enabled = false.
- [ ] Nav prop `features.hostedAgents` reflects config.
- [ ] Index page renders live status updates from Reverb broadcast.
- [ ] Create → wizard submit → redirect to detail page.
- [ ] Cross-hive access blocked.

## Validation Checklist

- [ ] All tests pass
- [ ] PSR-12 + ESLint clean
- [ ] Activity logging hook from lifecycle actions surfaces in UI
- [ ] Dashboard hidden on CE
- [ ] Used against a local dev novps project end-to-end
