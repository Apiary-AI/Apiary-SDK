"""Tests for persona endpoints."""

from __future__ import annotations

import json

from apiary_sdk import ApiaryClient

from .conftest import BASE_URL, TOKEN, envelope


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
        with ApiaryClient(BASE_URL, token=TOKEN) as c:
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
        with ApiaryClient(BASE_URL, token=TOKEN) as c:
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
        with ApiaryClient(BASE_URL, token=TOKEN) as c:
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
        with ApiaryClient(BASE_URL, token=TOKEN) as c:
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
        with ApiaryClient(BASE_URL, token=TOKEN) as c:
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
        with ApiaryClient(BASE_URL, token=TOKEN) as c:
            result = c.update_persona_document("MEMORY", content="Bare update.")
        assert result["version"] == 1
        assert result["document"] == "MEMORY"
        assert result["content"] == "Bare update."
        body = json.loads(httpx_mock.get_request().content)
        assert body["content"] == "Bare update."
        assert "message" not in body
