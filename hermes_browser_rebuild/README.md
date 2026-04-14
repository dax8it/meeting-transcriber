# Hermes Browser Rebuild Working Copy

This is a separate browser-hosted working copy for the Meeting Prompter app.
It does not modify the iOS app code.

What it includes now:
- local FastAPI app
- tabbed browser UI: Overview, Capture, Transcript, Summary, Talk, Artifacts
- live transcript preview during recording
- server-sent events stream for reactive UI updates
- multi-turn typed + voice conversation scoped to a single meeting
- hands-free voice mode with browser-side silence auto-stop
- reactive Kokoro answer playback visualization
- file-backed meeting sessions under `hermes_browser_rebuild/data/meetings/`
- endpoint map matching the current app workflow
- optional MLX adapter hooks for Whisper and Kokoro
- optional local Gemma-compatible chat endpoint hook for summary/Q&A

## Run

Use the included runner so you do not accidentally pick up some unrelated `uvicorn` on your PATH:

```bash
cd /Users/Shared/GITHUB/meeting-prompter-ios/meeting-transcriber
./hermes_browser_rebuild/run_local.sh
```

If you want the explicit manual version:

```bash
cd /Users/Shared/GITHUB/meeting-prompter-ios/meeting-transcriber
python3 -m venv hermes_browser_rebuild/.venv
source hermes_browser_rebuild/.venv/bin/activate
python -m pip install -r hermes_browser_rebuild/requirements.txt
python -m uvicorn hermes_browser_rebuild.app:app --host 127.0.0.1 --port 8792
```

Then open:
- local: `http://127.0.0.1:8792/`
- iPhone over tailnet HTTPS after `tailscale serve --bg 8792`

## Optional model wiring

Environment variables:

```bash
export HERMES_BROWSER_MLX_PYTHON=/Users/Shared/GITHUB/ios_models/_venvs/mlx/bin/python
export HERMES_BROWSER_WHISPER_MEETING_MODEL=mlx-community/whisper-tiny-asr-fp16
export HERMES_BROWSER_WHISPER_VOICE_MODEL=mlx-community/whisper-small
export HERMES_BROWSER_KOKORO_MODEL=prince-canuma/Kokoro-82M
export HERMES_BROWSER_KOKORO_VOICE=af_heart
export HERMES_BROWSER_GEMMA_BASE_URL=http://127.0.0.1:8082/v1
export HERMES_BROWSER_GEMMA_MODEL=mlx-community/gemma-4-26b-a4b-it-4bit
```

Current default assumptions in this working copy:
- Gemma defaults to `http://127.0.0.1:8082/v1`
- Gemma model defaults to `mlx-community/gemma-4-26b-a4b-it-4bit`
- Meeting transcription defaults to `mlx-community/whisper-tiny-asr-fp16`
- Voice-question transcription defaults to `mlx-community/whisper-small`
- Whisper/Kokoro use the MLX venv above unless overridden

Notes:
- if Gemma is not reachable, the app uses a deterministic fallback summarizer and answerer
- if Whisper/Kokoro subprocess wiring is unavailable, the UI still works but reports fallback/unavailable model status honestly
- live browser updates use SSE via `/api/meetings/{id}/events`
- meeting capture preview uses rolling `/transcribe-preview` uploads while recording is active

## Main browser features

### Capture
- start/stop meeting recording
- rolling transcript preview while recording
- visible timer and recording state
- final transcript + summary commit after stop

### Transcript
- clean transcript view
- raw transcript view
- both preserved as meeting artifacts

### Summary
- summary generated automatically after final transcription
- manual regenerate button still available

### Talk
- typed follow-up questions
- push-to-talk voice questions
- hands-free tap-once mode with auto-stop after silence
- multi-turn context from recent conversation history
- reactive audio bars while Kokoro reply audio is playing

### Artifacts
- direct links to saved meeting files
- pipeline log for transcription / summary / Q&A / TTS events

## Test

```bash
cd /Users/Shared/GITHUB/meeting-prompter-ios/meeting-transcriber
HERMES_BROWSER_DISABLE_MODEL_SUBPROCESS=1 python3 -m pytest hermes_browser_rebuild/tests/test_app.py -q
```
