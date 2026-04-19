# TASK-231: Hosted agent env injection

**Status:** pending
**Branch:** `task/231-hosted-agent-env-injection`
**PR:** —
**Depends on:** TASK-227, TASK-253
**Blocks:** TASK-230, TASK-233
**Edition:** cloud
**Feature doc:** [FEATURE_HOSTED_AGENTS.md](../features/list-1/FEATURE_HOSTED_AGENTS.md) §4.3, §6

## Objective

Produce the final, fully-resolved env var list that gets sent to novps at
deploy time. The list combines Apiary-injected runtime envs, the preset's
model selection, and the user's `user_env` — validated against the preset
schema and never persisted to novps outside of this single deploy call.

## Requirements

### Functional

- [ ] FR-1: `App\Cloud\Services\HostedAgentEnvResolver::resolve(HostedAgent $agent): array`
  returns an ordered list of `[['key'=>..,'value'=>..]]` matching novps's
  `ResourceEnvsType`.
- [ ] FR-2: Auto-injected envs (always present, cannot be overridden):
    - `APIARY_BASE_URL` → internal cluster URL
      (`config('apiary.hosted_agents.apiary_base_url')` with fallback to
      `config('app.url')`)
    - `APIARY_TOKEN` → freshly-issued token via
      `AgentTokenService::issueFor($agent->agent)`
    - `APIARY_HIVE_ID` → `$agent->hive_id`
    - `APIARY_AGENT_ID` → `$agent->agent_id`
    - `APIARY_AGENT_NAME` → `$agent->agent->name`
- [ ] FR-3: Preset-derived env: writes `preset.model_env_key` with the
  user-selected model (e.g. `CLAUDE_MODEL=claude-sonnet-4-5`).
- [ ] FR-4: User envs: decrypt `hosted_agents.user_env`, validate each key
  is declared in the preset's `user_env` schema, emit as-is.
- [ ] FR-5: Rejects unknown user env keys — raises
  `InvalidHostedAgentEnvException`. Should never happen post-validation
  at create time, but double-check defends against schema drift.
- [ ] FR-6: Deterministic merge order (last write wins, matching
  FEATURE_HOSTED_AGENTS.md §4.3):
    1. Preset-defined non-secret **defaults** (from `user_env` schema
       defaults, alphabetical).
    2. Preset model env (e.g. `CLAUDE_MODEL=...`).
    3. **User-supplied `user_env`** (alphabetical).
    4. **Auto-injected `APIARY_*` envs last** (alphabetical) — they win
       unconditionally over anything earlier and cannot be overridden.
  The reserved-prefix validation at create time (FEATURE §4.3) means
  layers 1-3 cannot legally contain `APIARY_*` keys; the final-write
  ordering here is a defence-in-depth backstop.
- [ ] FR-7: Token rotation contract — every call to `resolve()` issues a
  **new** `APIARY_TOKEN` and revokes the previous one once the deploy
  succeeds. Revocation happens in the deploy job on `success`, not here.
- [ ] FR-8: Returns an immutable value object; resolver never mutates the
  `HostedAgent` model.

### Non-Functional

- [ ] NFR-1: Plaintext envs exist only in memory during the deploy job.
  Never logged, never stored outside the encrypted `user_env` column.
- [ ] NFR-2: `AgentTokenService` is the single place tokens are minted.
  If it doesn't yet support a `issueFor(Agent)` variant, this task adds
  one — existing agent-token code paths stay untouched.

## Architecture & Design

### Files to Create / Modify

| Action | Path | Purpose |
|--------|------|---------|
| Create | `app/Cloud/Services/HostedAgentEnvResolver.php` | Compose final env list |
| Create | `app/Cloud/Services/HostedAgentEnvPayload.php` | Immutable VO |
| Create | `app/Cloud/Exceptions/InvalidHostedAgentEnvException.php` | Typed error |
| Modify | `app/Services/AgentTokenService.php` (or equivalent) | `issueFor(Agent)` method if missing |

### Key Design Decisions

- **Resolver does not persist a rotated token.** Agent tokens are recorded
  by `AgentTokenService`. Resolver just asks for a new one per invocation
  and returns it inside the VO. Deploy job decides whether to revoke the
  prior token (on success) or leave it (on failure retry).
- **Envs are a list, not a map.** Novps's `ResourceEnvsType` is a list of
  `{key, value}` and preserves order — we keep that shape all the way
  through so it's a straight pass-through to the HTTP payload.

## Test Plan

### Unit Tests

- [ ] Always emits the five `APIARY_*` envs.
- [ ] Model env is written with the preset's `model_env_key`.
- [ ] Unknown user env key triggers `InvalidHostedAgentEnvException`.
- [ ] Missing required preset user env raises
  `InvalidHostedAgentEnvException`.
- [ ] Calls `AgentTokenService::issueFor` once per invocation.
- [ ] Determinism: same input → same ordering.

### Feature Tests

- [ ] Full resolve from a persisted `HostedAgent` with Claude preset.
- [ ] Token issued is active post-resolve; prior token not yet revoked.

## Validation Checklist

- [ ] All tests pass
- [ ] PSR-12 compliant
- [ ] `user_env` never logged (verified against test-log assertions)
- [ ] No credentials logged in plaintext
