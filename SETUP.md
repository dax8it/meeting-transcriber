# Puppet iOS — Setup Guide

This setup guide reflects the **current working local app baseline**.

If you are checking model filenames or runtime loading behavior, confirm against:
- `MeetingPrompterIOS/Core/AI/ModelIDs.swift`
- `MeetingPrompterIOS/Core/AI/LeapModelManager.swift`

## Prerequisites

- Xcode 15+
- iOS 15+
- physical iPhone recommended
- local model assets available for bundling

## 1) Open the project

Open:
- `meeting-transcriber.xcodeproj`

## 2) Add Swift package dependencies

The app depends on:
- **LeapSDK**
- **GRDB**

Add them in Xcode using **File → Add Package Dependencies...**

## 3) Add model assets to the app target

The app uses **multiple local models**, not one model for everything.

### Audio / ASR / model TTS
Current audio model ID:
- `LFM2.5-Audio-1.5B-Q8_0`

Expected usage:
- live transcription
- voice question transcription
- spoken answer generation

Important:
- the audio model may require companion files next to it in the bundle
- companion files can include:
  - tokenizer
  - mmproj
  - decoder / vocoder artifact

### Summarization
Primary model ID:
- `LFM2-2.6B-Transcript-Q_4_k_m`

Fallback:
- `LFM2-2.6B-Transcript-Q4_K_M`

### Grounded Q&A
Model ID:
- `LFM2-1.2B-RAG-Q5_K_M`

## 4) Target membership and bundle verification

For every required model file:
1. verify the file is present in the Xcode project
2. verify the app target is checked under **Target Membership**
3. verify the file appears in **Build Phases → Copy Bundle Resources**

This matters especially for:
- audio model
- tokenizer
- mmproj
- decoder/vocoder
- transcript model
- RAG model

## 5) Resource path behavior on iOS

The app is built to tolerate iOS/Xcode resource flattening.

That means model lookup may succeed from either:
- an expected subdirectory like `models/audio` or `models/text`
- the bundle root fallback if Xcode flattened resources

Do not hardcode assumptions from older docs without checking current code.

## 6) Microphone permission

Confirm the target includes a microphone usage description.

Typical purpose string:
- the app needs microphone access to record meetings and voice questions

## 7) Build and run

Recommended:
1. select a physical iPhone
2. clean build folder if needed
3. run the app
4. grant microphone permission

## 8) First-run validation

### Home
- app launches cleanly
- Home screen appears
- recent sessions load or show empty state

### Recording
- New Transcription opens
- mic starts recording
- transcript updates while speaking
- pause/resume works
- stop finalizes the session

### Summary generation
- new session appears in Summaries
- summary placeholder is replaced by a real summary
- Session page renders Markdown summary

### Typed Q&A
- typed follow-up question returns an answer
- answer is grounded in meeting material

### Voice Q&A
- push-to-talk captures a short voice question
- voice status changes through listening/transcribing/thinking/speaking
- spoken-answer toggle works

## 9) Troubleshooting notes

### Models not found
Common cause:
- missing target membership or missing copy-bundle step

Check:
- current IDs in `ModelIDs.swift`
- resource resolution behavior in `LeapModelManager.swift`

### Audio model errors
Common causes:
- missing tokenizer
- missing mmproj
- missing decoder/vocoder for TTS path
- incompatible companion file names

### RAG loads incorrectly
Common cause:
- stale or mismatched model bundle contents

Check:
- current primary/fallback RAG IDs
- text-model staging logic in `LeapModelManager.swift`

### Summary generation fails
Common cause:
- transcript model missing or mismatched

Check:
- current transcript model IDs
- transcript-model load path in `LeapModelManager.swift`

## 10) Documentation reminder

This project is still evolving. When updating setup docs:
- prefer current model IDs over old examples
- explicitly mention fallbacks
- note that the app is a working prototype / work in progress
