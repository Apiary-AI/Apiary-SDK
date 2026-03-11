# TASK-052: Event Subscriptions Migration + Model

**Status:** In Progress
**Branch:** `task/052-event-subscriptions-migration-model`
**Depends On:** 051 (Events migration + model), 007 (Agent model)

## Requirements

Create the `event_subscriptions` table migration and `EventSubscription` Eloquent model for agent event subscriptions as described in PRODUCT.md §9.2.

### Schema (from PRODUCT.md)

```sql
CREATE TABLE event_subscriptions (
    agent_id        VARCHAR(26) REFERENCES agents(id) ON DELETE CASCADE,
    event_type      VARCHAR(100) NOT NULL,
    scope           VARCHAR(20) DEFAULT 'hive',  -- 'hive' or 'apiary'
    created_at      TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (agent_id, event_type)
);
```

### Model Requirements

- Composite primary key (`agent_id`, `event_type`) — same pattern as `AgentPermission`
- No ULID (composite PK, no surrogate key)
- No `updated_at` — subscriptions are created or deleted, not modified
- Constants: `SCOPE_HIVE`, `SCOPE_APIARY`, `VALID_SCOPES`
- Relationships: `agent()` → BelongsTo Agent
- Inverse: `Agent::eventSubscriptions()` → HasMany
- Scope helpers: `isHiveScope()`, `isApiaryScope()`
- Query scopes: `hiveScope`, `apiaryScope`, `forType`
- Factory with `forAgent`, `hiveScope`, `apiaryScope`, `forType` states

### Key Design Decisions

- Follows `AgentPermission` pattern: composite PK, no ULID, scoped through agent
- No `BelongsToHive`/`BelongsToApiary` traits — scoping is implicit through the agent (agent → hive → apiary)
- `scope` column controls event filtering: `'hive'` = hive-local events, `'apiary'` = cross-hive events
- `created_at` added for audit consistency (matches agent_permissions convention)
- CASCADE on agent delete — subscriptions are meaningless without their agent

## Test Plan

- Composite PK enforced (agent_id + event_type)
- Fillable fields persist correctly
- Default values (scope='hive')
- Unique constraint: duplicate (agent_id, event_type) rejected
- Relationships: agent(), Agent::eventSubscriptions()
- Scope helpers: isHiveScope(), isApiaryScope()
- Query scopes: hiveScope, apiaryScope, forType
- CASCADE: deleting agent cascades subscriptions
- Factory states: forAgent, hiveScope, apiaryScope, forType
- Same agent can subscribe to multiple event types
- Multiple agents can subscribe to the same event type

## Validation Checklist

- [ ] Migration creates event_subscriptions table with correct schema
- [ ] Composite PK (agent_id, event_type)
- [ ] FK agent_id → agents(id) CASCADE
- [ ] Model follows AgentPermission composite PK pattern
- [ ] Agent model gains eventSubscriptions() relationship
- [ ] Factory supports all subscription states
- [ ] All tests pass
- [ ] PSR-12 compliant (Pint)
