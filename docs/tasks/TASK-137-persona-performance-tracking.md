# TASK-137: Persona Performance Tracking Per Version

## Status
✅ Done

## Branch
`task/137-persona-performance-tracking`

## PR
_See PR opened from this branch_

## Depends On
- TASK-122 ✅ (agent persona model)
- TASK-018 ✅ (task progress, completion & failure)

## Edition Scope
Both CE and Cloud (core feature)

## Objective
Track and display task performance metrics per persona version so operators
can compare how different persona snapshots affect agent effectiveness.

## Architecture

### Data Model
The `agent_personas` table already has pre-allocated performance columns
(added in the TASK-122 migration with a "populated later by task 137" comment):
- `tasks_completed` — count of completed tasks
- `avg_task_duration` — mean duration in seconds (from initially_claimed_at to completed_at)
- `error_rate` — failed / (completed + failed), null when no tasks
- `avg_rating` — reserved for future agent-reported quality scores

A new column `persona_version_id` (string ULID, nullable) is added to the
`tasks` table. It is written atomically during the claim operation, recording
which persona snapshot the agent was running at execution time.

### Attribution Flow
1. **Claim** — `TaskController::claim()` resolves `PersonaService::getAssignedPersona($agent)`
   and writes the persona's id into `tasks.persona_version_id`.
2. **Complete/Fail** — `TaskController::complete()` / `fail()` schedule a
   `PersonaPerformanceService::recompute()` call via `DB::afterCommit()`.
3. **Recompute** — `PersonaPerformanceService::recompute($personaId)` runs a
   single SQL aggregate over `tasks WHERE persona_version_id = $personaId` and
   updates the four metric columns on the persona row.

### Dashboard API
`GET /dashboard/agents/{agent}/persona/performance`

Returns an array of per-version performance summaries ordered by version
descending. Each entry: `id`, `version`, `is_active`, `tasks_completed`,
`avg_task_duration`, `avg_rating`, `error_rate`, `created_at`.

## Files Changed

### New
- `database/migrations/2026_03_20_100000_add_persona_version_id_to_tasks_table.php`
- `app/Services/PersonaPerformanceService.php`
- `tests/Feature/PersonaPerformanceTrackingTest.php`
- `docs/tasks/TASK-137-persona-performance-tracking.md`

### Modified
- `app/Models/Task.php` — added `persona_version_id` to `$fillable`
- `app/Http/Controllers/Api/TaskController.php` — inject services, write `persona_version_id` on claim, trigger recompute on complete/fail
- `app/Http/Controllers/Dashboard/PersonaDashboardController.php` — inject `PersonaPerformanceService`, add `performance()` endpoint
- `routes/web.php` — register `GET /dashboard/agents/{agent}/persona/performance`
- `TASKS.md` — mark TASK-134 ✅, TASK-137 ✅

## Acceptance Criteria
- [x] Migration adds `persona_version_id` to tasks
- [x] Claim writes correct persona_version_id (null when agent has no persona)
- [x] Complete triggers recompute; tasks_completed increments
- [x] Fail triggers recompute; error_rate updates
- [x] avg_task_duration computed from initially_claimed_at (fallback: claimed_at)
- [x] Recompute is idempotent
- [x] Dashboard endpoint returns all versions ordered by version desc
- [x] Dashboard endpoint returns 404 for unknown agent
- [x] Dashboard endpoint requires auth
- [x] Tests pass: `php artisan test --filter=PersonaPerformanceTrackingTest`
