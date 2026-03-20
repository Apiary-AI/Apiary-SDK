# TASK-136: Token Counter + Cost Estimate

## Status
⬜ In Progress

## Branch
`task/136-token-counter-cost-estimate`

## Depends On
- TASK-126 ✅ (Persona SDK API)
- TASK-129 ✅ (Dashboard: persona editor page)

## Edition Scope
Both CE and Cloud (core feature)

## Objective
Show a live token count breakdown and cost estimate in the persona editor so
operators can understand and optimise persona size vs. LLM cost.

## Deliverables

### Backend (PHP)
1. `App\Services\PersonaTokenService` — token counting + cost estimation service.
   - `estimateTokens(string): int` — 1 token ≈ 4 chars approximation.
   - `countDocumentTokens(array): array` — per-document counts + `total`.
   - `countPersonaTokens(AgentPersona): array` — convenience wrapper.
   - `estimateCost(int, ...): array` — cost for given token count (Claude Sonnet pricing).
   - `summarize(AgentPersona, int): array` — full summary (document_tokens, total_tokens, cost).
2. `GET /dashboard/agents/{agent}/persona/tokens` — new endpoint returning token counts
   and cost estimates for the agent's active persona.
   - Optional `?monthly_tasks=N` (1–100000) overrides default 500-tasks projection.
   - Returns 404 when agent has no active persona.
   - Returns 404 for unknown agent.

### Frontend (React)
3. `TokenCounterPanel` component — live token count breakdown and cost estimate panel.
   - Shows per-document token counts for all 7 document types (SOUL, AGENT, MEMORY, RULES, STYLE, EXAMPLES, NOTES).
   - Proportional bar visualisation per document.
   - Total token count.
   - Cost per task and monthly cost estimate (Claude Sonnet, 500 tasks/month default).
   - Updates in real-time as the user types (uses character approximation, no network request).
4. Integrated into `Persona.jsx` between the editor card and version history.

### Tests
5. PHP feature tests in `PersonaTokenCounterTest` (20 tests covering tokens endpoint,
   validation, service unit tests, formula verification, active-persona selection).
6. JavaScript unit tests in `Persona.token-counter.test.jsx` (12 tests covering panel
   rendering, token calculation, cost formula, edge cases).

## Cost Model
- Model: Claude Sonnet (`claude-sonnet-4-5`)
- Input price: $3.00 per 1M tokens
- Output price: $15.00 per 1M tokens
- Output multiplier: 2× input tokens (assumed average output length)
- Default monthly volume: 500 tasks

## Token Counting Approach
Character-based approximation: `ceil(char_count / 4) = token_count`.
Industry-standard rule-of-thumb for English text with major LLM tokenisers.
Intentionally avoids a heavy tokeniser library dependency.

## Acceptance Criteria
- [x] `GET /dashboard/agents/{agent}/persona/tokens` returns document_tokens, total_tokens, cost
- [x] Per-document token counts match character-based approximation
- [x] Total equals sum of document token counts
- [x] Cost formula: input + output costs at Claude Sonnet pricing
- [x] `?monthly_tasks=N` overrides default 500
- [x] Monthly cost scales linearly with monthly_tasks
- [x] Returns 404 when no active persona
- [x] Returns 404 for unknown agent
- [x] Validates monthly_tasks (integer, 1–100000)
- [x] Uses active persona (not older versions)
- [x] TokenCounterPanel renders in Persona editor
- [x] Live update as user types (character-based approximation)
- [x] Per-document breakdown with proportional bars
- [x] Total token count displayed
- [x] Cost per task and monthly cost displayed
- [x] All tests pass
