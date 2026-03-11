"""Tests for task lifecycle endpoints."""

from __future__ import annotations

import json

import pytest

from apiary_sdk import ApiaryClient
from apiary_sdk.exceptions import ConflictError

from .conftest import BASE_URL, HIVE_ID, TASK_ID, TOKEN, envelope


def _task_data(**overrides):
    base = {
        "id": TASK_ID,
        "apiary_id": "A" * 26,
        "hive_id": HIVE_ID,
        "type": "process",
        "status": "pending",
        "priority": 2,
        "payload": {},
        "progress": 0,
        "claimed_by": None,
        "created_at": "2026-02-26T12:00:00Z",
    }
    base.update(overrides)
    return base


class TestCreateTask:
    def test_create_task_minimal(self, httpx_mock):
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/hives/{HIVE_ID}/tasks",
            status_code=201,
            json=envelope(_task_data()),
        )
        with ApiaryClient(BASE_URL, token=TOKEN) as c:
            task = c.create_task(HIVE_ID, task_type="process")
        assert task["id"] == TASK_ID
        assert task["status"] == "pending"

    def test_create_task_full(self, httpx_mock):
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/hives/{HIVE_ID}/tasks",
            status_code=201,
            json=envelope(_task_data(priority=4)),
        )
        with ApiaryClient(BASE_URL, token=TOKEN) as c:
            c.create_task(
                HIVE_ID,
                task_type="process",
                priority=4,
                target_capability="code",
                payload={
                    "input": "data",
                    "invoke": {
                        "instructions": "legacy payload instructions",
                        "context": {"origin": "payload"},
                    },
                },
                timeout_seconds=300,
                max_retries=5,
                context_refs=["ref-1"],
                invoke_instructions="first-class instructions",
                invoke_context={"origin": "top-level", "attempt": 2},
            )
        body = json.loads(httpx_mock.get_request().content)
        assert body["type"] == "process"
        assert body["priority"] == 4
        assert body["target_capability"] == "code"
        assert body["payload"] == {
            "input": "data",
            "invoke": {
                "instructions": "legacy payload instructions",
                "context": {"origin": "payload"},
            },
        }
        assert body["timeout_seconds"] == 300
        assert body["max_retries"] == 5
        assert body["context_refs"] == ["ref-1"]
        assert body["invoke"] == {
            "instructions": "first-class instructions",
            "context": {"origin": "top-level", "attempt": 2},
        }


class TestPollTasks:
    def test_poll_returns_list(self, httpx_mock):
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/hives/{HIVE_ID}/tasks/poll",
            json=envelope([_task_data(), _task_data(id="T" * 26)]),
        )
        with ApiaryClient(BASE_URL, token=TOKEN) as c:
            tasks = c.poll_tasks(HIVE_ID)
        assert len(tasks) == 2

    def test_poll_with_params(self, httpx_mock):
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/hives/{HIVE_ID}/tasks/poll?capability=code&limit=3",
            json=envelope([]),
        )
        with ApiaryClient(BASE_URL, token=TOKEN) as c:
            tasks = c.poll_tasks(HIVE_ID, capability="code", limit=3)
        assert tasks == []

    def test_poll_empty(self, httpx_mock):
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/hives/{HIVE_ID}/tasks/poll",
            json=envelope([]),
        )
        with ApiaryClient(BASE_URL, token=TOKEN) as c:
            tasks = c.poll_tasks(HIVE_ID)
        assert tasks == []


class TestClaimTask:
    def test_claim_success(self, httpx_mock):
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/hives/{HIVE_ID}/tasks/{TASK_ID}/claim",
            json=envelope(_task_data(status="in_progress", claimed_by="agent-1")),
        )
        with ApiaryClient(BASE_URL, token=TOKEN) as c:
            task = c.claim_task(HIVE_ID, TASK_ID)
        assert task["status"] == "in_progress"

    def test_claim_conflict(self, httpx_mock):
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/hives/{HIVE_ID}/tasks/{TASK_ID}/claim",
            status_code=409,
            json=envelope(errors=[{"message": "Task is no longer available.", "code": "conflict"}]),
        )
        with ApiaryClient(BASE_URL, token=TOKEN) as c:
            with pytest.raises(ConflictError):
                c.claim_task(HIVE_ID, TASK_ID)


class TestUpdateProgress:
    def test_progress_update(self, httpx_mock):
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/hives/{HIVE_ID}/tasks/{TASK_ID}/progress",
            json=envelope(_task_data(status="in_progress", progress=50)),
        )
        with ApiaryClient(BASE_URL, token=TOKEN) as c:
            task = c.update_progress(HIVE_ID, TASK_ID, progress=50, status_message="halfway")
        assert task["progress"] == 50
        body = json.loads(httpx_mock.get_request().content)
        assert body["progress"] == 50
        assert body["status_message"] == "halfway"


class TestCompleteTask:
    def test_complete(self, httpx_mock):
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/hives/{HIVE_ID}/tasks/{TASK_ID}/complete",
            json=envelope(
                _task_data(
                    status="completed",
                    progress=100,
                    result={"output": "done"},
                    completed_at="2026-02-26T12:05:00Z",
                )
            ),
        )
        with ApiaryClient(BASE_URL, token=TOKEN) as c:
            task = c.complete_task(HIVE_ID, TASK_ID, result={"output": "done"})
        assert task["status"] == "completed"
        assert task["progress"] == 100


class TestFailTask:
    def test_fail(self, httpx_mock):
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/hives/{HIVE_ID}/tasks/{TASK_ID}/fail",
            json=envelope(
                _task_data(
                    status="failed",
                    result={"reason": "crash"},
                )
            ),
        )
        with ApiaryClient(BASE_URL, token=TOKEN) as c:
            task = c.fail_task(HIVE_ID, TASK_ID, error={"reason": "crash"})
        assert task["status"] == "failed"
