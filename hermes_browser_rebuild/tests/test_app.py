import os
from pathlib import Path

os.environ.setdefault("HERMES_BROWSER_DISABLE_MODEL_SUBPROCESS", "1")
os.environ.setdefault("HERMES_BROWSER_GEMMA_BASE_URL", "")
os.environ.setdefault("HERMES_BROWSER_GEMMA_MODEL", "")

from fastapi.testclient import TestClient

import hermes_browser_rebuild.app as app_module
from hermes_browser_rebuild.app import app, DATA_DIR, WORKSPACE_ID, sanitize_transcript_text

client = TestClient(app)


def cleanup_meetings() -> None:
    meetings_dir = DATA_DIR / "meetings"
    for item in meetings_dir.iterdir():
        if item.name == ".gitkeep":
            continue
        if item.is_dir():
            for sub in sorted(item.rglob("*"), reverse=True):
                if sub.is_file():
                    sub.unlink()
                elif sub.is_dir():
                    sub.rmdir()
            item.rmdir()
        elif item.is_file():
            item.unlink()


def setup_function() -> None:
    cleanup_meetings()


def test_health_endpoint() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["app"] == "hermes-browser-rebuild"


def test_create_meeting_and_fetch_detail() -> None:
    created = client.post("/api/meetings/start", json={"title": "Browser rebuild demo"})
    assert created.status_code == 200
    body = created.json()
    assert body["title"] == "Browser rebuild demo"
    assert body["workspace"] == WORKSPACE_ID

    fetched = client.get(f"/api/meetings/{body['id']}")
    assert fetched.status_code == 200
    detail = fetched.json()
    assert detail["id"] == body["id"]
    assert detail["status"]["transcription"] == "idle"
    assert detail["artifact_log"]


def test_sanitize_transcript_text_collapses_loops() -> None:
    noisy = "And o o o o o o o and into into into into . . . ."
    cleaned = sanitize_transcript_text(noisy)
    assert "o o o" not in cleaned
    assert "into into into" not in cleaned


def test_transcribe_summarize_and_ask_flow() -> None:
    meeting = client.post("/api/meetings/start", json={"title": "Weekly planning"}).json()
    meeting_id = meeting["id"]

    transcribed = client.post(
        f"/api/meetings/{meeting_id}/transcribe?mode=meeting",
        content=b"fake-audio-bytes",
        headers={"content-type": "audio/webm", "x-filename": "weekly.webm"},
    )
    assert transcribed.status_code == 200
    transcribed_body = transcribed.json()
    assert transcribed_body["mode"] == "meeting"
    assert transcribed_body["meeting"]["transcript"]
    assert transcribed_body["meeting"]["raw_transcript"]
    assert transcribed_body["raw_transcript_delta"]
    assert transcribed_body["meeting"]["summary"]
    assert transcribed_body["meeting"]["artifact_log"]

    summarized = client.post(f"/api/meetings/{meeting_id}/summarize")
    assert summarized.status_code == 200
    assert summarized.json()["summary"]

    answered = client.post(
        f"/api/meetings/{meeting_id}/ask",
        json={"question": "What happened in this meeting?", "speak_reply": False},
    )
    assert answered.status_code == 200
    answer_body = answered.json()
    assert answer_body["answer"]
    assert answer_body["answer_provider"]
    assert answer_body["answer_strategy"]
    assert answer_body["answer_note"]
    assert answer_body["meeting"]["chat_history"]


def test_live_transcription_preview_updates_preview_without_finalizing_artifacts() -> None:
    meeting = client.post("/api/meetings/start", json={"title": "Live preview demo"}).json()
    meeting_id = meeting["id"]

    previewed = client.post(
        f"/api/meetings/{meeting_id}/transcribe-preview?mode=meeting",
        content=b"fake-audio-bytes",
        headers={"content-type": "audio/webm", "x-filename": "live-preview.webm"},
    )
    assert previewed.status_code == 200
    body = previewed.json()
    assert body["preview_text"]
    assert body["meeting"]["live_transcript_preview"]
    assert body["meeting"]["transcript"] == ""
    assert "live preview" in body["meeting"]["status"]["transcription"].lower()


def test_format_sse_event_contains_named_event_and_payload() -> None:
    message = app_module.format_sse_event("snapshot", {"meeting": {"id": "demo"}})

    assert "event: snapshot" in message
    assert '"id": "demo"' in message
    assert message.endswith("\n\n")


def test_answer_question_uses_gemma_meeting_context_fallback_when_retrieval_misses(monkeypatch) -> None:
    monkeypatch.setattr(app_module, "DEFAULT_GEMMA_BASE_URL", "http://fake-gemma.local/v1")
    monkeypatch.setattr(app_module, "DEFAULT_GEMMA_MODEL", "mlx-community/gemma-4-26b-a4b-it-4bit")
    monkeypatch.setattr(app_module, "call_gemma", lambda prompt: "The launch is on Tuesday.")

    answer, sources, provider, strategy, note = app_module.answer_question(
        question="When is go-live?",
        transcript="The launch is approved for Tuesday afternoon.",
        summary="Launch timing was approved and the team will execute next week.",
    )

    assert answer == "The launch is on Tuesday."
    assert sources == []
    assert provider == "gemma:mlx-community/gemma-4-26b-a4b-it-4bit"
    assert strategy == "gemma_meeting_context_fallback"
    assert "no direct lexical source match" in note.lower()


def test_answer_question_uses_recent_chat_history_for_follow_up_retrieval(monkeypatch) -> None:
    monkeypatch.setattr(app_module, "DEFAULT_GEMMA_BASE_URL", "")
    monkeypatch.setattr(app_module, "DEFAULT_GEMMA_MODEL", "")

    answer, sources, provider, strategy, note = app_module.answer_question(
        question="What about that timeline?",
        transcript="The launch date is Tuesday afternoon and the team will ship right after QA.",
        summary="",
        chat_history=[{"question": "When is the launch date?", "answer": "Tuesday afternoon."}],
    )

    assert answer
    assert sources
    assert provider == "local-fallback:retrieved-sources"
    assert strategy == "local_fallback_sources"
    assert "retrieved excerpts" in note.lower()


def test_answer_question_reports_explicit_local_fallback_when_no_sources_and_no_gemma(monkeypatch) -> None:
    monkeypatch.setattr(app_module, "DEFAULT_GEMMA_BASE_URL", "")
    monkeypatch.setattr(app_module, "DEFAULT_GEMMA_MODEL", "")

    answer, sources, provider, strategy, note = app_module.answer_question(
        question="When is go-live?",
        transcript="The launch is approved for Tuesday afternoon.",
        summary="Launch timing was approved and the team will execute next week.",
    )

    assert answer == "Not enough evidence in sources."
    assert sources == []
    assert provider == "local-fallback:no-sources"
    assert strategy == "local_fallback_no_sources"
    assert "gemma was not used" in note.lower()
