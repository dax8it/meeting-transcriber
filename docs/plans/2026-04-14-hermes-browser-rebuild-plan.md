# Hermes Meeting Prompter Browser Rebuild Plan

> For Hermes: implement as a separate local-web product path. Do not modify the existing iOS app code.

Goal: recreate the meeting-prompter experience as a phone-first browser app served from the Mac, using Hermes-agent as runtime/orchestration substrate and Tailscale HTTPS for private iPhone access.

Architecture:
- thin browser client on iPhone Safari
- local app server on Mac
- session/artifact storage on disk
- dedicated ASR service
- Gemma 4 for summary/Q&A
- dedicated TTS service
- Tailscale HTTPS exposure

Tech stack:
- FastAPI or existing Reddy app server
- browser UI served locally
- local Gemma 4 model server (MLX/OpenAI-compatible endpoint)
- local ASR endpoint
- local TTS endpoint
- SQLite/FTS or lightweight file-backed session storage

---

## Phase 1 — product shell

### Task 1: create standalone product boundary
Objective: keep the existing iOS app untouched while giving the browser rebuild its own implementation surface.

Files:
- Create: new repo or product slice under the chosen Hermes/Reddy host
- Create: `docs/product/meeting-prompter-browser.md`
- Create: `docs/architecture/meeting-prompter-browser.md`

Definition of done:
- browser rebuild has its own docs and runtime entrypoint
- no iOS app source files are changed

### Task 2: define session artifact contract
Objective: preserve the best part of the iOS design: persisted meeting artifacts.

Persist per session:
- `metadata.json`
- `meeting_audio.(wav|m4a|webm)`
- `transcript.txt`
- `summary.md`
- `search_index.db`
- `chat_history.json`
- `voice_replies/*.wav`

Definition of done:
- one session directory contains everything needed to reopen and answer from a meeting

---

## Phase 2 — browser UX skeleton

### Task 3: build the home/session list UI
Objective: show recent meetings and allow starting a new one.

Views:
- Home
- Sessions list
- Session detail

Definition of done:
- can create a new empty meeting session
- can list and reopen previous sessions

### Task 4: build live transcript page
Objective: make the browser the remote control surface for meeting recording.

Controls:
- start recording
- stop recording
- transcript streaming area
- recording status

Definition of done:
- iPhone browser can record through the page
- audio reaches backend
- transcript area updates from server state

---

## Phase 3 — ASR and transcript persistence

### Task 5: wire dedicated ASR endpoint
Objective: get reliable transcription without coupling to Gemma first.

Recommended initial choice:
- whisper.cpp / MLX Whisper class service

Definition of done:
- uploaded/live browser audio becomes transcript text
- transcript is saved to session artifacts

### Task 6: implement chunked live transcription
Objective: match the current app’s useful behavior without iPhone inference constraints.

Definition of done:
- transcript updates continuously while recording
- final transcript is normalized and saved on stop

---

## Phase 4 — summary generation

### Task 7: attach Gemma 4 summary service
Objective: replace the current dedicated summary model with Gemma 4 text generation.

Recommended default:
- Gemma 4 26B A4B on local MLX-compatible server if available

Definition of done:
- stopping a recording triggers summary generation
- summary is saved as markdown
- session detail page renders it cleanly

---

## Phase 5 — grounded Q&A

### Task 8: implement simple meeting retrieval
Objective: keep v1 retrieval lean and deterministic.

Recommended v1:
- SQLite FTS/BM25
- transcript chunking
- summary chunking
- top-k retrieval with source labels

Definition of done:
- question retrieves meeting-specific evidence only
- retrieved chunks are inspectable/debuggable

### Task 9: attach Gemma 4 answer generation
Objective: generate concise grounded answers from retrieved meeting evidence.

Prompt contract:
- answer only from supplied sources
- if evidence is insufficient, say so plainly
- keep answers concise by default

Definition of done:
- typed questions return grounded answers with source references

---

## Phase 6 — voice Q&A

### Task 10: add push-to-talk question capture
Objective: let the browser capture short follow-up voice questions.

Definition of done:
- hold-to-talk or tap-to-talk works in iPhone Safari over Tailscale HTTPS
- question audio is transcribed by backend ASR

### Task 11: add spoken answer playback
Objective: provide better voice output than the current iPhone path.

Recommended default:
- dedicated local TTS service, not Gemma 4
- start with short-answer synthesis and WAV/MP3 playback

Definition of done:
- chat answer can be spoken back and replayed
- generated audio is stored in the session artifact folder

---

## Phase 7 — Tailscale exposure

### Task 12: expose the UI over Tailscale HTTPS
Objective: make the app usable from iPhone without public exposure.

Requirements:
- local server reachable on localhost
- Tailscale running on Mac
- `tailscale serve` configured for the app port
- final access URL is `https://<host>.<tailnet>.ts.net`

Definition of done:
- iPhone Safari can open the app over HTTPS
- browser mic permissions work from the Tailscale URL

---

## Phase 8 — benchmarking and cutover decision

### Task 13: benchmark stage latency
Objective: verify that the browser rebuild is actually better, not just conceptually cleaner.

Measure:
- time to first transcript token
- time to final transcript
- time to summary
- time to first answer token
- time to finished spoken answer

Definition of done:
- benchmark table exists comparing iPhone app vs browser rebuild on real meetings

### Task 14: decide default model mix
Objective: decide with evidence, not vibes.

Compare:
- dedicated ASR + Gemma 4 + dedicated TTS
- Gemma 4 audio-in + Gemma 4 text + dedicated TTS

Definition of done:
- one stack is chosen as the production default
- any experimental path is marked experimental

---

## Default recommended stack

Production default:
- ASR: dedicated local speech service
- summary/Q&A: Gemma 4
- retrieval: SQLite FTS/BM25
- TTS: dedicated local TTS service
- access: Tailscale HTTPS

## Non-goals for v1

Do not add unless needed:
- vector DB first
- speaker diarization first
- public internet exposure
- multi-user auth complexity
- one-model-does-everything purity project

## Acceptance bar

The rebuild is successful when:
- it reproduces the useful workflow of the iOS app
- it is faster than the iPhone-first path in real use
- it sounds better on spoken replies
- it is easy to reach privately from iPhone Safari
- the old iOS app remains untouched
