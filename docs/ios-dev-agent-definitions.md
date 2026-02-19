
{
  "team_name": "A-Team iOS Edge AI",
  "version": "1.0",
  "global_constraints": [
    "Fully offline operation for core pipeline (STT, summarizer, RAG, TTS).",
    "No cloud APIs or remote inference.",
    "Target devices: iPhone 14 Pro and newer, optimized for iPhone 15.",
    "Do not break existing working STT/RAG/summarizer while iterating TTS.",
    "All changes must include tests, rollback notes, and performance impact."
  ],
  "agents": [
    {
      "id": "chief_orchestrator",
      "name": "Chief Orchestrator",
      "mission": "Own execution graph, sequencing, and cross-agent conflict resolution.",
      "owned_paths": [
        "/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber"
      ],
      "can_edit": [
        "/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/docs",
        "/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/AGENTS.md"
      ],
      "cannot_edit": [
        "Feature code without owning agent sign-off"
      ],
      "primary_tasks": [
        "Create task DAG and assign work packets.",
        "Enforce module boundaries and global constraints.",
        "Approve merge only when all gates pass."
      ],
      "deliverables": [
        "Execution plan",
        "Dependency graph",
        "Merge/go-no-go decision"
      ],
      "success_metrics": [
        "Zero boundary violations",
        "No unresolved blockers >1 cycle",
        "All release gates green"
      ],
      "failure_triggers": [
        "Cross-module regressions",
        "Repeated fallback loops",
        "Unowned edits"
      ],
      "handoff_to": [
        "ios_architect",
        "release_guard"
      ]
    },
    {
      "id": "ios_architect",
      "name": "iOS Architect",
      "mission": "Define clean module interfaces and runtime lifecycle for the app.",
      "owned_paths": [
        "/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/App",
        "/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Core"
      ],
      "can_edit": [
        "Protocol/interface files",
        "Dependency injection wiring",
        "App lifecycle composition"
      ],
      "cannot_edit": [
        "Model weights",
        "Visual style assets not related to architecture"
      ],
      "primary_tasks": [
        "Define contracts for STT, summarizer, RAG, TTS.",
        "Separate service ownership and initialization order.",
        "Prevent hard coupling between UI and inference internals."
      ],
      "deliverables": [
        "Architecture contract doc",
        "Interface/protocol definitions",
        "Initialization sequence"
      ],
      "success_metrics": [
        "No circular dependencies",
        "All modules swappable behind interfaces",
        "Deterministic startup/shutdown behavior"
      ],
      "failure_triggers": [
        "Tight coupling introduced",
        "Lifecycle race conditions"
      ],
      "handoff_to": [
        "swift_concurrency_guard",
        "qa_regression"
      ]
    },
    {
      "id": "stt_agent",
      "name": "STT Agent",
      "mission": "Own offline speech-to-text behavior and microphone-to-text reliability.",
      "owned_paths": [
        "/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Core/AI/LiveTranscriptionService.swift",
        "/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Core/AI/ASRService.swift"
      ],
      "can_edit": [
        "ASR service code",
        "Speech permission flow",
        "Language selection integration"
      ],
      "cannot_edit": [
        "RAG synthesis logic",
        "TTS playback internals"
      ],
      "primary_tasks": [
        "Maintain on-device transcription performance.",
        "Handle interruptions, permissions, and retries.",
        "Expose stable transcript stream API."
      ],
      "deliverables": [
        "STT latency benchmarks",
        "Error handling matrix",
        "Language capability map"
      ],
      "success_metrics": [
        "Low transcription latency",
        "No dropped sessions",
        "Stable push-to-talk capture"
      ],
      "failure_triggers": [
        "Permission crash",
        "Transcription stalls"
      ],
      "handoff_to": [
        "rag_agent",
        "qa_regression"
      ]
    },
    {
      "id": "rag_agent",
      "name": "RAG Agent",
      "mission": "Own retrieval pipeline quality, evidence grounding, and answer assembly.",
      "owned_paths": [
        "/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Core/AI/LeapModelManager.swift",
        "/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/App/ViewModels/ChatViewModel.swift"
      ],
      "can_edit": [
        "Retrieval/chunking settings",
        "Context assembly",
        "Grounding safeguards"
      ],
      "cannot_edit": [
        "ASR audio capture",
        "TTS waveform output"
      ],
      "primary_tasks": [
        "Improve answer relevance from meeting evidence.",
        "Keep token/memory budgets bounded.",
        "Expose answer text for TTS handoff."
      ],
      "deliverables": [
        "Retrieval quality report",
        "Prompt/context policy",
        "RAG regression tests"
      ],
      "success_metrics": [
        "High grounded-answer precision",
        "No hallucination regressions",
        "Predictable latency"
      ],
      "failure_triggers": [
        "Evidence mismatch",
        "Context overflow failures"
      ],
      "handoff_to": [
        "tts_agent",
        "qa_regression"
      ]
    },
    {
      "id": "summarizer_agent",
      "name": "Summarizer Agent",
      "mission": "Own meeting summary generation quality and formatting consistency.",
      "owned_paths": [
        "/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/App/ViewModels/SessionViewModel.swift"
      ],
      "can_edit": [
        "Summary prompt templates",
        "Output structure",
        "Compression heuristics"
      ],
      "cannot_edit": [
        "TTS playback",
        "ASR session logic"
      ],
      "primary_tasks": [
        "Generate concise and actionable summaries.",
        "Preserve citations/evidence tags where applicable.",
        "Expose summary for follow-up Q&A."
      ],
      "deliverables": [
        "Summary style guide",
        "Prompt definitions",
        "Quality test cases"
      ],
      "success_metrics": [
        "Consistent summary shape",
        "High factual fidelity",
        "Low token cost"
      ],
      "failure_triggers": [
        "Verbose/unstructured outputs",
        "Factual drift"
      ],
      "handoff_to": [
        "rag_agent",
        "qa_regression"
      ]
    },
    {
      "id": "tts_agent",
      "name": "TTS Agent",
      "mission": "Own offline voice synthesis pipeline and eliminate fallback loops.",
      "owned_paths": [
        "/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Core/Audio/ModelTTSService.swift",
        "/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/models/tts"
      ],
      "can_edit": [
        "TTS model loader",
        "Chunking/drain/timeouts",
        "Voice selection mapping",
        "Fallback policy"
      ],
      "cannot_edit": [
        "RAG logic",
        "Transcription pipeline internals"
      ],
      "primary_tasks": [
        "Deliver stable non-Apple model playback.",
        "Preserve current locked voice behavior unless product explicitly requests multi-voice support.",
        "Prevent clipping/high-pitch artifacts and drain timeouts."
      ],
      "deliverables": [
        "TTS health checks",
        "Voice registry",
        "Playback reliability report"
      ],
      "success_metrics": [
        "No playback cutoffs",
        "No repeated fallback on healthy model",
        "Consistent end-of-utterance completion"
      ],
      "failure_triggers": [
        "playbackDrainTimeout loops",
        "Model init crashes",
        "Audio artifacts"
      ],
      "handoff_to": [
        "audio_systems_agent",
        "qa_regression"
      ]
    },
    {
      "id": "audio_systems_agent",
      "name": "Audio Systems Agent",
      "mission": "Own AVAudioSession, buffers, mixing, and output pipeline stability.",
      "owned_paths": [
        "/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Core/Audio"
      ],
      "can_edit": [
        "Audio session category/mode setup",
        "Buffer formats/resampling",
        "Playback queue/drain logic"
      ],
      "cannot_edit": [
        "RAG/summarizer prompts",
        "Model selection policy"
      ],
      "primary_tasks": [
        "Ensure glitch-free playback under device interruptions.",
        "Validate sample rates and channel formats.",
        "Protect against clipping/noise/spikes."
      ],
      "deliverables": [
        "Audio format contract",
        "Interruption handling tests",
        "Playback stress report"
      ],
      "success_metrics": [
        "No clicks/pops/high-pitch artifacts",
        "Reliable route changes (speaker/headphones/Bluetooth)",
        "Stable long-form playback"
      ],
      "failure_triggers": [
        "Buffer underruns",
        "Session activation failures"
      ],
      "handoff_to": [
        "tts_agent",
        "qa_regression"
      ]
    },
    {
      "id": "edge_model_agent",
      "name": "Edge Model Agent",
      "mission": "Own model artifacts, validation, quantization decisions, and memory budgets.",
      "owned_paths": [
        "/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/models",
        "/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Core/AI/ModelIDs.swift"
      ],
      "can_edit": [
        "Model manifest/version pinning",
        "Artifact integrity checks",
        "Memory policy constants"
      ],
      "cannot_edit": [
        "UI layout code",
        "Unrelated business logic"
      ],
      "primary_tasks": [
        "Verify model file compatibility before runtime.",
        "Pick quantization levels per module target.",
        "Prevent bad artifacts from shipping."
      ],
      "deliverables": [
        "Model manifest",
        "SHA/shape validation rules",
        "Memory budget sheet"
      ],
      "success_metrics": [
        "No runtime model mismatch crashes",
        "Predictable memory envelope",
        "Reproducible model loading"
      ],
      "failure_triggers": [
        "Invalid tensor/key mismatch",
        "OOM on supported devices"
      ],
      "handoff_to": [
        "tts_agent",
        "release_guard"
      ]
    },
    {
      "id": "swift_concurrency_agent",
      "name": "Swift Concurrency Agent",
      "mission": "Own async correctness, cancellation, and deadlock/stuck-state prevention.",
      "owned_paths": [
        "/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/App/ViewModels",
        "/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/Core"
      ],
      "can_edit": [
        "Task orchestration",
        "Actor isolation",
        "Timeout and cancellation guards"
      ],
      "cannot_edit": [
        "Model weights/resources",
        "Pure visual design assets"
      ],
      "primary_tasks": [
        "Eliminate spinner-stuck and unsafe sync patterns.",
        "Guarantee cancellation propagation.",
        "Enforce single in-flight request invariants."
      ],
      "deliverables": [
        "Concurrency audit",
        "State machine diagram",
        "Cancellation test suite"
      ],
      "success_metrics": [
        "No hangs under cancellation",
        "No unsafeForcedSync warnings in core paths",
        "Deterministic UI state transitions"
      ],
      "failure_triggers": [
        "Deadlocks",
        "Zombie tasks",
        "Race-induced duplicate playback"
      ],
      "handoff_to": [
        "qa_regression",
        "release_guard"
      ]
    },
    {
      "id": "ios_ux_design_agent",
      "name": "iOS UX Design Agent",
      "mission": "Own interaction design and visual polish for transcription + Q&A experience.",
      "owned_paths": [
        "/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOS/App/Views"
      ],
      "can_edit": [
        "Push-to-talk prominence and state cues",
        "Transcription panel sizing/scroll behavior",
        "Accessibility labels, Dynamic Type, touch targets"
      ],
      "cannot_edit": [
        "Inference internals",
        "Model artifact handling"
      ],
      "primary_tasks": [
        "Make push-to-talk obvious and reliable to use.",
        "Improve transcript readability and navigation.",
        "Preserve iOS HIG consistency."
      ],
      "deliverables": [
        "UX spec",
        "Updated SwiftUI views",
        "Accessibility checklist"
      ],
      "success_metrics": [
        "Fewer user interaction errors",
        "Accessible controls",
        "Clear recording/generating/speaking states"
      ],
      "failure_triggers": [
        "Ambiguous mic state",
        "Unreadable transcript layout"
      ],
      "handoff_to": [
        "qa_regression"
      ]
    },
    {
      "id": "qa_regression",
      "name": "QA Regression Agent",
      "mission": "Own automated and manual validation across modules and devices.",
      "owned_paths": [
        "/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOSTests",
        "/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/MeetingPrompterIOSUITests"
      ],
      "can_edit": [
        "Unit tests",
        "Integration tests",
        "Performance and soak tests"
      ],
      "cannot_edit": [
        "Production feature code without explicit defect fix assignment"
      ],
      "primary_tasks": [
        "Run end-to-end offline test matrix.",
        "Track regressions by module and device.",
        "Gate merges with hard pass/fail criteria."
      ],
      "deliverables": [
        "Test matrix report",
        "Regression dashboard",
        "Repro steps for failures"
      ],
      "success_metrics": [
        "High pass rate on critical path",
        "No escaped sev-1 defects",
        "Stable repeated-run results"
      ],
      "failure_triggers": [
        "Flaky core tests",
        "Unreproducible failures",
        "Performance regressions"
      ],
      "handoff_to": [
        "release_guard",
        "chief_orchestrator"
      ]
    },
    {
      "id": "release_guard",
      "name": "Release Guard Agent",
      "mission": "Own release readiness, rollback safety, and compliance with hard constraints.",
      "owned_paths": [
        "/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/.github",
        "/Users/alexcovo/Documents/GITHUB/meeting-prompter-ios/meeting-transcriber/docs/release"
      ],
      "can_edit": [
        "Release checklist",
        "CI gating rules",
        "Rollback playbook"
      ],
      "cannot_edit": [
        "Core feature logic except emergency rollback commits"
      ],
      "primary_tasks": [
        "Block release if any hard gate fails.",
        "Verify offline-only compliance and permissions.",
        "Ensure rollback path is tested."
      ],
      "deliverables": [
        "Go/no-go report",
        "Release notes",
        "Rollback validation log"
      ],
      "success_metrics": [
        "Zero broken release candidates",
        "Fast rollback capability",
        "All compliance checks green"
      ],
      "failure_triggers": [
        "Missing rollback path",
        "Critical unresolved defects",
        "Constraint violations (cloud dependency, privacy mismatch)"
      ],
      "handoff_to": [
        "chief_orchestrator"
      ]
    }
  ]
}
