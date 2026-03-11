# TASK-056: Webhook Field Filters

## Status
In Progress

## Depends On
- TASK-055 (Webhook routes migration + model) — done (PR #69)

## Downstream
- TASK-057 (Webhook receiver controller) — depends on 055, 056
- TASK-058 (Webhook route evaluator + async processing) — depends on 057, 008
- TASK-060 (Dashboard: route builder) — depends on 055, 056

## Requirements

1. **FieldFilterEvaluator service** — Evaluate a webhook route's `field_filters` JSONB array against a parsed webhook payload. Returns `true` (all filters pass) or `false` (any filter fails). Empty filters = match all.

2. **FilterResult DTO** — Immutable value object capturing the evaluation outcome: matched (bool), list of individual filter results with field/operator/expected/actual values.

3. **Supported operators:**
   - `eq` — exact equality
   - `neq` — not equal
   - `contains` — substring match (strings) or element containment (arrays)
   - `not_contains` — negation of contains
   - `starts_with` — string prefix match
   - `ends_with` — string suffix match
   - `regex` — PCRE pattern match
   - `in` — value is in a list
   - `not_in` — value is not in a list
   - `exists` — field is present (non-null)
   - `not_exists` — field is absent or null
   - `gt`, `lt`, `gte`, `lte` — numeric/string comparisons

4. **Dot-notation field paths** — Support nested field access (e.g., `repository.full_name`, `pull_request.head.ref`). Missing intermediate keys = field not found.

5. **Wildcard array paths** — Support `*` to iterate array elements (e.g., `commits.*.author.email`). Match if ANY element matches.

6. **Fail-closed semantics** — Invalid operator, malformed filter, or evaluation error → filter does NOT match (fail-closed). Never throw exceptions during evaluation.

7. **WebhookRoute integration** — Add `matchesPayload(array $payload): bool` convenience method on the model that delegates to the service.

8. **Validation** — Add a reusable validation rule class (`FieldFilterRule`) that validates the filter structure: array of objects, each with `field` (string), `operator` (from supported list), and `value` (type depends on operator).

9. **Constants** — Add `OPERATORS` constant to the service listing all supported operators.

## Filter Structure

```json
[
  {"field": "ref", "operator": "eq", "value": "refs/heads/main"},
  {"field": "repository.full_name", "operator": "eq", "value": "myorg/backend"},
  {"field": "commits.*.author.email", "operator": "contains", "value": "@myorg.com"},
  {"field": "action", "operator": "in", "value": ["opened", "reopened"]},
  {"field": "draft", "operator": "exists", "value": null}
]
```

All filters are AND-joined: every filter must pass for the route to match.

## Test Plan

### Unit Tests (FieldFilterEvaluatorTest)
- Empty filters → always matches
- Single `eq` filter on top-level field → match and no-match
- Single `neq` filter → match and no-match
- `contains` on string field → match and no-match
- `not_contains` → match and no-match
- `starts_with` and `ends_with` → match and no-match
- `regex` with valid pattern → match and no-match
- `regex` with invalid pattern → fail-closed (no match)
- `in` / `not_in` with array values
- `exists` / `not_exists` for present and absent fields
- `gt`, `lt`, `gte`, `lte` numeric and string comparisons
- Dot-notation nested field access → match and no-match
- Deeply nested paths (3+ levels)
- Missing intermediate key → field not found → appropriate behavior per operator
- Wildcard `*` array paths → match if any element matches
- Multiple filters (AND logic) → all must pass
- Multiple filters with one failing → no match
- Invalid operator → fail-closed
- Malformed filter (missing field/operator) → fail-closed
- Non-string field path → fail-closed
- Filter with null value for non-exists operators → appropriate handling

### Integration (WebhookRoute model)
- `matchesPayload()` with matching filters → true
- `matchesPayload()` with non-matching filters → false
- `matchesPayload()` with empty filters → true

### Validation (FieldFilterRule)
- Valid filter array → passes
- Empty array → passes
- Missing `field` key → fails
- Missing `operator` key → fails
- Invalid operator → fails
- Non-array filter → fails
- `in`/`not_in` with non-array value → fails
- `exists`/`not_exists` ignores value → passes
