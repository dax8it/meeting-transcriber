# ADR-001 — Offline Voice Meeting Assistant

**Date:** 2026-02-10  
**Status:** Historical context with a stabilization addendum

This ADR is kept in the public repo as historical architecture context.
It is **not** the sole source of truth for the current app behavior.

For the current working baseline, check:
- `README.md`
- `docs/app-spec-current.md`
- `MeetingPrompterIOS/Core/AI/ModelIDs.swift`
- `MeetingPrompterIOS/Core/AI/LeapModelManager.swift`

---

## 2026-02-19 stabilization addendum

Current locked baseline at the time of this addendum:
- ASR: `LFM2.5-Audio-1.5B-Q8_0`
- local text models for summary + grounded Q&A
- TTS: `ModelTTSService` with Leap audio generation, chunking, buffered playback, and WAV export/share flow

Guidance from that stabilization point:
- avoid broad TTS architecture migrations while the baseline remains usable
- prefer minimal, scoped fixes for clear user-visible regressions

---

## Original decision summary

The original decision intent was:
1. keep the working transcription / summarization / retrieval baseline
2. avoid rewriting the app from scratch
3. improve voice reliability through better packaging, runtime discipline, and clearer failure handling

This remains useful as a record of how the project framed the voice-stack problem at the time.

---

## Original constraints captured in this ADR

- offline / no-cloud core workflow
- non-Apple TTS was considered a project requirement at the time
- existing transcription, summarization, and RAG strengths should be preserved
- TTS failure should not break the rest of the app flow

---

## Historical architecture guidance from this ADR

### Keep
- UI and session model
- transcript pipeline
- summary flow
- RAG / grounded Q&A flow
- voice Q&A entry point and push-to-talk interaction

### Improve
- TTS runtime implementation
- model artifact governance
- reliability controls such as timeouts and failure handling

---

## Why this ADR still matters

Even though parts of it are now historical, it still documents a few useful project lessons:
- do not solve too many audio/runtime problems at once in a live app loop
- keep model packaging disciplined
- treat reliability controls as product requirements, not cleanup work
- prefer bounded fixes over broad migrations when the baseline is working

---

## Public-repo note

This file is intentionally kept as a lightweight historical ADR.
Detailed internal migration plans and agent coordination docs are maintained privately and are not shipped in this public repo.
