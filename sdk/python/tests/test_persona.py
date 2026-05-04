"""Tests for persona endpoints."""

from __future__ import annotations

import json

import pytest

from superpos_sdk import SuperposClient

from .conftest import BASE_URL, HIVE_ID, TOKEN, envelope


def _persona_data(**overrides):
    base = {
        "id": "01HXYZ00000000000000000010",
        "agent_id": "01HXYZ00000000000000000002",
        "version": 1,
        "config": {"model": "gpt-4", "temperature": 0.7},
        "documents": {
            "SOUL": "You are a helpful assistant.",
            "AGENT": "Agent-specific instructions.",
        },
        "created_at": "2026-03-01T12:00:00Z",
    }
    base.update(overrides)
    return base


class TestGetPersona:
    def test_get_persona(self, httpx_mock):
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/persona",
            json=envelope(_persona_data()),
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            persona = c.get_persona()
        assert persona["version"] == 1
        assert persona["documents"]["SOUL"] == "You are a helpful assistant."


class TestGetPersonaConfig:
    def test_get_persona_config(self, httpx_mock):
        data = {"version": 1, "config": {"model": "gpt-4", "temperature": 0.7}}
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/persona/config",
            json=envelope(data),
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            result = c.get_persona_config()
        assert result["version"] == 1
        assert result["config"]["model"] == "gpt-4"


class TestGetPersonaDocument:
    def test_get_persona_document(self, httpx_mock):
        doc = {"version": 1, "document": "SOUL", "content": "You are a helpful assistant."}
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/persona/documents/SOUL",
            json=envelope(doc),
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            result = c.get_persona_document("SOUL")
        assert result["document"] == "SOUL"
        assert result["content"] == "You are a helpful assistant."


class TestGetPersonaAssembled:
    def test_get_persona_assembled(self, httpx_mock):
        assembled = {
            "version": 1,
            "prompt": "SOUL: You are a helpful assistant.\nAGENT: Do tasks.",
            "document_count": 2,
        }
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/persona/assembled",
            json=envelope(assembled),
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            result = c.get_persona_assembled()
        assert result["prompt"].startswith("SOUL:")
        assert result["document_count"] == 2


class TestUpdatePersonaDocument:
    def test_update_with_message(self, httpx_mock):
        doc = {"version": 1, "document": "MEMORY", "content": "Updated memory."}
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/persona/documents/MEMORY",
            json=envelope(doc),
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            result = c.update_persona_document(
                "MEMORY", content="Updated memory.", message="learned new fact"
            )
        assert result["version"] == 1
        assert result["document"] == "MEMORY"
        assert result["content"] == "Updated memory."
        body = json.loads(httpx_mock.get_request().content)
        assert body["content"] == "Updated memory."
        assert body["message"] == "learned new fact"

    def test_update_minimal(self, httpx_mock):
        doc = {"version": 1, "document": "MEMORY", "content": "Bare update."}
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/persona/documents/MEMORY",
            json=envelope(doc),
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            result = c.update_persona_document("MEMORY", content="Bare update.")
        assert result["version"] == 1
        assert result["document"] == "MEMORY"
        assert result["content"] == "Bare update."
        body = json.loads(httpx_mock.get_request().content)
        assert body["content"] == "Bare update."
        assert "message" not in body
        assert body["mode"] == "replace"

    def test_update_append_mode(self, httpx_mock):
        doc = {"version": 2, "document": "MEMORY", "content": "old\nnew fact"}
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/persona/documents/MEMORY",
            json=envelope(doc),
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            result = c.update_persona_document("MEMORY", content="new fact", mode="append")
        assert result["content"] == "old\nnew fact"
        body = json.loads(httpx_mock.get_request().content)
        assert body["mode"] == "append"
        assert body["content"] == "new fact"

    def test_update_prepend_mode(self, httpx_mock):
        doc = {"version": 2, "document": "MEMORY", "content": "preamble\nold"}
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/persona/documents/MEMORY",
            json=envelope(doc),
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            result = c.update_persona_document("MEMORY", content="preamble", mode="prepend")
        assert result["content"] == "preamble\nold"
        body = json.loads(httpx_mock.get_request().content)
        assert body["mode"] == "prepend"

    def test_update_invalid_mode_raises(self):
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            with pytest.raises(ValueError, match="Invalid mode"):
                c.update_persona_document("MEMORY", content="x", mode="overwrite")


class TestUpdateMemory:
    """Tests for the update_memory() convenience method."""

    def test_update_memory_default_mode_is_append(self, httpx_mock):
        doc = {"version": 2, "document": "MEMORY", "content": "old\nnew fact"}
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/persona/memory",
            json=envelope(doc),
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            result = c.update_memory(content="new fact")
        assert result["version"] == 2
        assert result["document"] == "MEMORY"
        body = json.loads(httpx_mock.get_request().content)
        assert body["content"] == "new fact"
        assert body["mode"] == "append"
        assert "message" not in body

    def test_update_memory_with_message(self, httpx_mock):
        doc = {"version": 2, "document": "MEMORY", "content": "old\nnew fact"}
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/persona/memory",
            json=envelope(doc),
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            result = c.update_memory(content="new fact", message="schema discovery")
        assert result["version"] == 2
        body = json.loads(httpx_mock.get_request().content)
        assert body["message"] == "schema discovery"

    def test_update_memory_replace_mode(self, httpx_mock):
        doc = {"version": 3, "document": "MEMORY", "content": "fresh slate"}
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/persona/memory",
            json=envelope(doc),
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            result = c.update_memory(content="fresh slate", mode="replace")
        assert result["content"] == "fresh slate"
        body = json.loads(httpx_mock.get_request().content)
        assert body["mode"] == "replace"

    def test_update_memory_prepend_mode(self, httpx_mock):
        doc = {"version": 4, "document": "MEMORY", "content": "preamble\nold"}
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/persona/memory",
            json=envelope(doc),
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            result = c.update_memory(content="preamble", mode="prepend")
        assert result["content"] == "preamble\nold"
        body = json.loads(httpx_mock.get_request().content)
        assert body["mode"] == "prepend"

    def test_update_memory_invalid_mode_raises(self):
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            with pytest.raises(ValueError, match="Invalid mode"):
                c.update_memory(content="x", mode="overwrite")


class TestGetPersonaVersion:
    """Tests for get_persona_version() — lightweight version polling (TASK-132)."""

    def test_get_persona_version_returns_version(self, httpx_mock):
        data = {"version": 3}
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/persona/version",
            json=envelope(data),
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            result = c.get_persona_version()
        assert result["version"] == 3
        assert "changed" not in result

    def test_get_persona_version_with_known_version_passes_param(self, httpx_mock):
        data = {"version": 3, "changed": False}
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/persona/version?known_version=3",
            json=envelope(data),
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            result = c.get_persona_version(known_version=3)
        assert result["version"] == 3
        assert result["changed"] is False

    def test_get_persona_version_changed_true_when_version_differs(self, httpx_mock):
        data = {"version": 4, "changed": True}
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/persona/version?known_version=3",
            json=envelope(data),
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            result = c.get_persona_version(known_version=3)
        assert result["changed"] is True

    def test_get_persona_version_null_when_no_persona(self, httpx_mock):
        data = {"version": None}
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/persona/version",
            json=envelope(data),
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            result = c.get_persona_version()
        assert result["version"] is None


class TestCheckPersonaVersion:
    """Tests for check_persona_version() — boolean changed helper (TASK-132)."""

    def test_check_persona_version_returns_false_when_unchanged(self, httpx_mock):
        data = {"version": 2, "changed": False}
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/persona/version?known_version=2",
            json=envelope(data),
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            changed = c.check_persona_version(known_version=2)
        assert changed is False

    def test_check_persona_version_returns_true_when_changed(self, httpx_mock):
        data = {"version": 5, "changed": True}
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/persona/version?known_version=2",
            json=envelope(data),
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            changed = c.check_persona_version(known_version=2)
        assert changed is True

    def test_check_persona_version_returns_false_when_changed_absent(self, httpx_mock):
        # Server may omit 'changed' when known_version is None.
        data = {"version": 1}
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/persona/version?known_version=1",
            json=envelope(data),
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            changed = c.check_persona_version(known_version=1)
        assert changed is False


class TestPollTasksWithMeta:
    """Tests for poll_tasks_with_meta() — full envelope with persona_version (TASK-132)."""

    def test_poll_tasks_with_meta_returns_full_envelope(self, httpx_mock):
        tasks = [{"id": "01ABC", "type": "default"}]
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/hives/{HIVE_ID}/tasks/poll",
            json={"data": tasks, "meta": {"total": 1, "persona_version": 3}, "errors": None},
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            envelope_result = c.poll_tasks_with_meta(HIVE_ID)
        assert envelope_result["data"] == tasks
        assert envelope_result["meta"]["persona_version"] == 3
        assert envelope_result["meta"]["total"] == 1

    def test_poll_tasks_with_meta_persona_version_none_when_no_persona(self, httpx_mock):
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/hives/{HIVE_ID}/tasks/poll",
            json={"data": [], "meta": {"total": 0, "persona_version": None}, "errors": None},
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            envelope_result = c.poll_tasks_with_meta(HIVE_ID)
        assert envelope_result["meta"]["persona_version"] is None

    def test_poll_tasks_with_meta_includes_platform_context_version(self, httpx_mock):
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/hives/{HIVE_ID}/tasks/poll",
            json={
                "data": [],
                "meta": {"total": 0, "persona_version": 1, "platform_context_version": 2},
                "errors": None,
            },
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            envelope_result = c.poll_tasks_with_meta(HIVE_ID)
        assert envelope_result["meta"]["platform_context_version"] == 2

    def test_poll_tasks_with_meta_platform_context_version_none(self, httpx_mock):
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/hives/{HIVE_ID}/tasks/poll",
            json={
                "data": [],
                "meta": {"total": 0, "persona_version": 1, "platform_context_version": None},
                "errors": None,
            },
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            envelope_result = c.poll_tasks_with_meta(HIVE_ID)
        assert envelope_result["meta"]["platform_context_version"] is None


class TestGetPersonaVersionPlatformContext:
    """Tests for known_platform_version in get_persona_version and check_persona_version."""

    def test_get_persona_version_with_known_platform_version(self, httpx_mock):
        data = {"version": 3, "platform_context_version": 2, "changed": False}
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/persona/version?known_version=3&known_platform_version=2",
            json=envelope(data),
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            result = c.get_persona_version(known_version=3, known_platform_version=2)
        assert result["version"] == 3
        assert result["platform_context_version"] == 2
        assert result["changed"] is False

    def test_get_persona_version_platform_change_triggers_changed(self, httpx_mock):
        data = {"version": 3, "platform_context_version": 5, "changed": True}
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/persona/version?known_version=3&known_platform_version=2",
            json=envelope(data),
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            result = c.get_persona_version(known_version=3, known_platform_version=2)
        assert result["changed"] is True
        assert result["platform_context_version"] == 5

    def test_get_persona_version_includes_platform_context_version_without_known(self, httpx_mock):
        data = {"version": 3, "platform_context_version": 1}
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/persona/version",
            json=envelope(data),
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            result = c.get_persona_version()
        assert result["platform_context_version"] == 1

    def test_check_persona_version_with_known_platform_version_unchanged(self, httpx_mock):
        data = {"version": 3, "platform_context_version": 2, "changed": False}
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/persona/version?known_version=3&known_platform_version=2",
            json=envelope(data),
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            changed = c.check_persona_version(known_version=3, known_platform_version=2)
        assert changed is False

    def test_check_persona_version_with_known_platform_version_changed(self, httpx_mock):
        data = {"version": 3, "platform_context_version": 5, "changed": True}
        httpx_mock.add_response(
            url=f"{BASE_URL}/api/v1/persona/version?known_version=3&known_platform_version=2",
            json=envelope(data),
        )
        with SuperposClient(BASE_URL, token=TOKEN) as c:
            changed = c.check_persona_version(known_version=3, known_platform_version=2)
        assert changed is True
