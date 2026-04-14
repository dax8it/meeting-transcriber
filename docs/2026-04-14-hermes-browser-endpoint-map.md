# Hermes Browser Rebuild Endpoint Map

Date: 2026-04-14
Working copy root: `hermes_browser_rebuild/`

This endpoint map mirrors the current iOS workflow while moving UI to the browser and compute to the Mac.

## Design goals

- keep meetings as first-class saved artifacts
- keep transcript, summary, Q&A, and spoken replies scoped to one meeting
- support both typed and push-to-talk follow-up questions
- keep the browser surface simple enough for iPhone Safari over Tailscale HTTPS

## Core routes

### GET `/health`
Purpose:
- health check for local server and Tailscale exposure verification

Returns:
- app ok flag
- current time
- model status
- number of meetings on disk

### GET `/api/model-status`
Purpose:
- tell the UI what is actually wired right now

Returns:
- whisper status
- gemma status
- kokoro status

### GET `/api/meetings`
Purpose:
- list saved meeting sessions for the left rail / summaries list

Returns per meeting:
- id
- title
- created_at
- updated_at
- transcript_present
- summary_present
- transcript_preview
- answer_count

### POST `/api/meetings/start`
Purpose:
- create a new meeting session folder and metadata record

Request body:
```json
{
  "title": "Weekly planning"
}
```

Returns:
- full meeting detail record

### GET `/api/meetings/{meeting_id}`
Purpose:
- load one meeting into the main workspace

Returns:
- live transcript preview
- transcript
- summary
- chat history
- status flags
- artifact URLs

### GET `/api/meetings/{meeting_id}/events`
Purpose:
- server-sent events stream for live UI updates

Behavior:
- emits initial snapshot event when the workspace loads
- emits preview updates during recording
- emits transcript finalization events after stop
- emits answer events when a Q&A turn completes

Use case:
- keeps iPhone/browser UI reactive without polling the whole meeting record every time

## Recording and transcription

### POST `/api/meetings/{meeting_id}/transcribe-preview?mode=meeting`
Purpose:
- upload a rolling meeting-audio snapshot and get live transcript preview text while recording is still active

Behavior:
- transcribes the rolling snapshot
- updates `live_transcript_preview`
- publishes an SSE preview event to the browser
- does not finalize transcript artifacts yet

Returns:
- updated meeting detail
- preview text
- provider used
- mode

### POST `/api/meetings/{meeting_id}/transcribe?mode=meeting`
Purpose:
- upload the final recorded meeting audio and commit the transcript artifacts

Request:
- raw audio body (`audio/webm`, `audio/wav`, etc.)
- `X-Filename` header optional

Behavior:
- saves meeting audio artifact
- runs Whisper MLX if configured
- clears live preview after final commit
- appends transcript to the meeting transcript artifact
- regenerates summary automatically
- publishes an SSE finalized-transcript event to the browser

Returns:
- updated meeting detail
- transcript delta
- provider used
- mode

### POST `/api/meetings/{meeting_id}/transcribe?mode=voice`
Purpose:
- transcribe a short voice clip without appending it to the meeting transcript

Use case:
- internal helper route for push-to-talk voice question flow

## Summary generation

### POST `/api/meetings/{meeting_id}/summarize`
Purpose:
- generate or regenerate the saved meeting summary from the transcript

Behavior:
- uses Gemma 4 if configured
- otherwise uses deterministic fallback summarization
- persists `summary.md`

Returns:
- updated meeting detail

## Typed Q&A

### POST `/api/meetings/{meeting_id}/ask`
Purpose:
- ask a grounded question against this meeting only

Request body:
```json
{
  "question": "What did we decide about launch timing?",
  "speak_reply": true
}
```

Behavior:
- retrieve transcript/summary chunks for this meeting
- answer via Gemma 4 if configured, fallback otherwise
- optionally synthesize spoken answer via Kokoro MLX
- save Q&A turn in meeting chat history

Returns:
- updated meeting detail
- answer text
- sources used
- optional audio URL
- answer provider
- tts provider

## Voice Q&A

### POST `/api/meetings/{meeting_id}/voice-question?speak_reply=true`
Purpose:
- one-shot push-to-talk endpoint for the browser

Request:
- raw audio body for short user question
- `X-Filename` header optional

Behavior:
1. save voice question audio clip
2. transcribe with Whisper MLX
3. use recent conversation turns as context for follow-up retrieval
4. retrieve grounded meeting sources
5. answer with Gemma 4 or meeting-context fallback
6. optionally synthesize reply with Kokoro MLX
7. persist the turn in chat history and publish an SSE answer event

Returns:
- same response shape as `/ask`

## Spoken reply only

### POST `/api/meetings/{meeting_id}/speak`
Purpose:
- synthesize speech for arbitrary text in the current meeting context

Request body:
```json
{
  "text": "Here is the concise answer to play back."
}
```

Returns:
- audio URL
- provider name

## Media

### GET `/media/{meeting_id}/{asset_path}`
Purpose:
- serve saved meeting artifacts and generated reply audio

Examples:
- transcript file
- summary file
- generated voice reply WAV

## Browser UX mapping to old app

Current iOS behavior -> browser route

- start a new meeting -> `POST /api/meetings/start`
- subscribe UI for reactive updates -> `GET /api/meetings/{id}/events`
- stream rolling preview while recording -> `POST /api/meetings/{id}/transcribe-preview?mode=meeting`
- stop recording and commit transcript -> `POST /api/meetings/{id}/transcribe?mode=meeting`
- summarize session -> `POST /api/meetings/{id}/summarize`
- ask typed follow-up -> `POST /api/meetings/{id}/ask`
- ask voice follow-up -> `POST /api/meetings/{id}/voice-question`
- speak latest answer -> returned from `ask` or `voice-question`, or explicit `POST /api/meetings/{id}/speak`

## Why this is better than the current app UX

- tabbed workspace instead of a cluttered single panel
- clear session state always visible
- transcript preview updates reactively during recording
- typed, push-to-talk, and hands-free follow-up live in the same Talk tab
- reactive speaking audio makes voice output feel alive instead of opaque
- model status is explicit instead of buried
- transcript, summary, answer, sources, and audio are visible together
- iPhone is just the control surface; the Mac does the heavy lifting
