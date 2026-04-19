# Runbook: novps.io GHCR Registry Credential Setup

> **Audience:** Cloud ops engineer
> **When:** One-time setup per novps project, plus periodic rotation (recommended every 90 days)
> **Prerequisite:** Admin access to the GitHub `apiary-ai` organisation and to the novps.io project used by Apiary Cloud

---

## 1. Provision a GitHub Token

Create a **classic personal access token** with `read:packages` scope. GHCR does not support fine-grained PATs for authentication — classic PATs are required.

### Steps

1. Go to **GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token (classic)**.

2. Configure the token:
   - **Token name:** `novps-ghcr-pull-<environment>` (e.g. `novps-ghcr-pull-production`)
   - **Expiration:** 90 days (custom expiration; see [Rotation](#5-credential-rotation) below)
   - **Scopes:** select **`read:packages`** (this grants pull access to `ghcr.io/apiary-ai/*`)

3. Click **Generate token** and copy the value immediately — it is shown only once.

   ```
   Expected output:
   ghp_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
   ```

4. Verify the token can pull from GHCR:

   ```bash
   echo "<YOUR_TOKEN>" | docker login ghcr.io -u <your-github-username> --password-stdin
   docker pull ghcr.io/apiary-ai/apiary-slim-agent-claude-sdk:latest
   ```

   ```
   Expected output:
   Login Succeeded
   latest: Pulling from apiary-ai/apiary-slim-agent-claude-sdk
   ...
   Status: Downloaded newer image for ghcr.io/apiary-ai/apiary-slim-agent-claude-sdk:latest
   ```

### Cost & Rotation Notes

- Classic PATs are **free** — no per-token charge from GitHub.
- GitHub **does not auto-rotate** tokens. Set a calendar/Apiary schedule reminder for 90-day rotation (see [Rotation](#5-credential-rotation)).
- Classic PATs with `read:packages` scope are **required** for GHCR authentication — fine-grained PATs are not supported by GHCR.
- GHCR pull rate limits: authenticated pulls are limited to **unlimited** for private packages within the org; public images have a 1,000 pulls/hr limit per token. Hosted agent deploys are well below this.

---

## 2. Register the Credential in novps

Register the GHCR credential in the novps project so deploy payloads can reference it by UUID.

### Option A: novps Dashboard

1. Log in to the novps dashboard at `https://app.novps.io`.
2. Select the project used by Apiary Cloud.
3. Navigate to **Settings → Registry Keys** (or **Project → Registry Credentials**).
4. Click **Add Registry Key**.
5. Fill in:
   - **Registry URL:** `ghcr.io`
   - **Username:** `<your-github-username>`
   - **Password / Token:** `<the classic PAT from step 1>`
   - **Label:** `ghcr-apiary-ai-<environment>`
6. Click **Save**.
7. Copy the returned **credential UUID** from the detail view.

   ```
   Expected output (UUID):
   a1b2c3d4-e5f6-7890-abcd-ef1234567890
   ```

### Option B: novps API (`/registry/keys` endpoint)

```bash
curl -X POST "https://private-api.novps.io/projects/<PROJECT_ID>/registry/keys" \
  -H "Authorization: Bearer <NOVPS_API_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "registry": "ghcr.io",
    "username": "<your-github-username>",
    "password": "<GITHUB_PAT>",
    "label": "ghcr-apiary-ai-<environment>"
  }'
```

```
Expected output:
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "registry": "ghcr.io",
  "label": "ghcr-apiary-ai-production",
  "created_at": "2026-04-17T..."
}
```

Save the `id` value — this is the credential UUID needed in the next step.

---

## 3. Set the Environment Variable

Set `NOVPS_GHCR_CREDENTIAL_ID` on the Cloud Apiary deployment so the deploy job can reference the credential when building novps apply payloads.

1. In the Apiary Cloud deployment environment (`.env`, infra config, or novps app env), set:

   ```
   NOVPS_GHCR_CREDENTIAL_ID=a1b2c3d4-e5f6-7890-abcd-ef1234567890
   ```

2. Verify the value is picked up by the application:

   ```bash
   php artisan tinker --execute="echo config('services.novps.registry_credential_id');"
   ```

   ```
   Expected output:
   a1b2c3d4-e5f6-7890-abcd-ef1234567890
   ```

3. Restart the application / redeploy if necessary for the env change to take effect.

---

## 4. Sanity Check

Deploy a test hosted agent to confirm the credential works end-to-end.

> **Prerequisite:** The hosted-agent CRUD API routes (TASK-228) must be deployed. These routes are available on `main` as of PR #434.
> **Prerequisite:** The deploy job implementation (TASK-230) must be deployed. Until TASK-230 merges, `DeployHostedAgentJob` is a no-op stub and the agent will never reach `running`.

1. Ensure `APIARY_HOSTED_AGENTS_ENABLED=true` in the deployment environment.

2. Via the dashboard or API, deploy a hosted agent using the `claude-sdk` preset into a **test hive**:

   ```bash
   curl -X POST "https://<APIARY_URL>/api/v1/hives/<test-hive-slug>/hosted-agents" \
     -H "Authorization: Bearer <USER_TOKEN>" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "credential-test",
       "preset_key": "claude-sdk",
       "model": "claude-sonnet-4-5",
       "user_env": {
         "ANTHROPIC_API_KEY": "<test-api-key>"
       }
     }'
   ```

   ```
   Expected output:
   {
     "data": {
       "id": "hag_01J...",
       "status": "deploying",
       ...
     }
   }
   ```

3. Poll the status endpoint until the agent reaches `running`:

   ```bash
   curl "https://<APIARY_URL>/api/v1/hives/<test-hive-slug>/hosted-agents/<id>/status" \
     -H "Authorization: Bearer <USER_TOKEN>"
   ```

   ```
   Expected output:
   {
     "data": {
       "status": "running",
       ...
     }
   }
   ```

4. If the status reaches `running`, the GHCR credential is working — novps successfully pulled the private image.

5. Clean up the test agent:

   ```bash
   curl -X DELETE "https://<APIARY_URL>/api/v1/hives/<test-hive-slug>/hosted-agents/<id>" \
     -H "Authorization: Bearer <USER_TOKEN>"
   ```

---

## 5. Credential Rotation

When the GitHub PAT approaches expiration (every 90 days), rotate the credential with zero downtime.

### Steps

1. **Provision a new GitHub PAT** following [Section 1](#1-provision-a-github-token) above.

2. **Register the new credential in novps** following [Section 2](#2-register-the-credential-in-novps). This creates a **new** credential UUID — the old one remains valid until deleted.

3. **Update the environment variable** on the Apiary Cloud deployment:

   ```
   NOVPS_GHCR_CREDENTIAL_ID=<new-uuid>
   ```

4. **Identify all hosted agents that need redeployment.** Run this SQL against the Apiary database to list affected rows:

   ```sql
   SELECT
       ha.id                AS hosted_agent_id,
       ha.novps_app_name,
       ha.status,
       ha.preset_key,
       ha.last_deployed_at,
       a.name               AS agent_name,
       h.name               AS hive_name
   FROM hosted_agents ha
   JOIN agents a ON a.id = ha.agent_id
   JOIN hives h ON h.id = ha.hive_id
   WHERE ha.status IN ('running', 'stopped', 'error')
     AND ha.novps_app_name IS NOT NULL
   ORDER BY ha.last_deployed_at ASC;
   ```

5. **Redeploy hosted agents** so they pick up the new credential. The correct lifecycle action depends on the agent's current status:

   > **Prerequisite:** The lifecycle API endpoints (`/start`, `/stop`, `/restart`) require TASK-233 to be completed. Until then, use the tinker fallback in step 5b.

   **5a. Via the lifecycle API (requires TASK-233):**

   - **`running` agents** — call `/restart` (restart is only allowed from the `running` state):

     ```bash
     curl -X POST "https://<APIARY_URL>/api/v1/hives/<hive>/hosted-agents/<id>/restart" \
       -H "Authorization: Bearer <ADMIN_TOKEN>"
     ```

   - **`stopped` or `error` agents** — call `/start` (start is allowed from `stopped` or `error` state):

     ```bash
     curl -X POST "https://<APIARY_URL>/api/v1/hives/<hive>/hosted-agents/<id>/start" \
       -H "Authorization: Bearer <ADMIN_TOKEN>"
     ```

   **5b. Via tinker (fallback — works today):**

   > **Warning:** `DeployHostedAgentJob` is a no-op stub on `main` until TASK-230 (PR #442) merges. This path will only work once TASK-230 is deployed.

   ```bash
   php artisan tinker --execute="
       App\Cloud\Models\HostedAgent::whereIn('status', ['running', 'stopped', 'error'])
           ->each(fn (\$ha) => dispatch(new App\Cloud\Jobs\DeployHostedAgentJob(\$ha->id)));
   "
   ```

6. **Verify** at least one agent reaches `running` status after redeployment (follow [Section 4](#4-sanity-check)).

7. **Delete the old credential** from novps (dashboard or API) once all agents are confirmed running on the new one.

8. **Revoke the old GitHub PAT** in GitHub → Settings → Developer settings → Personal access tokens.

---

## 6. If Something Breaks

### Failure Mode 1: Bad Token Scope

**Symptom:** Hosted agent deployment fails with status `error`. novps logs show an image pull error:

```
Error: unauthorized: authentication required
```

or

```
Error: denied: permission denied
```

**Cause:** The GitHub PAT does not have `read:packages` permission, or it was scoped to the wrong organisation / repositories.

**Fix:**

1. Verify the token works locally:
   ```bash
   echo "<YOUR_TOKEN>" | docker login ghcr.io -u <your-github-username> --password-stdin
   docker pull ghcr.io/apiary-ai/apiary-slim-agent-claude-sdk:latest
   ```
2. If `docker login` succeeds but `docker pull` fails, the token is missing the Packages `Read` permission. Generate a new token with the correct scope.
3. If `docker login` fails, the token is expired or revoked. Generate a new token.
4. After fixing, update the novps registry credential (register a new one or update the existing one) and redeploy.

### Failure Mode 2: GHCR Rate Limit

**Symptom:** Deployments fail intermittently. novps logs show:

```
Error: toomanyrequests: rate limit exceeded
```

**Cause:** Too many image pulls in a short window. This is uncommon for authenticated pulls of private images but can happen during mass redeployments.

**Fix:**

1. Wait 5-10 minutes for the rate limit window to reset.
2. Stagger redeployments instead of triggering all at once — add a short delay between each restart.
3. If the issue persists, check whether the token is being used from multiple environments (staging + production). Use a separate PAT per environment to avoid shared rate limits.
4. Verify you are using an **authenticated** pull (credential registered in novps). Unauthenticated GHCR pulls have much lower limits (as low as ~100/hr per IP).

---

*Related: [FEATURE_HOSTED_AGENTS.md §4.1](../features/list-1/FEATURE_HOSTED_AGENTS.md#41-configservicesphp) — novps operator configuration*
*Task: TASK-255*
