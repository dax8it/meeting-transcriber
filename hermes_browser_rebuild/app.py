from __future__ import annotations

import asyncio
import json
import math
import os
import re
import subprocess
import textwrap
import wave
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from uuid import uuid4

import httpx
from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel, Field

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
MEETINGS_DIR = DATA_DIR / "meetings"
STATIC_DIR = BASE_DIR / "static"
TEMPLATES_DIR = BASE_DIR / "templates"
DEFAULT_MLX_PYTHON = os.getenv("HERMES_BROWSER_MLX_PYTHON", "/Users/Shared/GITHUB/ios_models/_venvs/mlx/bin/python")
DEFAULT_WHISPER_MEETING_MODEL = os.getenv(
    "HERMES_BROWSER_WHISPER_MEETING_MODEL",
    os.getenv("HERMES_BROWSER_WHISPER_MODEL", "mlx-community/whisper-tiny-asr-fp16"),
)
DEFAULT_WHISPER_VOICE_MODEL = os.getenv(
    "HERMES_BROWSER_WHISPER_VOICE_MODEL",
    "mlx-community/whisper-small",
)
DEFAULT_KOKORO_MODEL = os.getenv("HERMES_BROWSER_KOKORO_MODEL", "prince-canuma/Kokoro-82M")
DEFAULT_KOKORO_FASTAPI_URL = os.getenv("HERMES_BROWSER_KOKORO_FASTAPI_URL", "http://127.0.0.1:8880/v1").strip()
DEFAULT_GEMMA_BASE_URL = os.getenv("HERMES_BROWSER_GEMMA_BASE_URL", "http://127.0.0.1:8082/v1").strip()
DEFAULT_GEMMA_MODEL = os.getenv("HERMES_BROWSER_GEMMA_MODEL", "mlx-community/gemma-4-26b-a4b-it-4bit")
DEFAULT_KOKORO_VOICE = os.getenv("HERMES_BROWSER_KOKORO_VOICE", "af_heart")
DISABLE_MODEL_SUBPROCESS = os.getenv("HERMES_BROWSER_DISABLE_MODEL_SUBPROCESS", "0") == "1"
WORKSPACE_ID = "meeting-prompter-app-test"

for directory in [DATA_DIR, MEETINGS_DIR, STATIC_DIR, TEMPLATES_DIR]:
    directory.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="Hermes Meeting Prompter Browser Rebuild", version="0.1.0")
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
templates = Jinja2Templates(directory=str(TEMPLATES_DIR))
MEETING_EVENT_QUEUES: dict[str, set[asyncio.Queue[str]]] = {}


class StartMeetingRequest(BaseModel):
    title: str | None = None


class AskRequest(BaseModel):
    question: str = Field(min_length=1)
    speak_reply: bool = False


class SpeakRequest(BaseModel):
    text: str = Field(min_length=1)


class MeetingSummary(BaseModel):
    id: str
    title: str
    created_at: str
    updated_at: str
    transcript_present: bool
    summary_present: bool
    transcript_preview: str
    answer_count: int


class MeetingDetail(BaseModel):
    id: str
    workspace: str
    title: str
    created_at: str
    updated_at: str
    live_transcript_preview: str
    raw_transcript: str
    transcript: str
    summary: str
    chat_history: list[dict[str, Any]]
    status: dict[str, str]
    artifact_log: list[dict[str, str]]
    artifact_urls: dict[str, str | None]


class TranscribeResponse(BaseModel):
    meeting: MeetingDetail
    transcript_delta: str
    raw_transcript_delta: str
    provider: str
    mode: str


class LivePreviewResponse(BaseModel):
    meeting: MeetingDetail
    preview_text: str
    provider: str
    mode: str


class AskResponse(BaseModel):
    meeting: MeetingDetail
    answer: str
    sources: list[dict[str, Any]]
    audio_url: str | None = None
    answer_provider: str
    answer_strategy: str
    answer_note: str
    tts_provider: str | None = None


class ModelStatus(BaseModel):
    whisper: str
    gemma: str
    kokoro: str


@app.get("/", response_class=HTMLResponse)
async def index(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "index.html",
        {
            "app_title": "Hermes Meeting Prompter",
            "tailscale_hint": "Open this over Tailscale HTTPS on iPhone for mic permissions.",
        },
    )


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "ok": True,
        "app": "hermes-browser-rebuild",
        "time": utc_now(),
        "models": model_status().dict(),
        "meetings": len(list_meeting_dirs()),
    }


@app.get("/api/config")
def config() -> dict[str, Any]:
    return {
        "tailscale_https_required": True,
        "recommended_flow": [
            "Create meeting",
            "Record meeting audio",
            "Transcribe",
            "Summarize",
            "Ask typed or voice follow-up",
            "Optionally speak answer",
        ],
        "endpoint_map_url": "/static/../docs-endpoint-map",
    }


@app.get("/api/model-status", response_model=ModelStatus)
def api_model_status() -> ModelStatus:
    return model_status()


@app.get("/api/meetings", response_model=list[MeetingSummary])
def get_meetings() -> list[MeetingSummary]:
    return [meeting_summary(load_meeting(meeting_dir)) for meeting_dir in list_meeting_dirs()]


@app.post("/api/meetings/start", response_model=MeetingDetail)
def start_meeting(payload: StartMeetingRequest) -> MeetingDetail:
    meeting = create_meeting(payload.title)
    persist_meeting(meeting)
    return detail_with_urls(meeting)


@app.get("/api/meetings/{meeting_id}", response_model=MeetingDetail)
def get_meeting(meeting_id: str) -> MeetingDetail:
    return detail_with_urls(require_meeting(meeting_id))


@app.get("/api/meetings/{meeting_id}/events")
async def stream_meeting_events(meeting_id: str, request: Request) -> StreamingResponse:
    meeting = require_meeting(meeting_id)
    queue = register_meeting_event_queue(meeting_id)

    async def event_stream() -> Any:
        try:
            yield format_sse_event("snapshot", meeting_event_payload(meeting, event="snapshot"))
            while True:
                if await request.is_disconnected():
                    break
                try:
                    message = await asyncio.wait_for(queue.get(), timeout=15)
                except TimeoutError:
                    yield ": keepalive\n\n"
                    continue
                yield message
        finally:
            unregister_meeting_event_queue(meeting_id, queue)

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@app.post("/api/meetings/{meeting_id}/transcribe", response_model=TranscribeResponse)
async def transcribe_meeting_audio(meeting_id: str, request: Request, mode: str = "meeting") -> TranscribeResponse:
    meeting = require_meeting(meeting_id)
    body = await request.body()
    if not body:
        raise HTTPException(status_code=400, detail="Audio payload is empty")

    if mode not in {"meeting", "voice"}:
        raise HTTPException(status_code=400, detail="mode must be 'meeting' or 'voice'")

    filename = request.headers.get("x-filename") or ("voice-question.webm" if mode == "voice" else "meeting-recording.webm")
    append_artifact_log(meeting, "capture", f"Received {mode} audio artifact: {filename}")
    audio_path = save_audio_blob(meeting_id=meeting_id, filename=filename, body=body, kind=mode)
    raw_transcript, provider = transcribe_audio(audio_path=audio_path, mode=mode)
    cleaned_transcript = sanitize_transcript_text(raw_transcript)

    if mode == "meeting":
        meeting["live_transcript_preview"] = ""
        meeting["raw_transcript"] = merge_transcript(meeting.get("raw_transcript", ""), raw_transcript)
        meeting["transcript"] = merge_transcript(meeting.get("transcript", ""), cleaned_transcript)
        write_text(meeting_file(meeting_id, "raw_transcript.txt"), meeting["raw_transcript"])
        write_text(meeting_file(meeting_id, "transcript.txt"), meeting["transcript"])
        append_artifact_log(meeting, "transcription", f"Transcription completed via {provider}")
        append_artifact_log(meeting, "transcription", "Sanitized transcript artifact updated for on-screen review.")
        if meeting["transcript"].strip():
            summary, summary_provider = summarize_transcript(meeting["transcript"])
            meeting["summary"] = summary
            write_text(meeting_file(meeting_id, "summary.md"), summary)
            meeting["status"]["summary"] = f"ready via {summary_provider}"
            append_artifact_log(meeting, "summary", f"Summary regenerated automatically via {summary_provider}")
        delta = cleaned_transcript
    else:
        append_artifact_log(meeting, "voice_input", f"Voice question transcribed via {provider}")
        delta = cleaned_transcript

    meeting["updated_at"] = utc_now()
    meeting["status"]["transcription"] = f"ready via {provider}"
    persist_meeting(meeting)
    publish_meeting_event(
        meeting_id,
        "transcript_finalized" if mode == "meeting" else "voice_transcribed",
        meeting_event_payload(meeting, event="transcript_finalized" if mode == "meeting" else "voice_transcribed", provider=provider, mode=mode),
    )
    return TranscribeResponse(
        meeting=detail_with_urls(meeting),
        transcript_delta=delta,
        raw_transcript_delta=raw_transcript,
        provider=provider,
        mode=mode,
    )


@app.post("/api/meetings/{meeting_id}/transcribe-preview", response_model=LivePreviewResponse)
async def preview_meeting_audio_transcription(meeting_id: str, request: Request, mode: str = "meeting") -> LivePreviewResponse:
    meeting = require_meeting(meeting_id)
    body = await request.body()
    if not body:
        raise HTTPException(status_code=400, detail="Audio payload is empty")

    if mode != "meeting":
        raise HTTPException(status_code=400, detail="mode must be 'meeting' for live preview")

    filename = request.headers.get("x-filename") or "meeting-preview.webm"
    preview_path = meeting_file(meeting_id, f"preview/{filename}")
    preview_path.parent.mkdir(parents=True, exist_ok=True)
    preview_path.write_bytes(body)
    raw_preview, provider = transcribe_audio(audio_path=preview_path, mode=mode)
    cleaned_preview = sanitize_transcript_text(raw_preview)
    meeting["live_transcript_preview"] = cleaned_preview
    meeting["updated_at"] = utc_now()
    meeting["status"]["transcription"] = f"live preview via {provider}"
    persist_meeting(meeting)
    publish_meeting_event(
        meeting_id,
        "preview",
        meeting_event_payload(meeting, event="preview", preview_text=cleaned_preview, provider=provider, mode=mode),
    )
    return LivePreviewResponse(
        meeting=detail_with_urls(meeting),
        preview_text=cleaned_preview,
        provider=provider,
        mode=mode,
    )


@app.post("/api/meetings/{meeting_id}/summarize", response_model=MeetingDetail)
def summarize_meeting(meeting_id: str) -> MeetingDetail:
    meeting = require_meeting(meeting_id)
    transcript = (meeting.get("transcript") or "").strip()
    if not transcript:
        raise HTTPException(status_code=400, detail="Transcript is empty")

    summary, provider = summarize_transcript(transcript)
    meeting["summary"] = summary
    meeting["updated_at"] = utc_now()
    meeting["status"]["summary"] = f"ready via {provider}"
    write_text(meeting_file(meeting_id, "summary.md"), summary)
    append_artifact_log(meeting, "summary", f"Summary generated on demand via {provider}")
    persist_meeting(meeting)
    return detail_with_urls(meeting)


@app.post("/api/meetings/{meeting_id}/ask", response_model=AskResponse)
def ask_meeting(meeting_id: str, payload: AskRequest) -> AskResponse:
    meeting = require_meeting(meeting_id)
    answer, sources, provider, strategy, note = answer_question(
        question=payload.question,
        transcript=meeting.get("transcript", ""),
        summary=meeting.get("summary", ""),
        chat_history=meeting.get("chat_history", []),
    )
    audio_url = None
    tts_provider = None
    if payload.speak_reply:
        audio_url, tts_provider = speak_answer(meeting_id=meeting_id, text=answer)

    meeting["chat_history"].append(
        {
            "id": str(uuid4()),
            "question": payload.question,
            "answer": answer,
            "sources": sources,
            "answer_provider": provider,
            "answer_strategy": strategy,
            "answer_note": note,
            "created_at": utc_now(),
            "audio_url": audio_url,
        }
    )
    meeting["updated_at"] = utc_now()
    meeting["status"]["qa"] = qa_status_label(provider=provider, strategy=strategy)
    append_artifact_log(meeting, "qa", f"Question answered via {provider}. {note}")
    if payload.speak_reply:
        meeting["status"]["tts"] = tts_provider or "unavailable"
        append_artifact_log(meeting, "tts", f"Spoken reply attempted via {tts_provider or 'unavailable'}")
    persist_meeting(meeting)
    publish_meeting_event(
        meeting_id,
        "answer",
        meeting_event_payload(
            meeting,
            event="answer",
            answer=answer,
            sources=sources,
            audio_url=audio_url,
            answer_provider=provider,
            answer_strategy=strategy,
            answer_note=note,
            tts_provider=tts_provider,
        ),
    )
    return AskResponse(
        meeting=detail_with_urls(meeting),
        answer=answer,
        sources=sources,
        audio_url=audio_url,
        answer_provider=provider,
        answer_strategy=strategy,
        answer_note=note,
        tts_provider=tts_provider,
    )


@app.post("/api/meetings/{meeting_id}/voice-question", response_model=AskResponse)
async def ask_meeting_by_voice(meeting_id: str, request: Request, speak_reply: bool = True) -> AskResponse:
    meeting = require_meeting(meeting_id)
    body = await request.body()
    if not body:
        raise HTTPException(status_code=400, detail="Audio payload is empty")
    filename = request.headers.get("x-filename") or "voice-question.webm"
    append_artifact_log(meeting, "capture", f"Received voice question artifact: {filename}")
    audio_path = save_audio_blob(meeting_id=meeting_id, filename=filename, body=body, kind="voice")
    raw_question, asr_provider = transcribe_audio(audio_path=audio_path, mode="voice")
    question = sanitize_transcript_text(raw_question).strip()
    if not question:
        raise HTTPException(status_code=422, detail="Voice question could not be transcribed")

    meeting["status"]["voice_input"] = f"transcribed via {asr_provider}"
    append_artifact_log(meeting, "voice_input", f"Voice question transcribed via {asr_provider}")
    meeting["updated_at"] = utc_now()
    persist_meeting(meeting)

    ask_response = ask_meeting(meeting_id, AskRequest(question=question, speak_reply=speak_reply))
    return ask_response


@app.post("/api/meetings/{meeting_id}/speak")
def speak_meeting_text(meeting_id: str, payload: SpeakRequest) -> dict[str, Any]:
    require_meeting(meeting_id)
    audio_url, provider = speak_answer(meeting_id=meeting_id, text=payload.text)
    if not audio_url:
        raise HTTPException(status_code=503, detail="TTS unavailable")
    return {"audio_url": audio_url, "provider": provider}


@app.get("/media/{meeting_id}/{asset_path:path}")
def get_media(meeting_id: str, asset_path: str) -> FileResponse:
    path = meeting_dir(meeting_id) / asset_path
    if not path.exists() or not path.is_file():
        raise HTTPException(status_code=404, detail="Media file not found")
    return FileResponse(path)


@app.get("/docs-endpoint-map")
def endpoint_map() -> Response:
    map_path = BASE_DIR.parent / "docs" / "2026-04-14-hermes-browser-endpoint-map.md"
    return FileResponse(map_path)


def utc_now() -> str:
    return datetime.now(UTC).isoformat()


def slugify(value: str | None) -> str:
    if not value:
        return "meeting"
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug or "meeting"


def list_meeting_dirs() -> list[Path]:
    return sorted(
        [path for path in MEETINGS_DIR.iterdir() if path.is_dir()],
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )


def meeting_dir(meeting_id: str) -> Path:
    return MEETINGS_DIR / meeting_id


def meeting_file(meeting_id: str, relative_name: str) -> Path:
    path = meeting_dir(meeting_id) / relative_name
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def meeting_json_path(meeting_id: str) -> Path:
    return meeting_file(meeting_id, "meeting.json")


def create_meeting(title: str | None) -> dict[str, Any]:
    created_at = utc_now()
    title_text = (title or "").strip() or "Untitled meeting"
    meeting_id = f"meeting-{datetime.now(UTC).strftime('%Y%m%d-%H%M%S')}-{slugify(title_text)[:24]}-{uuid4().hex[:6]}"
    directory = meeting_dir(meeting_id)
    directory.mkdir(parents=True, exist_ok=True)
    voice_dir = directory / "voice"
    voice_dir.mkdir(exist_ok=True)
    return {
        "id": meeting_id,
        "workspace": WORKSPACE_ID,
        "title": title_text,
        "created_at": created_at,
        "updated_at": created_at,
        "live_transcript_preview": "",
        "raw_transcript": "",
        "transcript": "",
        "summary": "",
        "chat_history": [],
        "status": {
            "transcription": "idle",
            "summary": "idle",
            "qa": "idle",
            "tts": "idle",
        },
        "artifact_log": [
            {
                "time": created_at,
                "stage": "workspace",
                "level": "info",
                "message": "App test meeting workspace created.",
            }
        ],
        "artifacts": {
            "meeting_audio": None,
            "raw_transcript": "raw_transcript.txt",
            "transcript": "transcript.txt",
            "summary": "summary.md",
            "voice_dir": "voice",
        },
    }


def require_meeting(meeting_id: str) -> dict[str, Any]:
    path = meeting_json_path(meeting_id)
    if not path.exists():
        raise HTTPException(status_code=404, detail="Meeting not found")
    return load_meeting(meeting_dir(meeting_id))


def load_meeting(directory: Path) -> dict[str, Any]:
    return json.loads((directory / "meeting.json").read_text())


def persist_meeting(meeting: dict[str, Any]) -> None:
    meeting_json_path(meeting["id"]).write_text(json.dumps(meeting, indent=2))


def write_text(path: Path, text: str) -> None:
    path.write_text(text)


def append_artifact_log(meeting: dict[str, Any], stage: str, message: str, level: str = "info") -> None:
    meeting.setdefault("artifact_log", []).append(
        {
            "time": utc_now(),
            "stage": stage,
            "level": level,
            "message": message,
        }
    )


def detail_with_urls(meeting: dict[str, Any]) -> MeetingDetail:
    meeting_id = meeting["id"]
    artifacts = meeting.get("artifacts", {})
    voice_files = sorted((meeting_dir(meeting_id) / "voice").glob("*.wav"), reverse=True)
    artifact_urls = {
        "meeting_audio": media_url(meeting_id, artifacts.get("meeting_audio")),
        "raw_transcript": media_url(meeting_id, artifacts.get("raw_transcript")),
        "transcript": media_url(meeting_id, artifacts.get("transcript")),
        "summary": media_url(meeting_id, artifacts.get("summary")),
        "latest_voice_reply": media_url(meeting_id, f"voice/{voice_files[0].name}") if voice_files else None,
    }
    return MeetingDetail(
        id=meeting_id,
        workspace=meeting.get("workspace", WORKSPACE_ID),
        title=meeting["title"],
        created_at=meeting["created_at"],
        updated_at=meeting["updated_at"],
        live_transcript_preview=meeting.get("live_transcript_preview", ""),
        raw_transcript=meeting.get("raw_transcript", ""),
        transcript=meeting.get("transcript", ""),
        summary=meeting.get("summary", ""),
        chat_history=meeting.get("chat_history", []),
        status=meeting.get("status", {}),
        artifact_log=meeting.get("artifact_log", []),
        artifact_urls=artifact_urls,
    )


def meeting_event_payload(meeting: dict[str, Any], **extra: Any) -> dict[str, Any]:
    payload = {"meeting": detail_with_urls(meeting).dict()}
    payload.update(extra)
    return payload


def register_meeting_event_queue(meeting_id: str) -> asyncio.Queue[str]:
    queue: asyncio.Queue[str] = asyncio.Queue()
    MEETING_EVENT_QUEUES.setdefault(meeting_id, set()).add(queue)
    return queue


def unregister_meeting_event_queue(meeting_id: str, queue: asyncio.Queue[str]) -> None:
    queues = MEETING_EVENT_QUEUES.get(meeting_id)
    if not queues:
        return
    queues.discard(queue)
    if not queues:
        MEETING_EVENT_QUEUES.pop(meeting_id, None)


def format_sse_event(event: str, payload: dict[str, Any]) -> str:
    return f"event: {event}\ndata: {json.dumps(payload)}\n\n"


def publish_meeting_event(meeting_id: str, event: str, payload: dict[str, Any]) -> None:
    message = format_sse_event(event, payload)
    for queue in list(MEETING_EVENT_QUEUES.get(meeting_id, set())):
        try:
            queue.put_nowait(message)
        except asyncio.QueueFull:
            pass


def meeting_summary(meeting: dict[str, Any]) -> MeetingSummary:
    transcript = meeting.get("transcript", "")
    return MeetingSummary(
        id=meeting["id"],
        title=meeting["title"],
        created_at=meeting["created_at"],
        updated_at=meeting["updated_at"],
        transcript_present=bool(transcript.strip()),
        summary_present=bool((meeting.get("summary") or "").strip()),
        transcript_preview=preview_text(transcript or meeting.get("live_transcript_preview", "")),
        answer_count=len(meeting.get("chat_history", [])),
    )


def preview_text(text: str, limit: int = 120) -> str:
    compact = " ".join(text.split())
    if len(compact) <= limit:
        return compact
    return compact[: limit - 1].rstrip() + "…"


def media_url(meeting_id: str, relative_path: str | None) -> str | None:
    if not relative_path:
        return None
    return f"/media/{meeting_id}/{relative_path}"


def save_audio_blob(meeting_id: str, filename: str, body: bytes, kind: str) -> Path:
    clean_name = Path(filename).name or ("audio.webm")
    if kind == "meeting":
        target = meeting_file(meeting_id, clean_name)
        relative = clean_name
        meeting = require_meeting(meeting_id)
        meeting["artifacts"]["meeting_audio"] = relative
        persist_meeting(meeting)
    else:
        target = meeting_file(meeting_id, f"voice/{datetime.now(UTC).strftime('%H%M%S')}-{clean_name}")
    target.write_bytes(body)
    return target


def merge_transcript(existing: str, incoming: str) -> str:
    if not existing.strip():
        return incoming.strip()
    if not incoming.strip():
        return existing.strip()
    return (existing.strip() + "\n\n" + incoming.strip()).strip()


def sanitize_transcript_text(text: str) -> str:
    compact = " ".join((text or "").split()).strip()
    if not compact:
        return ""

    compact = re.sub(r'(?:\s*[.]){4,}\s*$', '', compact).strip()
    compact = re.sub(r'\b([a-zA-Z])(?:\s+\1){4,}\b', r'\1', compact, flags=re.IGNORECASE)

    tokens = compact.split()
    collapsed: list[str] = []
    previous_norm = None
    run_count = 0
    for token in tokens:
        normalized = re.sub(r'[^a-z0-9]+', '', token.lower())
        if normalized and normalized == previous_norm:
            run_count += 1
        else:
            previous_norm = normalized
            run_count = 1

        limit = 1 if len(normalized) <= 2 else 2
        if run_count <= limit:
            collapsed.append(token)

    compact = " ".join(collapsed).strip()
    compact = re.sub(r'(?:\b(?:o|oh|uh|um|into)\b\s*){4,}$', '', compact, flags=re.IGNORECASE).strip()
    compact = re.sub(r'\s+([.,!?;:])', r'\1', compact)
    return compact or text.strip()


def transcribe_audio(audio_path: Path, mode: str) -> tuple[str, str]:
    whisper_model = whisper_model_for_mode(mode)
    if not DISABLE_MODEL_SUBPROCESS and Path(DEFAULT_MLX_PYTHON).exists():
        try:
            prepared_audio_path = prepare_audio_for_whisper(audio_path)
            script = textwrap.dedent(
                f"""
                import json, re
                from mlx_audio.stt import load
                model = load({whisper_model!r})
                result = model.generate({str(prepared_audio_path)!r}, word_timestamps=False)
                text = getattr(result, 'text', '') or ''
                text = re.sub(r'(?:\s*[.]){4,}\s*$', '', text).strip()
                print(json.dumps({{'text': text}}))
                """
            )
            completed = subprocess.run(
                [DEFAULT_MLX_PYTHON, "-c", script],
                check=True,
                capture_output=True,
                text=True,
                timeout=600,
            )
            data = json.loads(completed.stdout.strip() or "{}")
            text = (data.get("text") or "").strip()
            if text:
                return text, f"whisper-mlx:{whisper_model}"
        except Exception:
            pass

    fallback = (
        "Voice question captured. Whisper MLX is not wired yet for this runtime, so this fallback text is standing in for the transcribed question."
        if mode == "voice"
        else "Meeting audio captured. Whisper MLX is not wired yet for this runtime, so this fallback text is standing in for the meeting transcript."
    )
    return fallback, "fallback"


def prepare_audio_for_whisper(audio_path: Path) -> Path:
    normalized = audio_path.with_suffix('.whisper.wav')
    subprocess.run(
        [
            'ffmpeg',
            '-y',
            '-i',
            str(audio_path),
            '-ac',
            '1',
            '-ar',
            '16000',
            str(normalized),
        ],
        check=True,
        capture_output=True,
        text=True,
        timeout=120,
    )
    return normalized


def whisper_model_for_mode(mode: str) -> str:
    if mode == "voice":
        return DEFAULT_WHISPER_VOICE_MODEL
    return DEFAULT_WHISPER_MEETING_MODEL


def summarize_transcript(transcript: str) -> tuple[str, str]:
    transcript = transcript.strip()
    if DEFAULT_GEMMA_BASE_URL and DEFAULT_GEMMA_MODEL:
        try:
            prompt = (
                "Summarize this meeting in markdown with sections for Title, Key points, Decisions, Action items, and Open questions.\n\n"
                + transcript
            )
            summary = call_gemma(prompt)
            if summary.strip():
                return summary.strip(), f"gemma:{DEFAULT_GEMMA_MODEL}"
        except Exception:
            pass

    lines = [line.strip("-• ") for line in transcript.splitlines() if line.strip()]
    key_points = lines[:5] or [preview_text(transcript, 180)]
    decisions = lines[5:7] or ["No explicit decisions detected in fallback summarizer."]
    actions = lines[7:10] or ["Review transcript and mark action items manually."]
    summary = [
        f"# {infer_title(transcript)}",
        "",
        "## Key points",
        *[f"- {point}" for point in key_points],
        "",
        "## Decisions",
        *[f"- {item}" for item in decisions],
        "",
        "## Action items",
        *[f"- {item}" for item in actions],
        "",
        "## Open questions",
        "- What should be clarified from the transcript before follow-up sharing?",
    ]
    return "\n".join(summary).strip(), "fallback"


def infer_title(transcript: str) -> str:
    sentence = preview_text(transcript.replace("\n", " "), 60).strip(". ")
    return sentence or "Meeting summary"


def answer_question(
    question: str,
    transcript: str,
    summary: str,
    chat_history: list[dict[str, Any]] | None = None,
) -> tuple[str, list[dict[str, Any]], str, str, str]:
    chat_history = chat_history or []
    sources = retrieve_sources(question=question, transcript=transcript, summary=summary, chat_history=chat_history)
    conversation_context = build_conversation_context(chat_history)
    gemma_sources_error: str | None = None
    if DEFAULT_GEMMA_BASE_URL and DEFAULT_GEMMA_MODEL and sources:
        try:
            source_block = "\n\n".join(
                f"[{source['source_id']}] {source['title']}\n{source['excerpt']}" for source in sources
            )
            prompt = (
                "Answer only using the supplied sources. Keep it concise and say 'Not enough evidence in sources.' if the sources do not support the answer.\n\n"
                + (f"RECENT CONVERSATION:\n{conversation_context}\n\n" if conversation_context else "")
                + f"SOURCES:\n{source_block}\n\nQUESTION:\n{question}"
            )
            answer = call_gemma(prompt)
            if answer.strip():
                return (
                    answer.strip(),
                    sources,
                    f"gemma:{DEFAULT_GEMMA_MODEL}",
                    "grounded_sources",
                    "Gemma answered from retrieved meeting sources.",
                )
        except Exception as exc:
            gemma_sources_error = f"Gemma source-grounded answer failed ({exc.__class__.__name__})."

    if sources:
        opening = f"Based on this meeting, {sources[0]['excerpt']}"
        if len(sources) > 1:
            follow = f" The strongest supporting detail is: {sources[1]['excerpt']}"
        else:
            follow = ""
        answer = opening + follow
        note = gemma_sources_error or "Gemma was not used; the app stitched together retrieved excerpts locally."
        return answer.strip(), sources, "local-fallback:retrieved-sources", "local_fallback_sources", note

    gemma_context_error: str | None = None
    meeting_context = build_meeting_context(summary=summary, transcript=transcript, chat_history=chat_history)
    if DEFAULT_GEMMA_BASE_URL and DEFAULT_GEMMA_MODEL and meeting_context.strip():
        try:
            prompt = (
                "Lexical retrieval found no direct source match for this meeting question. "
                "Use the meeting context below to answer as helpfully as possible. "
                "If the answer is still unsupported, say 'Not enough evidence in meeting context.'\n\n"
                f"MEETING CONTEXT:\n{meeting_context}\n\nQUESTION:\n{question}"
            )
            answer = call_gemma(prompt)
            if answer.strip():
                return (
                    answer.strip(),
                    [],
                    f"gemma:{DEFAULT_GEMMA_MODEL}",
                    "gemma_meeting_context_fallback",
                    "No direct lexical source match; Gemma answered from meeting transcript/summary context instead.",
                )
        except Exception as exc:
            gemma_context_error = f"Gemma meeting-context fallback failed ({exc.__class__.__name__})."

    note = gemma_context_error or (
        "Gemma was not used because retrieval found no direct lexical source match and no meeting-context fallback answer was available."
    )
    return "Not enough evidence in sources.", [], "local-fallback:no-sources", "local_fallback_no_sources", note


def build_meeting_context(
    summary: str,
    transcript: str,
    chat_history: list[dict[str, Any]] | None = None,
    transcript_limit: int = 4000,
) -> str:
    blocks: list[str] = []
    summary = summary.strip()
    transcript = transcript.strip()
    if chat_history:
        conversation_context = build_conversation_context(chat_history)
        if conversation_context:
            blocks.append(f"RECENT CONVERSATION:\n{conversation_context}")
    if summary:
        blocks.append(f"SUMMARY:\n{summary}")
    if transcript:
        transcript_excerpt = transcript[:transcript_limit].strip()
        if len(transcript) > transcript_limit:
            transcript_excerpt += "\n...[truncated]"
        blocks.append(f"TRANSCRIPT EXCERPT:\n{transcript_excerpt}")
    return "\n\n".join(blocks).strip()


def build_conversation_context(chat_history: list[dict[str, Any]] | None, turns: int = 4) -> str:
    if not chat_history:
        return ""
    lines: list[str] = []
    for entry in chat_history[-turns:]:
        question = (entry.get("question") or "").strip()
        answer = (entry.get("answer") or "").strip()
        if question:
            lines.append(f"User: {question}")
        if answer:
            lines.append(f"Assistant: {answer}")
    return "\n".join(lines).strip()


def qa_status_label(provider: str, strategy: str) -> str:
    strategy_labels = {
        "grounded_sources": "grounded source answer",
        "gemma_meeting_context_fallback": "Gemma meeting-context fallback after retrieval miss",
        "local_fallback_sources": "local retrieved-source fallback",
        "local_fallback_no_sources": "Gemma skipped; no lexical source match",
    }
    return f"{strategy_labels.get(strategy, strategy)} via {provider}"


def retrieve_sources(
    question: str,
    transcript: str,
    summary: str,
    chat_history: list[dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    query_tokens = token_set(contextual_query_text(question, chat_history))
    chunks: list[tuple[str, str]] = []
    chunks.extend(("Transcript", chunk) for chunk in chunk_text(transcript))
    chunks.extend(("Summary", chunk) for chunk in chunk_text(summary))
    scored: list[tuple[int, int, str, str]] = []
    for idx, (title, chunk) in enumerate(chunks, start=1):
        score = len(query_tokens & token_set(chunk))
        if score > 0:
            scored.append((score, idx, title, chunk))
    scored.sort(key=lambda item: (-item[0], item[1]))
    output = []
    for rank, (_, idx, title, excerpt) in enumerate(scored[:3], start=1):
        output.append(
            {
                "source_id": f"S{rank}",
                "title": title,
                "chunk_index": idx,
                "excerpt": excerpt,
            }
        )
    return output


def contextual_query_text(question: str, chat_history: list[dict[str, Any]] | None, turns: int = 2) -> str:
    pieces = [question.strip()]
    if chat_history:
        for entry in chat_history[-turns:]:
            if entry.get("question"):
                pieces.append(str(entry["question"]).strip())
            if entry.get("answer"):
                pieces.append(str(entry["answer"]).strip())
    return " ".join(piece for piece in pieces if piece)


def token_set(text: str) -> set[str]:
    return {token for token in re.findall(r"[a-zA-Z0-9]+", text.lower()) if len(token) > 2}


def chunk_text(text: str, max_chars: int = 280) -> list[str]:
    cleaned = [line.strip() for line in text.splitlines() if line.strip()]
    if not cleaned:
        return []
    chunks: list[str] = []
    current = ""
    for line in cleaned:
        candidate = f"{current} {line}".strip()
        if len(candidate) <= max_chars:
            current = candidate
        else:
            if current:
                chunks.append(current)
            current = line
    if current:
        chunks.append(current)
    return chunks


def call_gemma(prompt: str) -> str:
    base_url = DEFAULT_GEMMA_BASE_URL.rstrip("/")
    url = f"{base_url}/chat/completions"
    if not base_url.endswith("/v1"):
        url = f"{base_url}/v1/chat/completions"
    payload = {
        "model": DEFAULT_GEMMA_MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "stream": False,
    }
    with httpx.Client(timeout=120.0) as client:
        response = client.post(url, json=payload)
        response.raise_for_status()
        body = response.json()
    return (
        body.get("choices", [{}])[0]
        .get("message", {})
        .get("content", "")
        .strip()
    )


def speak_answer(meeting_id: str, text: str) -> tuple[str | None, str | None]:
    out_path = meeting_file(meeting_id, f"voice/{datetime.now(UTC).strftime('%H%M%S')}-{uuid4().hex[:6]}.wav")
    if not DISABLE_MODEL_SUBPROCESS and Path(DEFAULT_MLX_PYTHON).exists() and kokoro_dependency_check():
        try:
            script = textwrap.dedent(
                f"""
                import json
                import wave
                import numpy as np
                from mlx_audio.tts import load

                model = load({DEFAULT_KOKORO_MODEL!r})
                chunks = list(model.generate({text!r}, voice={DEFAULT_KOKORO_VOICE!r}, speed=1.0))
                if not chunks:
                    raise RuntimeError('No audio generated')
                audio = chunks[0].audio
                if hasattr(audio, 'tolist'):
                    samples = np.array(audio.tolist(), dtype=np.float32)
                else:
                    samples = np.array(audio, dtype=np.float32)
                samples = np.clip(samples, -1.0, 1.0)
                pcm = (samples * 32767).astype(np.int16)
                with wave.open({str(out_path)!r}, 'wb') as wav:
                    wav.setnchannels(1)
                    wav.setsampwidth(2)
                    wav.setframerate(int(chunks[0].sample_rate))
                    wav.writeframes(pcm.tobytes())
                print(json.dumps({{'ok': True}}))
                """
            )
            subprocess.run(
                [DEFAULT_MLX_PYTHON, "-c", script],
                check=True,
                capture_output=True,
                text=True,
                timeout=600,
            )
            return media_url(meeting_id, f"voice/{out_path.name}"), f"kokoro-mlx:{DEFAULT_KOKORO_MODEL}"
        except Exception:
            pass

    if kokoro_fastapi_available():
        try:
            base_url = DEFAULT_KOKORO_FASTAPI_URL.rstrip('/')
            url = f"{base_url}/audio/speech" if base_url.endswith('/v1') else f"{base_url}/v1/audio/speech"
            response = httpx.post(
                url,
                json={
                    "model": "kokoro",
                    "input": text,
                    "voice": DEFAULT_KOKORO_VOICE,
                    "response_format": "wav",
                    "speed": 1.0,
                },
                timeout=120.0,
            )
            response.raise_for_status()
            out_path.write_bytes(response.content)
            return media_url(meeting_id, f"voice/{out_path.name}"), f"kokoro-fastapi:{DEFAULT_KOKORO_FASTAPI_URL}"
        except Exception:
            return None, "unavailable"

    return None, "unavailable"


def kokoro_dependency_check() -> bool:
    try:
        completed = subprocess.run(
            [
                DEFAULT_MLX_PYTHON,
                "-c",
                "import importlib.util as u; print(int(all(u.find_spec(m) for m in ['misaki','num2words','spacy'])))",
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=30,
        )
        return completed.stdout.strip() == "1"
    except Exception:
        return False


def gemma_available() -> bool:
    if not (DEFAULT_GEMMA_BASE_URL and DEFAULT_GEMMA_MODEL):
        return False
    try:
        base_url = DEFAULT_GEMMA_BASE_URL.rstrip('/')
        url = f"{base_url}/models" if base_url.endswith('/v1') else f"{base_url}/v1/models"
        response = httpx.get(url, timeout=5.0)
        response.raise_for_status()
        payload = response.json()
        names = [item.get('id') for item in payload.get('data', []) if isinstance(item, dict)]
        return DEFAULT_GEMMA_MODEL in names
    except Exception:
        return False


def kokoro_fastapi_available() -> bool:
    if not DEFAULT_KOKORO_FASTAPI_URL:
        return False
    try:
        base_url = DEFAULT_KOKORO_FASTAPI_URL.rstrip('/')
        url = f"{base_url}/audio/voices" if base_url.endswith('/v1') else f"{base_url}/v1/audio/voices"
        response = httpx.get(url, timeout=5.0)
        response.raise_for_status()
        return True
    except Exception:
        return False


def model_status() -> ModelStatus:
    whisper = "fallback"
    kokoro = "unavailable"
    if not DISABLE_MODEL_SUBPROCESS and Path(DEFAULT_MLX_PYTHON).exists():
        if DEFAULT_WHISPER_MEETING_MODEL == DEFAULT_WHISPER_VOICE_MODEL:
            whisper = f"whisper-mlx configured ({DEFAULT_WHISPER_MEETING_MODEL})"
        else:
            whisper = (
                "whisper-mlx configured "
                f"(meeting={DEFAULT_WHISPER_MEETING_MODEL}; voice={DEFAULT_WHISPER_VOICE_MODEL})"
            )
        if kokoro_dependency_check():
            kokoro = f"kokoro-mlx configured ({DEFAULT_KOKORO_MODEL})"
        elif kokoro_fastapi_available():
            kokoro = f"kokoro-fastapi configured ({DEFAULT_KOKORO_FASTAPI_URL})"
        else:
            kokoro = "unavailable (missing Kokoro runtime deps in MLX venv and no Kokoro FastAPI detected)"
    gemma = "fallback"
    if DEFAULT_GEMMA_BASE_URL and DEFAULT_GEMMA_MODEL:
        gemma = f"gemma configured ({DEFAULT_GEMMA_MODEL})" if gemma_available() else "fallback (Gemma endpoint unreachable)"
    return ModelStatus(whisper=whisper, gemma=gemma, kokoro=kokoro)
