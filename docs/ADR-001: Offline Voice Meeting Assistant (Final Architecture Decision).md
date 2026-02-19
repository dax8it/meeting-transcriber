ADR-001: Offline Voice Meeting Assistant (Final Architecture Decision)

**ADR-001: Offline Voice Meeting Assistant (Final Architecture Decision)**  
**Date:** February 10, 2026  
**Status:** Approved (recommended implementation baseline)

## 0. 2026-02-19 Stabilization Addendum (Current Source of Truth)
- This ADR remains useful as historical context, but parts of the migration recommendation below are now **superseded for the current release track**.
- Current locked baseline is the existing on-device stack:
  - ASR: `LFM2.5-Audio-1.5B-Q8_0` path
  - RAG + transcript summarizer: existing local text models
  - TTS: `ModelTTSService` with Leap audio generation, conservative chunking, buffered playback, and exported WAV share flow
- Latest on-device validation completed two full Q&A turns with full paragraph playback and successful sharing.
- Lock-down rule: avoid broad TTS architecture migrations while this pipeline is stable; only apply minimal, scoped fixes for user-visible regressions.

## 1. Scope and Constraints
- Fully offline (`no cloud`)
- Non-Apple TTS is a hard requirement
- Target devices: iPhone 15 primary, iPhone 14 Pro supported
- Must keep existing strengths: transcription, summarization, RAG
- UX on TTS failure: show `No audio available at this moment` and continue normal app flow

## 2. Final Technical Decision
1. Keep current transcription/summarization/RAG stack.
2. Replace current experimental TTS runtime path with a production TTS subsystem using a strict provider interface and single primary engine.
3. Do **not** restart app from scratch.

## 3. Recommended Production Stack
- **STT:** Keep current on-device transcription path that is already performing well.  
  - English-first production.
  - Add multilingual only after explicit model-card validation and device benchmarks.
- **Summarizer:** Keep current local transcript summarizer model.
- **RAG:** Keep current local RAG model and retrieval pipeline.
- **TTS (primary):** Move to a simpler, deterministic offline TTS engine with stable iOS packaging (recommended: **Piper ONNX** style deployment with local voice packs).  
  - Reason: lower runtime fragility than current MLX/Kokoro integration path.
- **TTS fallback behavior:** No Apple fallback in production voice path; instead:
  - circuit-breaker + user alert `No audio available at this moment`.

## 4. Why Current Attempts Broke
- LFM2.5 audio path: model/task compatibility and memory pressure instability.
- Kokoro path: artifact/version mismatch + resource packaging/cache fragility + timeout race handling.
- Too many concurrent hard problems (model compatibility, resource bundling, audio session, fallback logic) were being solved in one live app loop.

## 5. What to Keep vs Change
**Keep**
- UI, session model, transcript pipeline, summary flow, RAG flow.
- Voice Q&A UX entry and push-to-talk interaction.

**Change**
- TTS runtime implementation and packaging discipline.
- Model artifact governance (hashes, manifest, compatibility checks).
- Reliability controls (timeouts, single-fallback guard, circuit breaker).

## 6. Packaging and Runtime Rules (Non-Negotiable)
1. Every model artifact pinned by SHA256 in a manifest.
2. At launch, verify artifact hashes and compatibility keys before use.
3. Only one heavy model family active at a time (memory budget control).
4. TTS provider must pass soak tests before release.
5. No implicit fallback loops; single failure path + user alert.

## 7. Performance/Quality Targets (Release Gates)
- Crash-free TTS sessions: `>= 99.5%`
- TTS fallback/alert rate: `< 1%`
- TTS speed: `>= 1.0x` realtime on iPhone 14 Pro
- No high-pitch/noise artifacts in 10-minute soak test
- Voice Q&A end-to-end (PTT stop -> spoken answer start): target `< 4s` median

## 8. OpenClaw Agent Ownership (Recommended)
Agents should own:
1. Model registry updates (hash + metadata + migration notes)
2. Device benchmark matrix (iPhone 14 Pro, iPhone 15)
3. Regression packs:
   - 20-turn voice Q&A
   - long-answer TTS (30s, 60s, 120s)
   - interruption/cancel/resume
   - memory pressure + background/foreground transitions
4. Promotion gates (fail build if thresholds violated)

## 9. What I’d Do Differently From Day 1
1. Freeze one engine per modality early.
2. Build one vertical slice and soak test first.
3. Require artifact hash manifest before any runtime integration.
4. Add reliability SLOs before adding extra voices/languages.
5. Separate “experimental TTS” from production path behind a flag.

## 10. Questions That Must Be Answered Before Next Ambitious Build
1. Which exact devices are hard support targets?
2. What is max acceptable app size?
3. What is max acceptable latency per module?
4. What fallback UX is allowed per module?
5. Is multilingual required at launch or post-launch?
6. How many voices at launch?
7. Who owns model upgrade approvals?
8. What are release-blocking quality thresholds?
9. What telemetry can be collected offline for QA?
10. What is the rollback plan for model regressions?
11. How are model artifacts signed/verified?
12. What is the exact definition of “done” for each module?

## 11. Definition of Done (Your Project)
All pass on iPhone 14 Pro and iPhone 15:
1. Transcription works offline.
2. Summarization works offline.
3. RAG answers correctly with local evidence.
4. Non-Apple TTS reads responses reliably.
5. On TTS failure, app remains fully functional and shows `No audio available at this moment`.

If you want, next I can produce the exact **implementation plan (tasks + file-level changes + test matrix)** for migrating TTS cleanly without touching your working STT/RAG/summarizer modules.