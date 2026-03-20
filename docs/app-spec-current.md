# Puppet iOS — Current App Spec

> This document summarizes the current *working* app behavior and is meant to be easier to read than tracing everything from code.
>
> Final authority still lives in:
> - `MeetingPrompterIOS/Core/AI/ModelIDs.swift`
> - `MeetingPrompterIOS/Core/AI/LeapModelManager.swift`
> - `MeetingPrompterIOS/App/ViewModels/`
> - `MeetingPrompterIOS/Views/`

## Product summary

Puppet is an offline-first iOS meeting assistant that records meetings, generates local summaries, and supports grounded follow-up Q&A against saved meeting artifacts.

The app is intentionally built around **local multi-model inference** rather than a single all-purpose model.

## Current user-facing pages

### 1) Home
Purpose:
- start a new meeting transcription
- open the summaries library
- reopen recent sessions
- access settings

Behavior:
- shows the on-device-only positioning
- loads recent sessions from local storage
- presents the AI disclosure on first use

### 2) Transcribe
Purpose:
- record a meeting
- show a live transcript during capture
- finalize a transcript into a saved session

Behavior:
- records audio locally
- shows live transcript updates while capture is active
- supports pause/resume while recording
- on stop, creates a session and triggers summary generation

### 3) Summaries
Purpose:
- browse saved sessions
- reopen or delete meetings

Behavior:
- loads all saved sessions from local storage
- supports pull-to-refresh
- supports deletion from the device

### 4) Session
Purpose:
- review the generated meeting summary
- share the summary
- ask typed questions
- jump into voice Q&A

Behavior:
- loads Markdown or text summary artifacts
- shows an AI notice banner
- supports typed Q&A from the session screen
- provides access to the dedicated Chat / Voice Q&A page

### 5) Chat / Voice Q&A
Purpose:
- ask meeting-specific follow-up questions by text or voice
- optionally hear spoken answers

Behavior:
- text input and push-to-talk input are both supported
- voice recording auto-stops after a bounded capture window
- grounded answers are generated from meeting transcript + summary evidence
- spoken answers can be toggled on/off

### 6) Settings
Purpose:
- disclosure, privacy, legal, version/build info

## Current model mapping

### ASR
Model:
- `LFM2.5-Audio-1.5B-Q8_0`

Use:
- live meeting transcription
- voice question transcription

Implementation note:
- requires audio companions such as tokenizer / mmproj and, for TTS usage, decoder-vocoder artifacts

### Summarization
Primary:
- `LFM2-2.6B-Transcript-Q_4_k_m`

Fallback:
- `LFM2-2.6B-Transcript-Q4_K_M`

Use:
- generates the Markdown smart summary for a meeting

Output shape:
- title
- key points
- decisions
- action items
- open questions

### Grounded Q&A
Model:
- `LFM2-1.2B-RAG-Q5_K_M`

Use:
- typed follow-up questions
- answer-generation step in Voice Q&A

Grounding:
- uses a meeting-scoped local index
- can merge transcript chunks with summary chunks
- aims to answer only from available evidence

### Spoken answers
Primary:
- `LFM2.5-Audio-1.5B-Q8_0`

Fallback:
- Apple speech synthesis

Use:
- speak answers in Voice Q&A
- optionally export generated audio artifacts

## Current workflow

### Meeting creation workflow
1. Start recording from Home.
2. Capture audio locally.
3. Show live transcript.
4. Stop recording.
5. Persist transcript and create a new session folder.
6. Write placeholder summary artifact.
7. Generate summary in the background.
8. Re-index the meeting for grounded Q&A.

### Session Q&A workflow
1. Open session.
2. Load transcript/summary artifacts.
3. Retrieve relevant meeting chunks.
4. Generate grounded answer.
5. Optionally show citations and/or speak the response.

## Current storage expectations

Per meeting session, the app may store:
- audio recording
- transcript file
- summary text file
- summary markdown file
- local retrieval database / indexed meeting chunks
- optional answer-audio export files

## Product messaging

Current messaging should emphasize:
- private
- secure
- local AI
- on-device only
- no internet required for core flows

It should also clearly state:
- AI answers may be inaccurate
- the app is still a work in progress
- model and UX choices may continue to evolve

## Documentation maintenance rule

When updating docs:
1. check code first
2. check model IDs second
3. avoid copying stale filenames from older MVP notes
4. document fallbacks explicitly
5. state when a feature is stable vs still evolving
