# Audio / TTS Notes (Current Locked Baseline)

## Working baseline (2026-02-19)
- Voice Q&A pipeline is working end-to-end on device for multi-turn responses.
- `ModelTTSService` uses Leap audio generation with conservative chunking + buffered playback.
- Assistant reply WAV export and user share flow are working in observed runs.

## Warning triage from latest device tails
- `NSOSStatusErrorDomain Code=-50` during primary playback session setup:
  - Currently recoverable in-app (conservative session fallback succeeds).
  - Treat as monitor-only unless playback starts failing.
- Share/LaunchServices warnings (`-10814`, `NSCocoaErrorDomain 256`, `canmaplsdatabase`):
  - Observed alongside successful sharing.
  - Treat as platform/service noise unless user-visible share failure returns.
- `RBSServiceErrorDomain client not entitled`, `IOSurface creation failed`, `CFMessagePort/PPT`:
  - Not currently correlated with transcription/TTS pipeline failures.

## Lock-down guidance
- Do not refactor TTS/share architecture while current path remains stable.
- Only allow minimal, scoped edits for clear user-visible regressions:
  - no audio playback,
  - share action fails for users,
  - crash/deadlock,
  - repeated fallback loops.
