# TASK-044: Policy Engine Service

**Phase:** 2 — Service Proxy & Security
**Status:** in progress
**Depends On:** TASK-043 (Action policies migration + model)
**Branch:** `task/044-policy-engine-service`

---

## Objective

Create a `PolicyEngine` service that evaluates action policy rules against an agent's proxy request. This is the core enforcement mechanism for the per-agent per-service firewall described in PRODUCT.md §6.8.

## Requirements

### Service: `App\Services\PolicyEngine`

A stateless service (resolved from the container) that evaluates an action policy's rules against an HTTP method and path.

**Primary method:**

```php
public function evaluate(Agent $agent, ServiceConnection $service, string $method, string $path): PolicyResult
```

**Return value:** `PolicyResult` — a simple value object with:
- `action` — one of `'deny'`, `'require_approval'`, `'allow'`
- `policyId` — the ID of the matched policy (or `null` if no policy exists)
- `matchedRule` — the specific rule that matched (array with `method`+`path`, or `null`)

### Evaluation Logic

Priority order (per PRODUCT.md §20.5):
1. **No policy exists** → default deny
2. **Policy is inactive** → default deny
3. **Deny rules** — if any deny rule matches, result is `deny`
4. **Require approval rules** — if any require_approval rule matches, result is `require_approval`
5. **Allow rules** — if any allow rule matches, result is `allow`
6. **No rule matched** → default deny

### Rule Matching

Each rule has `method` and `path`:
- **Method matching:** case-insensitive exact match, or `*` matches any method
- **Path matching:** glob-style patterns with `*` matching any single path segment and `**` matching any number of segments
  - `/repos/*/pulls` matches `/repos/myorg/pulls`
  - `/repos/*` matches `/repos/myorg`
  - `*` matches everything

### Value Object: `App\Services\PolicyResult`

Simple immutable data class:
```php
class PolicyResult {
    public function __construct(
        public readonly string $action,
        public readonly ?string $policyId = null,
        public readonly ?array $matchedRule = null,
    ) {}

    public function isAllowed(): bool
    public function isDenied(): bool
    public function requiresApproval(): bool
}
```

### Cache Strategy

- Cache the policy lookup per agent+service pair
- TTL: 300s (same as PolicyService)
- Cache key: `{prefix}:action_policy:{agent_id}:{service_id}`
- Flush on policy update/delete (via `flushCache` method)

### Activity Logging

Log every evaluation via ActivityLogger:
- Action: `policy.evaluated`
- Details: agent_id, service_id, method, path, result action, policy_id, matched_rule

## Test Plan

### Unit Tests: PolicyEngine

1. No policy for agent+service → default deny
2. Inactive policy → default deny
3. Deny rule matches → deny
4. Require approval rule matches → require_approval
5. Allow rule matches → allow
6. Deny takes precedence over allow (same request matches both)
7. Deny takes precedence over require_approval
8. Require approval takes precedence over allow
9. No rules match → default deny
10. Method matching: case-insensitive
11. Method matching: wildcard `*` matches any method
12. Path matching: exact match
13. Path matching: single `*` wildcard
14. Path matching: glob pattern in middle of path
15. Path matching: `*` (everything) matches any path
16. Cache hit returns same result without DB query
17. flushCache clears cached policy
18. Activity logging is triggered on evaluation

### Unit Tests: PolicyResult

1. isAllowed() returns true only for 'allow'
2. isDenied() returns true only for 'deny'
3. requiresApproval() returns true only for 'require_approval'
4. Constructor sets all properties correctly

## Design Decisions

- Stateless service resolved from Laravel container
- Returns a value object rather than bool — callers need the action type for approval flow
- Caching at the policy-lookup level (not per-request) — the rule evaluation itself is fast
- Activity logging on every evaluation for full audit trail
- Path matching uses glob-style patterns to match PRODUCT.md spec
- No dependency on HTTP Request object — takes raw method+path strings for testability and reuse

## Related

- **Upstream:** TASK-043 (ActionPolicy model)
- **Downstream:** TASK-045 (Approval requests use require_approval result), TASK-042 (ServiceProxy integration), TASK-050 (Dashboard policy editor)
- **Spec reference:** PRODUCT.md §6.8, §20.5
