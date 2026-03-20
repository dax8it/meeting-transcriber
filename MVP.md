# Puppet iOS — Working MVP / Baseline Notes

> This file is now a **current baseline reference**, not an old speculative MVP plan.
>
> The current runtime source of truth is still:
> - `MeetingPrompterIOS/Core/AI/ModelIDs.swift`
> - `MeetingPrompterIOS/Core/AI/LeapModelManager.swift`
> - `MeetingPrompterIOS/App/ViewModels/`

## What the app currently does

The working app supports five core capabilities:
1. record a meeting locally
2. generate a live/final transcript
3. save the meeting as a reusable session
4. generate a local Markdown summary
5. answer follow-up questions about that meeting by text or voice

## Current screen map

### Home
- app entry point
- starts a new transcription
- opens summaries library
- shows recent sessions
- links to settings

### Transcribe
- records the meeting
- shows live transcript updates
- supports pause/resume
- finalizes the transcript into a session on stop

### Summaries
- session library / history
- reopen saved sessions
- delete saved sessions

### Session
- displays smart summary
- supports summary sharing
- supports typed follow-up questions
- links to voice Q&A

### Chat / Voice Q&A
- typed meeting Q&A
- push-to-talk voice questions
- optional spoken answers

### Settings
- AI disclosure
- privacy
- EULA
- third-party notices
- version/build info

## Current model architecture

The app uses multiple local models for different tasks.

### ASR
- `LFM2.5-Audio-1.5B-Q8_0`

Used for:
- live meeting transcription
- voice question transcription

### Summary generation
Primary:
- `LFM2-2.6B-Transcript-Q_4_k_m`

Fallback:
- `LFM2-2.6B-Transcript-Q4_K_M`

Used for:
- Markdown smart summaries

### Q&A / grounded answering
Model:
- `LFM2-1.2B-RAG-Q5_K_M`

Used for:
- typed Q&A from the session page
- answer generation in Voice Q&A

### Spoken answers
Primary model path:
- `LFM2.5-Audio-1.5B-Q8_0`

Fallback path:
- Apple speech synthesis

Used for:
- spoken reply playback in Voice Q&A

## Current workflow summary

### Recording → session creation
- start capture
- generate live transcript
- stop capture
- persist transcript to a session folder
- create placeholder summary
- generate summary asynchronously
- re-index transcript + summary for later Q&A

### Session review → Q&A
- open saved session
- read summary
- ask typed follow-up questions
- or open Voice Q&A for push-to-talk interaction

## Current product messaging

The app should be described as:
- private
- secure
- local AI
- on-device only
- offline-first
- a work in progress

## Important implementation realities

- the app swaps/unloads models to manage device memory
- audio and text models are intentionally isolated
- summary and Q&A run against saved session artifacts
- AI responses may be inaccurate and should be verified when important

## What changed versus older docs

Older docs often implied:
- a simpler two-model app
- an earlier Meeting Prompter naming baseline
- a narrower typed-Q&A-only workflow

The current working app is broader than that and now includes:
- saved session library
- smart summary screen
- voice Q&A chat
- spoken answers
- more explicit multi-model separation
