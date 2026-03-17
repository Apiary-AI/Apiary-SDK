"""Core HTTP client with envelope parsing and auth management."""

from __future__ import annotations

from typing import Any

import httpx

from apiary_sdk.exceptions import ApiaryError, raise_for_status


class ApiaryClient:
    """Minimal Python client for the Apiary agent orchestration API.

    Usage::

        client = ApiaryClient("https://apiary.example.com")
        data = client.register(
            name="my-agent",
            hive_id="01HXYZ...",
            secret="super-secret-value-16+",
        )
        # client.token is now set automatically

        tasks = client.poll_tasks(hive_id="01HXYZ...")
    """

    def __init__(
        self,
        base_url: str,
        *,
        token: str | None = None,
        timeout: float = 30.0,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.token = token
        self._http = httpx.Client(
            base_url=self.base_url,
            timeout=timeout,
            headers={"Accept": "application/json"},
        )

    # ------------------------------------------------------------------
    # Low-level helpers
    # ------------------------------------------------------------------

    def _headers(self) -> dict[str, str]:
        headers: dict[str, str] = {}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        return headers

    def _request(
        self,
        method: str,
        path: str,
        *,
        json: dict[str, Any] | None = None,
        params: dict[str, Any] | None = None,
    ) -> dict[str, Any] | None:
        """Send a request, unwrap the Apiary envelope, raise on errors."""
        response = self._http.request(
            method,
            path,
            json=json,
            params=params,
            headers=self._headers(),
        )

        if response.status_code == 204:
            return None

        try:
            body = response.json()
        except Exception:
            if response.status_code >= 400:
                snippet = response.text[:200]
                raise ApiaryError(
                    f"HTTP {response.status_code}: {snippet}",
                    status_code=response.status_code,
                )
            raise ApiaryError(
                f"Expected JSON response, got {response.headers.get('content-type', 'unknown')}",
                status_code=response.status_code,
            )

        if response.status_code >= 400:
            raise_for_status(response.status_code, body)

        return body.get("data")

    # ------------------------------------------------------------------
    # Agent auth
    # ------------------------------------------------------------------

    def register(
        self,
        *,
        name: str,
        hive_id: str,
        secret: str,
        apiary_id: str | None = None,
        agent_type: str = "custom",
        capabilities: list[str] | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Register a new agent and store the returned token.

        Returns the full ``data`` dict (``agent`` + ``token``).
        """
        payload: dict[str, Any] = {
            "name": name,
            "hive_id": hive_id,
            "secret": secret,
            "type": agent_type,
        }
        if apiary_id is not None:
            payload["apiary_id"] = apiary_id
        if capabilities is not None:
            payload["capabilities"] = capabilities
        if metadata is not None:
            payload["metadata"] = metadata

        data = self._request("POST", "/api/v1/agents/register", json=payload)
        self.token = data["token"]
        return data

    def login(self, *, agent_id: str, secret: str) -> dict[str, Any]:
        """Authenticate an existing agent and store the returned token."""
        data = self._request(
            "POST",
            "/api/v1/agents/login",
            json={"agent_id": agent_id, "secret": secret},
        )
        self.token = data["token"]
        return data

    def logout(self) -> None:
        """Revoke the current token."""
        try:
            self._request("POST", "/api/v1/agents/logout")
        finally:
            self.token = None

    def me(self) -> dict[str, Any]:
        """Return the currently authenticated agent's profile."""
        return self._request("GET", "/api/v1/agents/me")

    # ------------------------------------------------------------------
    # Agent lifecycle
    # ------------------------------------------------------------------

    def heartbeat(self, *, metadata: dict[str, Any] | None = None) -> dict[str, Any]:
        """Send a heartbeat to keep the agent alive."""
        payload = {}
        if metadata is not None:
            payload["metadata"] = metadata
        return self._request("POST", "/api/v1/agents/heartbeat", json=payload)

    def update_status(self, status: str) -> dict[str, Any]:
        """Update the agent's status (online/busy/idle/offline/error)."""
        return self._request("PATCH", "/api/v1/agents/status", json={"status": status})

    # ------------------------------------------------------------------
    # Drain mode
    # ------------------------------------------------------------------

    def enter_drain(
        self,
        *,
        reason: str | None = None,
        deadline_minutes: int | None = None,
    ) -> dict[str, Any]:
        """Enter drain mode. The agent stops accepting new tasks."""
        body: dict[str, Any] = {}
        if reason is not None:
            body["reason"] = reason
        if deadline_minutes is not None:
            body["deadline_minutes"] = deadline_minutes
        return self._request("POST", "/api/v1/agents/drain", json=body or None)

    def exit_drain(self) -> dict[str, Any]:
        """Exit drain mode, restoring normal operation."""
        return self._request("POST", "/api/v1/agents/undrain")

    def drain_status(self) -> dict[str, Any]:
        """Get current drain status for the authenticated agent."""
        return self._request("GET", "/api/v1/agents/drain")

    # ------------------------------------------------------------------
    # Key rotation
    # ------------------------------------------------------------------

    def rotate_key(
        self,
        *,
        new_secret: str,
        grace_period_minutes: int = 0,
    ) -> dict[str, Any]:
        """Rotate the agent's API key. Returns a new token.

        The old key remains valid for ``grace_period_minutes`` (0 = immediate).
        """
        body: dict[str, Any] = {"new_secret": new_secret}
        if grace_period_minutes:
            body["grace_period_minutes"] = grace_period_minutes
        data = self._request("POST", "/api/v1/agents/key/rotate", json=body)
        self.token = data["token"]
        return data

    def revoke_previous_key(self) -> dict[str, Any]:
        """Immediately revoke the previous (grace-period) key."""
        return self._request("POST", "/api/v1/agents/key/revoke")

    def key_status(self) -> dict[str, Any]:
        """Get current key rotation status."""
        return self._request("GET", "/api/v1/agents/key/status")

    # ------------------------------------------------------------------
    # Pool health
    # ------------------------------------------------------------------

    def get_pool_health(
        self,
        hive_id: str,
        *,
        window: int | None = None,
    ) -> dict[str, Any]:
        """Get pool health metrics (agents, backlog, throughput) for a hive."""
        params: dict[str, Any] = {}
        if window is not None:
            params["window"] = window
        return self._request("GET", f"/api/v1/hives/{hive_id}/pool/health", params=params or None)

    # ------------------------------------------------------------------
    # Tasks
    # ------------------------------------------------------------------

    def create_task(
        self,
        hive_id: str,
        *,
        task_type: str,
        priority: int | None = None,
        target_agent_id: str | None = None,
        target_capability: str | None = None,
        payload: dict[str, Any] | None = None,
        timeout_seconds: int | None = None,
        max_retries: int | None = None,
        parent_task_id: str | None = None,
        context_refs: list[str] | None = None,
        guarantee: str | None = None,
        expires_at: str | None = None,
        invoke_instructions: str | None = None,
        invoke_context: Any | None = None,
        failure_policy: dict[str, Any] | None = None,
        idempotency_key: str | None = None,
    ) -> dict[str, Any]:
        """Create a new task in the given hive."""
        body: dict[str, Any] = {"type": task_type}
        if priority is not None:
            body["priority"] = priority
        if target_agent_id is not None:
            body["target_agent_id"] = target_agent_id
        if target_capability is not None:
            body["target_capability"] = target_capability
        if payload is not None:
            body["payload"] = payload
        if timeout_seconds is not None:
            body["timeout_seconds"] = timeout_seconds
        if max_retries is not None:
            body["max_retries"] = max_retries
        if parent_task_id is not None:
            body["parent_task_id"] = parent_task_id
        if context_refs is not None:
            body["context_refs"] = context_refs
        if guarantee is not None:
            body["guarantee"] = guarantee
        if expires_at is not None:
            body["expires_at"] = expires_at
        if invoke_instructions is not None or invoke_context is not None:
            body["invoke"] = {}
            if invoke_instructions is not None:
                body["invoke"]["instructions"] = invoke_instructions
            if invoke_context is not None:
                body["invoke"]["context"] = invoke_context
        if failure_policy is not None:
            body["failure_policy"] = failure_policy
        if idempotency_key is not None:
            body["idempotency_key"] = idempotency_key
        return self._request("POST", f"/api/v1/hives/{hive_id}/tasks", json=body)

    def poll_tasks(
        self,
        hive_id: str,
        *,
        capability: str | None = None,
        limit: int | None = None,
    ) -> list[dict[str, Any]]:
        """Poll for available tasks. Returns a list (may be empty)."""
        params: dict[str, Any] = {}
        if capability is not None:
            params["capability"] = capability
        if limit is not None:
            params["limit"] = limit
        return self._request("GET", f"/api/v1/hives/{hive_id}/tasks/poll", params=params)

    def claim_task(self, hive_id: str, task_id: str) -> dict[str, Any]:
        """Atomically claim a pending task."""
        return self._request("PATCH", f"/api/v1/hives/{hive_id}/tasks/{task_id}/claim")

    def update_progress(
        self,
        hive_id: str,
        task_id: str,
        *,
        progress: int,
        status_message: str | None = None,
    ) -> dict[str, Any]:
        """Report progress on a claimed task (0-100)."""
        body: dict[str, Any] = {"progress": progress}
        if status_message is not None:
            body["status_message"] = status_message
        return self._request(
            "PATCH", f"/api/v1/hives/{hive_id}/tasks/{task_id}/progress", json=body
        )

    def complete_task(
        self,
        hive_id: str,
        task_id: str,
        *,
        result: dict[str, Any] | None = None,
        status_message: str | None = None,
    ) -> dict[str, Any]:
        """Mark a claimed task as completed."""
        body: dict[str, Any] = {}
        if result is not None:
            body["result"] = result
        if status_message is not None:
            body["status_message"] = status_message
        return self._request(
            "PATCH", f"/api/v1/hives/{hive_id}/tasks/{task_id}/complete", json=body
        )

    def fail_task(
        self,
        hive_id: str,
        task_id: str,
        *,
        error: dict[str, Any] | None = None,
        status_message: str | None = None,
    ) -> dict[str, Any]:
        """Mark a claimed task as failed."""
        body: dict[str, Any] = {}
        if error is not None:
            body["error"] = error
        if status_message is not None:
            body["status_message"] = status_message
        return self._request("PATCH", f"/api/v1/hives/{hive_id}/tasks/{task_id}/fail", json=body)

    # ------------------------------------------------------------------
    # Task replay / time travel
    # ------------------------------------------------------------------

    def get_task_trace(self, hive_id: str, task_id: str) -> dict[str, Any]:
        """Get the full execution trace for a task."""
        return self._request("GET", f"/api/v1/hives/{hive_id}/tasks/{task_id}/trace")

    def replay_task(
        self,
        hive_id: str,
        task_id: str,
        *,
        override_payload: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Create a replay of a completed/failed/dead_letter/expired task."""
        body: dict[str, Any] = {}
        if override_payload is not None:
            body["override_payload"] = override_payload
        return self._request(
            "POST", f"/api/v1/hives/{hive_id}/tasks/{task_id}/replay", json=body or None
        )

    def compare_tasks(
        self,
        hive_id: str,
        *,
        task_a: str,
        task_b: str,
    ) -> dict[str, Any]:
        """Compare two tasks by payload, result, and trace."""
        return self._request(
            "GET",
            f"/api/v1/hives/{hive_id}/tasks/compare",
            params={"task_a": task_a, "task_b": task_b},
        )

    # ------------------------------------------------------------------
    # Knowledge
    # ------------------------------------------------------------------

    def list_knowledge(
        self,
        hive_id: str,
        *,
        key: str | None = None,
        scope: str | None = None,
        limit: int | None = None,
    ) -> list[dict[str, Any]]:
        """List knowledge entries in a hive."""
        params: dict[str, Any] = {}
        if key is not None:
            params["key"] = key
        if scope is not None:
            params["scope"] = scope
        if limit is not None:
            params["limit"] = limit
        return self._request("GET", f"/api/v1/hives/{hive_id}/knowledge", params=params)

    def search_knowledge(
        self,
        hive_id: str,
        *,
        q: str | None = None,
        scope: str | None = None,
        limit: int | None = None,
    ) -> list[dict[str, Any]]:
        """Full-text search knowledge entries."""
        params: dict[str, Any] = {}
        if q is not None:
            params["q"] = q
        if scope is not None:
            params["scope"] = scope
        if limit is not None:
            params["limit"] = limit
        return self._request("GET", f"/api/v1/hives/{hive_id}/knowledge/search", params=params)

    def get_knowledge(self, hive_id: str, entry_id: str) -> dict[str, Any]:
        """Get a single knowledge entry by ID."""
        return self._request("GET", f"/api/v1/hives/{hive_id}/knowledge/{entry_id}")

    def create_knowledge(
        self,
        hive_id: str,
        *,
        key: str,
        value: Any,
        scope: str | None = None,
        visibility: str | None = None,
        ttl: str | None = None,
    ) -> dict[str, Any]:
        """Create a new knowledge entry."""
        body: dict[str, Any] = {"key": key, "value": value}
        if scope is not None:
            body["scope"] = scope
        if visibility is not None:
            body["visibility"] = visibility
        if ttl is not None:
            body["ttl"] = ttl
        return self._request("POST", f"/api/v1/hives/{hive_id}/knowledge", json=body)

    def update_knowledge(
        self,
        hive_id: str,
        entry_id: str,
        *,
        value: Any,
        visibility: str | None = None,
        ttl: str | None = None,
    ) -> dict[str, Any]:
        """Update an existing knowledge entry (bumps version)."""
        body: dict[str, Any] = {"value": value}
        if visibility is not None:
            body["visibility"] = visibility
        if ttl is not None:
            body["ttl"] = ttl
        return self._request("PUT", f"/api/v1/hives/{hive_id}/knowledge/{entry_id}", json=body)

    def delete_knowledge(self, hive_id: str, entry_id: str) -> None:
        """Delete a knowledge entry."""
        self._request("DELETE", f"/api/v1/hives/{hive_id}/knowledge/{entry_id}")

    # ------------------------------------------------------------------
    # Schedules
    # ------------------------------------------------------------------

    def list_schedules(
        self,
        hive_id: str,
        *,
        status: str | None = None,
    ) -> list[dict[str, Any]]:
        """List task schedules in a hive."""
        params: dict[str, Any] = {}
        if status is not None:
            params["status"] = status
        return self._request("GET", f"/api/v1/hives/{hive_id}/schedules", params=params or None)

    def get_schedule(self, hive_id: str, schedule_id: str) -> dict[str, Any]:
        """Get a single task schedule by ID."""
        return self._request("GET", f"/api/v1/hives/{hive_id}/schedules/{schedule_id}")

    def create_schedule(
        self,
        hive_id: str,
        *,
        name: str,
        trigger_type: str,
        task_type: str,
        cron_expression: str | None = None,
        interval_seconds: int | None = None,
        run_at: str | None = None,
        description: str | None = None,
        task_payload: dict[str, Any] | None = None,
        task_priority: int | None = None,
        task_target_agent_id: str | None = None,
        task_target_capability: str | None = None,
        task_timeout_seconds: int | None = None,
        task_max_retries: int | None = None,
        task_context_refs: list[str] | None = None,
        task_failure_policy: dict[str, Any] | None = None,
        overlap_policy: str | None = None,
        expires_at: str | None = None,
    ) -> dict[str, Any]:
        """Create a new task schedule."""
        body: dict[str, Any] = {
            "name": name,
            "trigger_type": trigger_type,
            "task_type": task_type,
        }
        if cron_expression is not None:
            body["cron_expression"] = cron_expression
        if interval_seconds is not None:
            body["interval_seconds"] = interval_seconds
        if run_at is not None:
            body["run_at"] = run_at
        if description is not None:
            body["description"] = description
        if task_payload is not None:
            body["task_payload"] = task_payload
        if task_priority is not None:
            body["task_priority"] = task_priority
        if task_target_agent_id is not None:
            body["task_target_agent_id"] = task_target_agent_id
        if task_target_capability is not None:
            body["task_target_capability"] = task_target_capability
        if task_timeout_seconds is not None:
            body["task_timeout_seconds"] = task_timeout_seconds
        if task_max_retries is not None:
            body["task_max_retries"] = task_max_retries
        if task_context_refs is not None:
            body["task_context_refs"] = task_context_refs
        if task_failure_policy is not None:
            body["task_failure_policy"] = task_failure_policy
        if overlap_policy is not None:
            body["overlap_policy"] = overlap_policy
        if expires_at is not None:
            body["expires_at"] = expires_at
        return self._request("POST", f"/api/v1/hives/{hive_id}/schedules", json=body)

    def update_schedule(
        self,
        hive_id: str,
        schedule_id: str,
        **fields: Any,
    ) -> dict[str, Any]:
        """Update a task schedule. Pass only the fields to change."""
        return self._request("PUT", f"/api/v1/hives/{hive_id}/schedules/{schedule_id}", json=fields)

    def delete_schedule(self, hive_id: str, schedule_id: str) -> None:
        """Delete a task schedule."""
        self._request("DELETE", f"/api/v1/hives/{hive_id}/schedules/{schedule_id}")

    def pause_schedule(self, hive_id: str, schedule_id: str) -> dict[str, Any]:
        """Pause an active schedule."""
        return self._request("PATCH", f"/api/v1/hives/{hive_id}/schedules/{schedule_id}/pause")

    def resume_schedule(self, hive_id: str, schedule_id: str) -> dict[str, Any]:
        """Resume a paused schedule."""
        return self._request("PATCH", f"/api/v1/hives/{hive_id}/schedules/{schedule_id}/resume")

    # ------------------------------------------------------------------
    # Rate Limiting
    # ------------------------------------------------------------------

    def rate_limit_status(self) -> dict[str, Any]:
        """Get current rate limit configuration and usage for this agent."""
        return self._request("GET", "/api/v1/agents/rate-limit")

    def update_rate_limit(
        self,
        *,
        rate_limit_per_minute: int | None,
    ) -> dict[str, Any]:
        """Update the per-agent rate limit. Pass None to reset to system default."""
        return self._request(
            "PUT",
            "/api/v1/agents/rate-limit",
            json={"rate_limit_per_minute": rate_limit_per_minute},
        )

    # ------------------------------------------------------------------
    # Persona
    # ------------------------------------------------------------------

    def get_persona(self) -> dict[str, Any]:
        """Get the agent's active persona (policy-selected version)."""
        return self._request("GET", "/api/v1/persona")

    def get_persona_config(self) -> dict[str, Any]:
        """Get persona config only."""
        return self._request("GET", "/api/v1/persona/config")

    def get_persona_document(self, name: str) -> dict[str, Any]:
        """Get a single persona document by name."""
        return self._request("GET", f"/api/v1/persona/documents/{name}")

    def get_persona_assembled(self) -> dict[str, Any]:
        """Get pre-assembled system prompt (SOUL→AGENT→RULES→STYLE→EXAMPLES→MEMORY)."""
        return self._request("GET", "/api/v1/persona/assembled")

    def update_persona_document(
        self,
        name: str,
        *,
        content: str,
        message: str | None = None,
    ) -> dict[str, Any]:
        """Update a single persona document (agent self-update)."""
        body: dict[str, Any] = {"content": content}
        if message is not None:
            body["message"] = message
        return self._request("PATCH", f"/api/v1/persona/documents/{name}", json=body)

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    def close(self) -> None:
        """Close the underlying HTTP connection pool."""
        self._http.close()

    def __enter__(self) -> ApiaryClient:
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()
