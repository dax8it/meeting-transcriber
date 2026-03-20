# Puppet iOS — Quick Start

This is the short setup path for the **current working app**.

For the fuller setup and behavior notes, also see:
- `README.md`
- `SETUP.md`
- `docs/app-spec-current.md`

## What this app does

Puppet is an on-device iOS app for:
- meeting transcription
- meeting summaries
- grounded Q&A over saved meetings
- push-to-talk voice Q&A with spoken answers

## Current model roles

The app uses different local models for different jobs:
- **ASR:** `LFM2.5-Audio-1.5B-Q8_0`
- **Summary:** `LFM2-2.6B-Transcript-Q_4_k_m` (fallback `LFM2-2.6B-Transcript-Q4_K_M`)
- **Q&A / RAG:** `LFM2-1.2B-RAG-Q5_K_M`
- **Spoken answers / TTS:** `LFM2.5-Audio-1.5B-Q8_0` with Apple speech fallback

## Fast setup checklist

### 1) Open the project
Open:
- `meeting-transcriber.xcodeproj`

### 2) Add package dependencies
Required packages:
- Leap SDK
- GRDB

### 3) Bundle the local models
Make sure your app target includes the current model assets and required audio companion files.

At minimum, verify:
- ASR/audio model file
- audio tokenizer
- mmproj
- decoder/vocoder artifact for model TTS when using spoken answers
- transcript/summarization model
- RAG model

### 4) Confirm microphone permission
Verify `NSMicrophoneUsageDescription` is present in the target Info settings.

### 5) Build on a physical device
Recommended flow:
- select iPhone target
- build and run
- grant microphone access

## First manual smoke test

1. Launch the app.
2. Confirm Home loads.
3. Start **New Transcription**.
4. Record a short meeting sample.
5. Stop and wait for session creation.
6. Open the saved session in **Summaries**.
7. Confirm the summary appears.
8. Ask a typed question.
9. Open **Voice Q&A** and test push-to-talk.
10. Toggle spoken answers and verify reply playback.

## Expected current screens
- Home
- Transcribe
- Summaries
- Session
- Chat / Voice Q&A
- Settings

## Important note

This app is **working but still in progress**. If docs and runtime behavior disagree, trust the code and then update the docs.
