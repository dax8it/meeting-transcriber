# Audio / TTS Notes

This note captures the current public-facing baseline for the audio reply path.

It is intentionally short and focused on what contributors should know right now.

## Current baseline

At the current baseline:
- Voice Q&A works end-to-end on device
- `ModelTTSService` handles spoken replies
- reply audio can be exported/shared when the path succeeds

## Current caveats

Contributors should assume the following until improved by measurement:
- audio reply performance is still not fully optimized
- spoken replies can lag behind the text answer path
- newer iPhones provide a better experience than older devices
- known test baseline includes **iPhone 14 Pro**

## Guidance

For now:
- avoid broad audio/TTS rewrites unless there is a clear user-visible failure
- prefer minimal, scoped fixes
- treat latency and reliability work as bounded experiments, not open-ended churn

## What counts as a meaningful regression

Prioritize investigation if any of these become user-visible:
- no spoken audio playback
- broken share/export flow for generated reply audio
- repeated fallback/failure loops
- crashes or deadlocks in the voice reply path

## Source of truth

For actual current implementation details, check:
- `MeetingPrompterIOS/Core/Audio/ModelTTSService.swift`
- `MeetingPrompterIOS/App/ViewModels/ChatViewModel.swift`
- `MeetingPrompterIOS/Core/AI/ASRService.swift`
- `MeetingPrompterIOS/Core/AI/RAGService.swift`
