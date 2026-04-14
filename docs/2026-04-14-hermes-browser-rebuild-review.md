# Hermes Browser Rebuild Review for Meeting Prompter

Date: 2026-04-14
Scope: review the current iOS app and recommend a local browser-hosted rebuild that keeps compute on the Mac, is reachable from iPhone over Tailscale, and does not modify the existing iOS app code.

## Executive take

Yes, this should be rebuilt as a local web app running on the Mac instead of forcing more complexity into the iPhone app.

But no, the best version is probably not "Gemma 4 for everything."

Best practical answer:
- use a browser UI as the phone/thin-client surface
- run the models on the Mac
- expose it over Tailscale HTTPS
- use Gemma 4 for the text reasoning/summarization/Q&A core
- keep a dedicated speech stack for transcription and voice output

Reason:
- Gemma 4 supports audio input on the small E2B/E4B models and generates text output
- Gemma 4 does not solve spoken audio output by itself
- the current app’s slowest/painful path is the audio side, not the text side
- dedicated ASR + dedicated TTS is still the cleaner operator choice for low-latency local voice UX

## What the current iOS app actually is

The app is not one model. It is a staged pipeline.

Verified from repo:
- `MeetingPrompterIOS/Core/AI/ModelIDs.swift`
- `MeetingPrompterIOS/Core/AI/LeapModelManager.swift`
- `MeetingPrompterIOS/Core/AI/ASRService.swift`
- `MeetingPrompterIOS/Core/AI/SummarizationService.swift`
- `MeetingPrompterIOS/Core/AI/RAGService.swift`
- `MeetingPrompterIOS/Core/Audio/ModelTTSService.swift`
- `MeetingPrompterIOS/Retrieval/SearchIndex.swift`
- `MeetingPrompterIOS/App/ViewModels/ChatViewModel.swift`
- `README.md`

Current split:
- ASR / speech in: `LFM2.5-Audio-1.5B-Q8_0`
- summary model: `LFM2-2.6B-Transcript-Q4_K_M`
- grounded Q&A model: `LFM2-1.2B-RAG-Q5_K_M`
- speech out: `LFM2.5-Audio-1.5B-Q8_0`
- fallback speech out: Apple speech synthesis

Important detail:
- the "RAG" is not embedding/vector search right now
- `SearchIndex.swift` uses GRDB + SQLite FTS5 keyword retrieval
- query sanitization joins tokens with `OR`
- chunks are mostly newline/paragraph splits of transcript and summary

So the current app is really:
1. record audio
2. transcribe audio
3. save transcript + summary + per-meeting DB
4. lexical search over saved meeting artifacts
5. feed retrieved chunks into a small generation model
6. optionally synthesize speech reply

## What is good in the current design

Strong choices:
- session-first artifact model is good
- transcript, summary, audio, and per-session DB are persisted cleanly
- meeting-scoped retrieval is the right product behavior
- model isolation is explicit instead of magical
- the app already understands that memory pressure is real on-device

This is the right product shape.
The weak point is the runtime substrate.

## What is hurting the app

### 1. The phone is carrying too much weight

The app keeps unloading and reloading models to survive mobile memory limits.
`LeapModelManager` explicitly unloads ASR, TTS, transcript, and RAG models between stages.

That is sane on iPhone, but bad for perceived latency.

### 2. Audio is the unstable path

Your own README already says:
- audio lags in parts of the experience
- spoken answer path is less responsive than the text path
- newer iPhones are preferred

That matches the code.
The audio path is the most operationally fragile part of the app.

### 3. TTS is expensive and fussy

The current TTS path needs:
- main audio model
- tokenizer companion
- mmproj companion
- decoder/vocoder companion
- chunking/crossfading/playback logic
- fallback handling

That is a lot of machinery just to speak back an answer.

### 4. "RAG" is simpler than the label suggests

This is not a criticism. It is actually useful.
But it means the app is already mostly a:
- meeting artifact store
- lexical retriever
- answer composer

So the clean browser rebuild should preserve that simplicity instead of overengineering a vector DB first.

## Can Gemma 4 replace the stack?

## Short answer

Partially.

### Gemma 4 can replace well
- summary generation
- grounded answer generation
- some audio understanding / transcription experiments on E2B/E4B

### Gemma 4 should not be expected to replace
- high-quality TTS voice output

Verified from Google’s Gemma 4 docs:
- Gemma 4 models are multimodal
- small E2B/E4B models support audio input
- Gemma 4 generates text output
- audio docs cover ASR / speech translation / speech understanding
- docs do not position Gemma 4 as a text-to-speech output model

So:
- Gemma 4 can listen
- Gemma 4 can reason
- Gemma 4 does not natively solve the spoken reply problem you care about

## Should Gemma 4 replace ASR too?

Technically: yes, it can be tested.
Architecturally: I would not make that the default first version.

Why:
- generative multimodal audio-in is useful
- but dedicated ASR is still usually faster, cheaper, easier to tune, and easier to keep real-time-ish
- your product needs dependable meeting transcription more than "one model elegance"

So the non-cargo-cult answer is:
- use Gemma 4 for the text brain
- do not force Gemma 4 to be the entire speech stack unless benchmarks prove it wins on your hardware

## Best rebuild target

Use a local browser app on the Mac, with iPhone as remote UI over Tailscale.

Best host pattern:
- browser client on iPhone Safari
- local web server on Mac
- Hermes-agent underneath for orchestration / workers / API substrate
- optionally extend the existing Reddy phone-first local-web pattern instead of inventing a new substrate

Why this is better than continuing on-device iPhone inference:
- Mac can keep models warm
- far more RAM headroom
- easier to swap models
- easier to capture/store/export session artifacts
- easier to debug latency
- easier to add streaming and background jobs
- easier to expose privately over Tailscale

## Machine fit check

Verified on this machine:
- OS: macOS Darwin 25.2.0 arm64
- chip: Apple M2 Max
- RAM: 103079215104 bytes (~96 GiB)
- Tailscale installed: `/usr/local/bin/tailscale`
- Tailscale backend state: `Running`

This machine is absolutely a better substrate for this app than the iPhone.

## Recommended model architecture

## Option A — recommended default

Lean, fast, good quality, lowest regret.

### Components
- ASR: dedicated local speech model/server
  - preferred class: whisper.cpp / MLX Whisper / similarly optimized ASR stack
- Retrieval:
  - keep transcript + summary artifacts
  - keep per-meeting lexical retrieval first
  - optionally add embeddings later as rerank, not as v1 dependency
- LLM:
  - Gemma 4 26B A4B or another Gemma 4 text-capable serving target on Mac
- TTS:
  - dedicated local TTS such as Kokoro or Piper

### Why this wins
- fastest time to something materially better than the iPhone app
- avoids the current heavy multimodel audio-output pain
- keeps the architecture honest
- easiest to benchmark stage by stage

## Option B — more Gemma-heavy

### Components
- ASR / speech understanding: Gemma 4 E2B or E4B
- Summary + answer generation: Gemma 4 26B A4B
- TTS: still separate local TTS model

### Why this is interesting
- simpler model family story
- one family for audio understanding + reasoning

### Why I would not start here
- more uncertainty on latency and transcription reliability for long-form meeting capture
- does not remove the need for a separate TTS system anyway

## Option C — single small Gemma-first prototype

### Components
- Gemma 4 E4B for transcription + summarization + answering
- dedicated TTS only

### Why this is not my main recommendation
- good hack/demo path
- not the best production path for meeting capture quality

## What I would rebuild in the browser version

### Product surface
- Home
- New meeting
- Live transcript
- Stop/save session
- Session summary
- Ask follow-up by text
- Hold-to-talk follow-up question
- Optional spoken answer playback
- Export/share artifacts

Same product, different substrate.

### Backend state model
Per meeting keep:
- raw audio file
- transcript text
- summary markdown
- retrieval index files
- chat history
- generated answer audio files
- lightweight metadata JSON

This mirrors the iOS app’s good artifact design.

### Retrieval v1
Keep it simple:
- chunk transcript by speaker block / paragraph / sentence window
- chunk summary by section
- BM25/FTS retrieval
- optional source dedupe
- feed top chunks to Gemma 4 with explicit source-only prompt

Do not start with a vector DB just because the word RAG is fashionable.

## How Hermes-agent should fit

Best fit is not "Hermes as the model."
Best fit is:
- Hermes-agent as the operator/runtime substrate
- local model server(s) as specialist engines
- browser UI as the control surface

Suggested split:
- browser app / Reddy-style thin client: session UX
- local model adapter: Gemma 4 + ASR + TTS endpoints
- Hermes-agent: workflow orchestration, background jobs, export handling, optional specialist workers

If you want to keep this aligned with your existing direction, the cleanest path is probably:
- extend the existing Reddy-style local web control surface
- add a meeting-prompter product slice there
- keep the current iPhone app untouched as the old branch of the product

## Tailscale access path

Yes, this is the right access model.

Use:
- local app bound on the Mac
- Tailscale HTTPS serve to expose it privately to the tailnet
- open the `https://...ts.net` URL from iPhone Safari

Why HTTPS matters:
- iPhone browser mic access wants a secure context
- raw `http://100.x.x.x:port` is the wrong UX for browser mic features
- Tailscale HTTPS gives you private access plus browser permission compatibility

## Concrete recommendation

Build this as a local browser app on the Mac.

Recommended v1 stack:
- UI/runtime shell: Hermes-agent + Reddy-style web app
- ASR: dedicated local speech service
- Retrieval: per-meeting FTS/BM25
- LLM: Gemma 4 as the main summarization/Q&A brain
- TTS: dedicated local TTS service
- network access: Tailscale HTTPS

## What to avoid

Avoid these traps:
- "one model for everything" because it sounds elegant
- vector DB first, before proving lexical retrieval is insufficient
- rebuilding the whole old app architecture inside Hermes without simplifying it
- browser mic over insecure raw IP instead of Tailscale HTTPS
- making the phone do inference when the Mac is sitting there with 96 GiB RAM

## Practical first implementation order

1. Build the session/artifact API on the Mac
2. Build browser pages for record, session list, summary, and chat
3. Wire browser mic upload / push-to-talk to backend ASR
4. Add transcript save + summary generation with Gemma 4
5. Add meeting-scoped retrieval + grounded answer generation
6. Add TTS playback/export
7. Expose over Tailscale HTTPS
8. Benchmark stage latency and compare against the iPhone app

## Final verdict

Yes, you should recreate this as a local browser-hosted Hermes app on the Mac.

Yes, Gemma 4 belongs in the new version.

No, Gemma 4 should probably not be forced to replace every component.

My recommendation:
- Gemma 4 for the reasoning core
- dedicated ASR for transcription
- dedicated TTS for voice output
- browser UI over Tailscale
- Hermes-agent/Reddy as the runtime shell

That gets you leaner, faster, easier to operate, and probably materially better audio UX than the current iPhone-first stack.
