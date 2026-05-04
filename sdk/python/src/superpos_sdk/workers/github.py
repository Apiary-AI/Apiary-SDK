"""GitHub service worker — interact with the GitHub REST API.

Install the optional dependency::

    pip install superpos-sdk[github]

Credentials (env-first, payload fallback):

- ``GITHUB_TOKEN`` — personal access token or GitHub App token

Task payload (``params``) schema varies by operation.  All operations accept
an optional ``token`` key that overrides the environment variable.

Supported operations
--------------------

``get_issue``
    ``{"owner": "...", "repo": "...", "number": 1}``

``create_issue``
    ``{"owner": "...", "repo": "...", "title": "...", "body": "...", "labels": [...]}``

``list_issues``
    ``{"owner": "...", "repo": "...", "state": "open", "per_page": 30, "page": 1}``

``get_pr``
    ``{"owner": "...", "repo": "...", "number": 1}``

``list_prs``
    ``{"owner": "...", "repo": "...", "state": "open", "per_page": 30, "page": 1}``

``create_pr``
    ``{"owner": "...", "repo": "...", "title": "...", "head": "...", "base": "...",
       "body": "...", "draft": false}``

``get_file``
    ``{"owner": "...", "repo": "...", "path": "README.md", "ref": "main"}``

``create_file``
    ``{"owner": "...", "repo": "...", "path": "...", "message": "...",
       "content": "<base64>", "branch": "main"}``

``update_file``
    ``{"owner": "...", "repo": "...", "path": "...", "message": "...",
       "content": "<base64>", "sha": "...", "branch": "main"}``

``list_commits``
    ``{"owner": "...", "repo": "...", "sha": "main", "per_page": 30, "page": 1}``

``get_commit``
    ``{"owner": "...", "repo": "...", "ref": "<sha>"}``
"""

from __future__ import annotations

import os
from typing import Any

from superpos_sdk.service_worker import ServiceWorker

_GITHUB_API = "https://api.github.com"


class GitHubWorker(ServiceWorker):
    """Service worker that proxies GitHub REST API calls.

    Credentials are read from the ``GITHUB_TOKEN`` environment variable.
    A per-request ``token`` key in *params* overrides the environment token.
    """

    CAPABILITY = "data:github"

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _client(self, params: dict[str, Any]):  # type: ignore[return]
        """Return an httpx.Client configured for the GitHub API."""
        try:
            import httpx
        except ImportError as exc:  # pragma: no cover
            raise ImportError(
                "httpx is required for GitHubWorker. "
                "Install it with: pip install superpos-sdk[github]"
            ) from exc

        token = params.get("token") or os.environ.get("GITHUB_TOKEN", "")
        headers: dict[str, str] = {
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        }
        if token:
            headers["Authorization"] = f"Bearer {token}"
        return httpx.Client(base_url=_GITHUB_API, headers=headers, timeout=30)

    def _get(self, params: dict[str, Any], path: str, **query: Any) -> Any:
        query = {k: v for k, v in query.items() if v is not None}
        with self._client(params) as c:
            r = c.get(path, params=query or None)
            r.raise_for_status()
            return r.json()

    def _post(self, params: dict[str, Any], path: str, body: dict[str, Any]) -> Any:
        with self._client(params) as c:
            r = c.post(path, json=body)
            r.raise_for_status()
            return r.json()

    def _put(self, params: dict[str, Any], path: str, body: dict[str, Any]) -> Any:
        with self._client(params) as c:
            r = c.put(path, json=body)
            r.raise_for_status()
            return r.json()

    @staticmethod
    def _repo_path(params: dict[str, Any], *parts: str) -> str:
        owner = params["owner"]
        repo = params["repo"]
        base = f"/repos/{owner}/{repo}"
        if parts:
            base = base + "/" + "/".join(str(p) for p in parts)
        return base

    # ------------------------------------------------------------------
    # Issue operations
    # ------------------------------------------------------------------

    def get_issue(self, params: dict[str, Any]) -> dict[str, Any]:
        """Fetch a single issue by number."""
        return self._get(params, self._repo_path(params, "issues", params["number"]))

    def create_issue(self, params: dict[str, Any]) -> dict[str, Any]:
        """Create a new issue."""
        body: dict[str, Any] = {"title": params["title"]}
        if params.get("body"):
            body["body"] = params["body"]
        if params.get("labels"):
            body["labels"] = params["labels"]
        if params.get("assignees"):
            body["assignees"] = params["assignees"]
        return self._post(params, self._repo_path(params, "issues"), body)

    def list_issues(self, params: dict[str, Any]) -> list[dict[str, Any]]:
        """List issues for a repository."""
        return self._get(
            params,
            self._repo_path(params, "issues"),
            state=params.get("state", "open"),
            per_page=params.get("per_page", 30),
            page=params.get("page", 1),
            labels=params.get("labels"),
        )

    # ------------------------------------------------------------------
    # Pull request operations
    # ------------------------------------------------------------------

    def get_pr(self, params: dict[str, Any]) -> dict[str, Any]:
        """Fetch a single pull request by number."""
        return self._get(params, self._repo_path(params, "pulls", params["number"]))

    def list_prs(self, params: dict[str, Any]) -> list[dict[str, Any]]:
        """List pull requests for a repository."""
        return self._get(
            params,
            self._repo_path(params, "pulls"),
            state=params.get("state", "open"),
            per_page=params.get("per_page", 30),
            page=params.get("page", 1),
        )

    def create_pr(self, params: dict[str, Any]) -> dict[str, Any]:
        """Create a new pull request."""
        body: dict[str, Any] = {
            "title": params["title"],
            "head": params["head"],
            "base": params["base"],
        }
        if params.get("body"):
            body["body"] = params["body"]
        if "draft" in params:
            body["draft"] = bool(params["draft"])
        return self._post(params, self._repo_path(params, "pulls"), body)

    # ------------------------------------------------------------------
    # File / content operations
    # ------------------------------------------------------------------

    def get_file(self, params: dict[str, Any]) -> dict[str, Any]:
        """Fetch a file's metadata and base64-encoded content."""
        path = self._repo_path(params, "contents", params["path"])
        query: dict[str, Any] = {}
        if params.get("ref"):
            query["ref"] = params["ref"]
        with self._client(params) as c:
            r = c.get(path, params=query or None)
            r.raise_for_status()
            return r.json()

    def create_file(self, params: dict[str, Any]) -> dict[str, Any]:
        """Create a new file via the Contents API."""
        body: dict[str, Any] = {
            "message": params["message"],
            "content": params["content"],
        }
        if params.get("branch"):
            body["branch"] = params["branch"]
        return self._put(params, self._repo_path(params, "contents", params["path"]), body)

    def update_file(self, params: dict[str, Any]) -> dict[str, Any]:
        """Update an existing file via the Contents API."""
        body: dict[str, Any] = {
            "message": params["message"],
            "content": params["content"],
            "sha": params["sha"],
        }
        if params.get("branch"):
            body["branch"] = params["branch"]
        return self._put(params, self._repo_path(params, "contents", params["path"]), body)

    # ------------------------------------------------------------------
    # Commit operations
    # ------------------------------------------------------------------

    def list_commits(self, params: dict[str, Any]) -> list[dict[str, Any]]:
        """List commits for a repository."""
        return self._get(
            params,
            self._repo_path(params, "commits"),
            sha=params.get("sha"),
            per_page=params.get("per_page", 30),
            page=params.get("page", 1),
        )

    def get_commit(self, params: dict[str, Any]) -> dict[str, Any]:
        """Fetch a single commit by SHA."""
        return self._get(params, self._repo_path(params, "commits", params["ref"]))
