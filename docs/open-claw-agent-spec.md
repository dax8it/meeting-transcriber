Use this as your OpenClaw setup spec for an offline iOS edge-AI app team.

**1) Global Rules (apply to every agent)**
1. Hard constraints: fully offline, no cloud calls, iOS-first, target iPhone 15 and iPhone 14 Pro minimum.
2. Data policy: no remote telemetry, only local logs and local model files.
3. Module boundary: STT, summarizer, RAG, TTS are separate subsystems with strict interfaces.
4. Change control: each agent owns specific files/folders and cannot edit outside ownership without a handoff request.
5. Output contract: every task returns `Decision`, `Patch`, `Tests`, `Risks`, `Rollback`.

**2) A-Team Agent Roster**
1. `Chief-Orchestrator`: routes work, resolves conflicts, enforces constraints, approves merges.
2. `iOS-Architect`: defines app architecture, module boundaries, DI, lifecycle, threading model.
3. `STT-Agent`: owns on-device transcription stack and microphone flow; optimizes latency/accuracy.
4. `RAG-Agent`: owns embeddings/retrieval/chunking/context assembly and answer quality.
5. `Summarizer-Agent`: owns summary generation and meeting-structure outputs.
6. `TTS-Agent`: owns speech synthesis pipeline (model loading, inference, playback queue, fallback behavior).
7. `Audio-Systems-Agent`: owns AVAudioSession, buffer formats, interruptions, sample-rate conversion, clipping/noise handling.
8. `Edge-Model-Agent`: owns model packaging, quantization choices, memory budgets, warmup/caching, artifact validation.
9. `Swift-Concurrency-Agent`: owns actors, cancellation, timeouts, deadlock prevention, stuck-spinner fixes.
10. `iOS-UX-Design-Agent`: owns visual design, push-to-talk prominence, accessibility, HIG compliance, interaction polish.
11. `QA-Regression-Agent`: owns test matrix, device sweeps, fail/retry scenarios, performance baselines.
12. `Release-Guard-Agent`: owns build reproducibility, feature flags, migration safety, release checklist.

**3) Ownership Map**
1. UI/UX: `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/App/Views`
2. View models: `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/App/ViewModels`
3. AI runtime/services: `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Core/AI`
4. Audio/session: `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Core/Audio` (or equivalent audio folder)
5. Model artifacts/config: `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/models`
6. Tests: `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOSTests` and `/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOSUITests`

**4) Agentic Execution Flow (event-driven, not calendar-driven)**
1. `Chief-Orchestrator` creates a task graph from product goals.
2. `iOS-Architect` publishes contracts/interfaces first.
3. Implementation agents (`STT`, `RAG`, `Summarizer`, `TTS`, `Audio`, `Edge-Model`, `Concurrency`, `UX`) run in parallel on non-overlapping ownership.
4. `QA-Regression-Agent` runs continuously on every merged patch.
5. `Release-Guard-Agent` blocks merge if any hard gate fails.
6. `Chief-Orchestrator` resolves conflicts and triggers rollback if regression appears.

**5) Required Gates Before “Done”**
1. Functional: transcription, summary, Q&A, and voice playback all pass end-to-end offline.
2. Stability: no crash, no stuck spinner, no deadlock, no repeated fallback loop.
3. Audio quality: no clipping/high-pitch artifacts, proper drain completion.
4. Performance: acceptable first-response latency and sustained playback on iPhone 14 Pro/15.
5. UX: push-to-talk visible and reliable, accessibility labels, large readable transcript area.
6. Privacy: permissions declared and justified in Info.plist, no network dependency for core flow.

**6) OpenClaw Agent Template**
1. `Name`
2. `Mission`
3. `Owned Paths`
4. `Inputs`
5. `Outputs`
6. `Can Edit`
7. `Cannot Edit`
8. `Success Metrics`
9. `Failure Triggers`
10. `Escalation Target`

If you want, I can generate the exact 12 OpenClaw agent definitions in a ready-to-paste JSON/TOML format next.