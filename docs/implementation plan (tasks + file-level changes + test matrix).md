**Final TTS Migration Plan (Offline, Non-Apple, No STT/RAG/Summary Changes)**

> **Status (2026-02-19): Superseded for current release track.**
>
> The app currently has a working/stable on-device voice pipeline (ASR + RAG + summary + Leap model TTS + WAV share).
> Keep this migration plan as a contingency/reference only. Do **not** execute broad provider/runtime migrations while the current baseline remains stable.
>
> Current recommendation: only apply minimal, scoped fixes for user-visible regressions (crash, no audio, failed share flow, repeat fallback loops).

## 1. Guardrails (hard)
1. Do not modify:
- `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Core/AI/ASRService.swift`
- `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Core/AI/LiveTranscriptionService.swift`
- `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Core/AI/RAGService.swift`
- `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Core/AI/SummarizationService.swift`
2. TTS failure UX must be: `No audio available at this moment`.
3. No Apple TTS fallback in production path.
4. All model artifacts pinned by SHA256.

## 2. Architecture Decision for Migration
Use a dedicated **offline TTS subsystem** with provider abstraction and make **Piper ONNX** the primary production engine (more deterministic packaging/runtime on iOS than current MLX kernel/cache behavior).

## 3. Task Plan (exact)

| ID | Task | Files | Exit Criteria |
|---|---|---|---|
| T1 | Introduce TTS provider interface | **Add** `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Core/TTS/TTSProvider.swift` | `ModelTTSService` depends on protocol, not concrete engine |
| T2 | Add TTS runtime package wrapper | **Add** `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/Packages/PiperTTSKit/Package.swift` and wrapper sources | Local package builds in Xcode; no app logic yet |
| T3 | Add Piper inference bridge + phonemizer bridge | **Add** `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/Packages/PiperTTSKit/Sources/PiperTTSKit/PiperEngine.swift`, `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/Packages/PiperTTSKit/Sources/PiperTTSKit/PhonemizerBridge.mm`, `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/Packages/PiperTTSKit/Sources/PiperTTSKit/include/*.h` | Can synthesize PCM from text in isolated unit test |
| T4 | Add asset manifest and verifier | **Add** `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/models/tts/manifest.json`, `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/scripts/verify_tts_assets.sh` | Build fails (or startup hard-fails TTS init) on hash mismatch |
| T5 | Add voice catalog and preferences model | **Add** `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Core/TTS/TTSVoiceCatalog.swift`, `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Core/TTS/TTSPreferences.swift` | Multiple voice IDs load from manifest and persist via `AppStorage` |
| T6 | Replace current `ModelTTSService` internals | **Modify** `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Core/Audio/ModelTTSService.swift` | Uses provider abstraction; no direct Kokoro/Apple runtime calls |
| T7 | Add robust playback controller | **Add** `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Core/TTS/PCMPlaybackController.swift` | No high-pitch artifacts, no cut-off on long playback |
| T8 | Update settings UI for voices | **Modify** `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Views/Settings/SettingsView.swift` | User can pick default voice and speech rate |
| T9 | Wire failure UX in chat | **Modify** `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/App/ViewModels/ChatViewModel.swift` | On TTS failure: alert text `No audio available at this moment`, text answer remains |
| T10 | Xcode resource and package wiring | **Modify** `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/meeting-transcriber.xcodeproj/project.pbxproj` | Voice/model files and phonemizer data packaged correctly |
| T11 | Remove old runtime coupling safely | **Modify** `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Core/Audio/ModelTTSService.swift`; optional cleanup in `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/models/tts/` | No Kokoro/Apple fallback path in production branch |
| T12 | Add regression harness for agents | **Add** `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/scripts/tts_regression.sh`, `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/docs/tts-regression-matrix.md` | OpenClaw agents can run deterministic upgrade checks |

## 4. File-Level Change List

### Add
- `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Core/TTS/TTSProvider.swift`
- `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Core/TTS/TTSVoiceCatalog.swift`
- `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Core/TTS/TTSPreferences.swift`
- `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Core/TTS/PCMPlaybackController.swift`
- `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/models/tts/manifest.json`
- `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/scripts/verify_tts_assets.sh`
- `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/scripts/tts_regression.sh`
- `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/Packages/PiperTTSKit/Package.swift`
- `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/Packages/PiperTTSKit/Sources/PiperTTSKit/PiperEngine.swift`
- `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/Packages/PiperTTSKit/Sources/PiperTTSKit/PhonemizerBridge.mm`
- `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/Packages/PiperTTSKit/Sources/PiperTTSKit/include/PiperBridge.h`

### Modify
- `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Core/Audio/ModelTTSService.swift`
- `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/App/ViewModels/ChatViewModel.swift`
- `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Views/Settings/SettingsView.swift`
- `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/meeting-transcriber.xcodeproj/project.pbxproj`

## 5. Test Matrix (release gate)

| ID | Area | Scenario | Device | Pass Criteria |
|---|---|---|---|---|
| F1 | Functional | Voice Q&A short answer (5-10s audio) | iPhone 14 Pro, iPhone 15 | Audio plays fully, no fallback |
| F2 | Functional | Long answer (45-90s) | iPhone 14 Pro, iPhone 15 | No cut-off, no high-pitch artifact |
| F3 | Functional | User interrupts playback with new question | iPhone 14 Pro, iPhone 15 | Current playback stops cleanly, next starts |
| F4 | Functional | Change voice in settings, ask again | iPhone 14 Pro, iPhone 15 | New voice heard immediately |
| F5 | Functional | Missing/corrupt voice asset | iPhone 14 Pro, iPhone 15 | Shows `No audio available at this moment`, app continues |
| R1 | Reliability | 50 consecutive voice Q&A turns | iPhone 15 | 0 crashes, fallback rate < 1% |
| R2 | Reliability | 20-minute soak (mixed short/long) | iPhone 14 Pro | 0 deadlocks, stable memory trend |
| P1 | Performance | Time to first audio | iPhone 14 Pro, iPhone 15 | p50 < 2.5s, p95 < 4.0s |
| P2 | Performance | Real-time factor | iPhone 14 Pro, iPhone 15 | >= 1.0x realtime |
| M1 | Memory | Peak RSS during long TTS | iPhone 14 Pro | Within defined budget; no jetsam |
| G1 | Guardrail | STT regression | iPhone 14 Pro, iPhone 15 | Transcription unchanged baseline |
| G2 | Guardrail | RAG regression | iPhone 14 Pro, iPhone 15 | Answer quality/citations unchanged baseline |
| G3 | Guardrail | Summarizer regression | iPhone 14 Pro, iPhone 15 | Summary generation unchanged baseline |

## 6. OpenClaw Agent Requirements
1. Model registry ownership: artifact URL, hash, size, compatibility metadata.
2. Automatic asset verification before build and at startup.
3. Nightly device matrix runs for TTS soak and latency.
4. Release blocker rules:
- any crash in TTS flow blocks promotion
- fallback rate >= 1% blocks promotion
- STT/RAG/Summary regression blocks promotion
5. Auto-generated upgrade report with: changed artifacts, benchmark deltas, rollback decision.

## 7. Definition of Done for this migration
1. Non-Apple offline TTS works reliably on iPhone 14 Pro and iPhone 15.
2. Voice selection works from Settings.
3. On any TTS failure, app shows `No audio available at this moment` and continues.
4. STT, summarizer, and RAG remain unchanged and passing baseline tests.
5. OpenClaw automation can run full TTS regression and block bad upgrades.

If you want, next I can turn this into a day-by-day execution schedule (`Day 1` through `Day 5`) with exact implementation order and rollback checkpoints.