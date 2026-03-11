# TASK-117: Connect Agent UX Slice

**Phase:** 1 — Core MVP (Dashboard)
**Status:** pending
**Depends On:** TASK-014 (Agent registration API), TASK-022 (Inertia + React), TASK-024 (Agents dashboard), TASK-116 (Dashboard auth)
**Branch:** `task/117-connect-agent-ux-slice`

---

## Objective

Build the end-to-end dashboard UX flow for connecting (bootstrapping) a new agent to the platform. This is the primary onboarding path for agent operators: from the dashboard they should be able to generate a bootstrap token, see connection instructions, and verify the agent is online.

## Requirements

### 1. Agent Bootstrap / Connect Flow

- Add a "Connect Agent" button/action on the Agents dashboard page
- Modal or dedicated page with:
  - Form to name the agent and select capabilities
  - Generate a one-time bootstrap token (calls existing Agent Registration API)
  - Display the token prominently with copy-to-clipboard
  - Show SDK-specific connection snippets (Python, Shell) pre-filled with the token and endpoint URL

### 2. Token / Bootstrap Visibility

- After token generation, show it exactly **once** (cannot be retrieved later)
- Clear warning: "Save this token — it won't be shown again"
- Copy-to-clipboard button with visual confirmation
- Display the API base URL alongside the token for easy agent configuration

### 3. Live Connection / Status Indicator

- On the Agents list and Agent detail views:
  - Real-time status badge: `online` (green), `idle` (yellow), `offline` (grey)
  - Last heartbeat timestamp with relative time ("2 minutes ago")
  - Auto-refresh via existing Reverb WebSocket channel (`hive.{id}.activity`)
- After token generation, show a "Waiting for connection..." state that auto-updates when the agent's first heartbeat arrives

### 4. Minimal Test Action Trigger

- On the Agent detail view, add a "Send Test Task" button
- Creates a simple `ping` task targeted at the agent
- Shows real-time status of the test task (pending → claimed → completed)
- Confirms the agent is not only connected but actively processing

## Scope Boundaries

- This task covers **dashboard UI only** — no new API endpoints (uses existing registration, heartbeat, and task APIs)
- No changes to agent authentication flow (Sanctum tokens from TASK-012)
- No changes to WebSocket infrastructure (uses existing Reverb from TASK-028)
- The bootstrap token is the same Sanctum token returned by the registration API

## UI/UX Notes

- Follow existing shadcn/ui component patterns from the redesign (PR #55)
- Use the existing AppLayout and page structure from TASK-022/024
- Status indicators should match the color scheme used in the Agents dashboard

## Test Plan

1. Connect flow renders and generates a token via API call
2. Token is displayed and can be copied
3. Connection snippets include correct endpoint and token
4. Status badge updates on heartbeat WebSocket event
5. "Waiting for connection" state transitions to "online" on first heartbeat
6. Test task creation and status tracking through completion
7. Token is not shown on subsequent page loads

## Design Decisions

- Reuses existing API endpoints — zero backend work
- Token display follows industry patterns (GitHub PAT, Stripe keys)
- WebSocket-driven status avoids polling from the dashboard
- Test task uses a `ping` type that any agent can handle as a capability check

## Related

- **Upstream:** TASK-014 (Agent registration API), TASK-022 (Inertia + React), TASK-024 (Agents dashboard), TASK-116 (Dashboard auth)
- **Downstream:** Marketplace agent templates, onboarding wizard (Cloud)
- **Spec reference:** PRODUCT.md §10.1 (Agent Lifecycle), §14.2 (Per-Hive Views)
