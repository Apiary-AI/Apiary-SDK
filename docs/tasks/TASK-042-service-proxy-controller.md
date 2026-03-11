# TASK-042: Service Proxy Controller

**Status:** In Progress
**Branch:** `task/042-service-proxy-controller`
**Depends On:** 037 (Credential vault), 038 (Connector interface + base class)

---

## Requirements

Implement the service proxy controller that allows agents to make HTTP requests
to external services through the platform. The proxy injects credentials from
the credential vault so agents never see plaintext secrets.

### API Endpoints

```
ANY  /api/v1/proxy/{service}/{path}   — Forward request to external service
```

Where `{service}` is the ServiceConnection name (unique per apiary) and
`{path}` is the downstream path (including query string).

### Behaviour

1. Resolve ServiceConnection by name within the agent's apiary
2. Verify agent has `services:{connection_id}` or `services:*` permission
3. Reject if connection is inactive (404)
4. Decrypt auth_config and inject auth headers based on auth_type
5. Forward HTTP method, body, query params, and filtered headers to `base_url + path`
6. Return upstream response (status code, body, content-type) to the agent
7. Log every proxy request via ActivityLogger

### Auth Injection by Type

| auth_type | Behaviour |
|-----------|-----------|
| `token`   | `Authorization: Bearer {token}` |
| `oauth2`  | `Authorization: Bearer {access_token}` |
| `basic`   | `Authorization: Basic base64(username:password)` |
| `api_key` | Custom header from config: `{header_name}: {api_key}` |
| `none`    | No auth headers injected |

### Error Responses

| Condition | Status | Code |
|-----------|--------|------|
| Not authenticated | 401 | — |
| Service not found / inactive | 404 | not_found |
| Agent lacks permission | 403 | forbidden |
| Upstream connection failure | 502 | bad_gateway |
| Upstream timeout | 504 | gateway_timeout |

### Security

- Agent NEVER receives decrypted credentials in the response
- auth_config is never logged or exposed
- Request/response bodies are not logged (privacy; proxy_log table is TASK-047)
- Only forward safe headers (strip Authorization, Cookie, Host from agent request)

---

## Files to Create

| File | Purpose |
|------|---------|
| `app/Services/ServiceProxy.php` | HTTP forwarding with credential injection |
| `app/Http/Controllers/Api/ProxyController.php` | API controller |
| `tests/Feature/ProxyControllerTest.php` | Feature tests |

## Files to Modify

| File | Change |
|------|--------|
| `routes/api.php` | Add proxy route group |

---

## Test Plan

1. Authentication required (401 without token)
2. Service not found → 404
3. Inactive service → 404
4. Permission denied (no `services:*` or `services:{id}`) → 403
5. Successful proxy forward with token auth
6. Successful proxy forward with basic auth
7. Successful proxy forward with api_key auth
8. Successful proxy forward with none auth
9. Activity logging on proxy request
10. Cross-apiary isolation (cannot access other apiary's services)
11. Upstream error handling (502 on connection failure)
12. Path and query string forwarding
13. POST body forwarding
