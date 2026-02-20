# Meeting Transcriber iOS — MVP

> **Status (2026-02-19): historical MVP reference.**
>
> The current runtime source-of-truth for model IDs and loading behavior is:
> - `MeetingPrompterIOS/Core/AI/ModelIDs.swift`
> - `MeetingPrompterIOS/Core/AI/LeapModelManager.swift`
>
> Some model filename examples below reflect older MVP snapshots and should not override current in-code IDs.

This repo implements an offline-first, fully on-device iOS MVP with two explicit actions:

1) Record Meeting (ASR) -> produces a transcript and stores/indexes it locally as the **current meeting**
2) Ask Question (RAG) -> user types a question; RAG answers using **only** the stored transcript evidence

## 1) Source of Truth

- Open the app project in Xcode via: `meeting-transcriber.xcodeproj`
- App source code lives under: `MeetingPrompterIOS/`
- The app is designed to run fully offline (Airplane Mode).

## 2) Models (Required) + Expected Folders

These models must be present in the app bundle (Copy Bundle Resources / target membership):

### A) Audio (ASR) model + companions

Expected folder in repo (and ideally in bundle):
- `MeetingPrompterIOS/models/audio/`

Required files:
- `MeetingPrompterIOS/models/audio/LFM2.5-Audio-1.5B-Q4_0.gguf`
- `MeetingPrompterIOS/models/audio/tokenizer-LFM2.5-Audio-1.5B-Q4_0.gguf`
- `MeetingPrompterIOS/models/audio/mmproj-LFM2.5-Audio-1.5B-Q4_0.gguf`

Notes:
- The ASR pipeline uses the system prompt `Perform ASR.`
- The tokenizer + mmproj are required for audio support.

### B) Text (RAG) model(s)

Expected folder in repo (and ideally in bundle):
- `MeetingPrompterIOS/models/text/`

Required files:
- `MeetingPrompterIOS/models/text/LFM2-1.2B-RAG-Q5_K_M.gguf` (or thinking later)


## 3) iOS Resource Flattening (Important)

Xcode/iOS can flatten bundle resources at runtime (i.e., files end up directly under:
`.../YourApp.app/<filename>` instead of `.../YourApp.app/models/audio/<filename>`).

Because of this, model lookup must be resilient:
- First try `Bundle.main.url(forResource:withExtension:subdirectory:)`
- If nil, fall back to `Bundle.main.url(forResource:withExtension:)`

Additionally:
- Audio companion discovery (tokenizer/mmproj) must scan **next to the resolved ASR model URL** (same directory as the resolved `.gguf`), not assume a hardcoded folder.

## 4) Target Membership + Copy Bundle Resources Checklist

For each required model file:

1) In Xcode, click the file in the Project Navigator
2) In the File Inspector (right panel):
   - Ensure the file is checked under **Target Membership** for the iOS app target
3) In the target Build Phases:
   - Ensure the file appears in **Copy Bundle Resources**

If ASR fails with a message like "audio support is not enabled" or "tokenizer missing":
- Confirm `tokenizer-...gguf` and `mmproj-...gguf` are present in Copy Bundle Resources

## 5) MVP Option 1 Flow (Record -> Save -> Ask)

### A) Record Meeting (ASR)

- Tap/hold Push-to-talk
- Live transcript updates while recording

### B) Stop -> finalize transcript -> store/index as "current meeting"

On stop:
- Final transcript is shown as `transcriptFinal`
- Transcript is stored/indexed as the **current meeting**
- App returns to `.idle` so the user can record again

Expected logs:
- `[ASR] transcription finished, len=..., preview='...'`
- `[SearchIndex] Current meeting transcript indexed, chunks=...`
- `[MainViewModel] Current meeting transcript saved, length=...`

### C) Ask Question (RAG)

- Type a question into the text field
- Tap `Ask`
- Retrieval searches only the current meeting transcript
- RAG answers using only retrieved evidence

Expected logs:
- `[SearchIndex] searchCurrentMeeting queryLen=..., topK=...`
- `[MainViewModel] askQuestion length=..., chunks=...`
- `[RAG] generateAnswer(question:chunks:) ...`

## 6) Key File Map

### UI
- `MeetingPrompterIOS/ContentView.swift`
  - Push-to-talk UI
  - Question text field + Ask button
- `MeetingPrompterIOS/Views/TranscriptView.swift`
  - Displays `transcriptLive` / `transcriptFinal`
- `MeetingPrompterIOS/Views/AnswerView.swift`
  - Displays `answerText`
- `MeetingPrompterIOS/Views/SourcesView.swift`
  - Displays retrieved `sources`

### ViewModel / Flow
- `MeetingPrompterIOS/App/ViewModels/MainViewModel.swift`
  - `startRecording()`
  - `stopRecording()` -> saves/indexes current meeting transcript, returns to idle
  - `askQuestion(_:)` -> runs retrieval + RAG

### ASR
- `MeetingPrompterIOS/Core/Audio/PushToTalkController.swift`
  - Orchestrates audio capture and calls ASR
- `MeetingPrompterIOS/Core/AI/ASRService.swift`
  - Calls LeapSDK with system prompt `Perform ASR.`

### Retrieval (Current Meeting)
- `MeetingPrompterIOS/Retrieval/SearchIndex.swift`
  - `setCurrentMeetingTranscript(_:)`
  - `searchCurrentMeeting(query:topK:)`

### RAG
- `MeetingPrompterIOS/Core/AI/RAGService.swift`
  - `generateAnswer(question:chunks:)` (uses provided current-meeting chunks)

### Model Loading / Isolation
- `MeetingPrompterIOS/Core/AI/LeapModelManager.swift`
  - Loads ASR + RAG runners
  - Finds ASR companions (tokenizer/mmproj)
  - Loads RAG in **text engine** mode (no mmproj/tokenizer)
  - Uses sandbox staging (Application Support) to isolate text RAG from audio companions

## 7) Known Failure Modes + Fixes

### A) ASR returns empty transcript
Symptoms:
- `transcriptFinal` is empty
- `[PushToTalk] Transcription result:` is blank

Fixes:
- Confirm ASR model and companions are present (tokenizer + mmproj)
- Confirm audio buffer is non-empty (`[PushToTalk] Got full buffer with ... samples`)

### B) "audio support is not enabled" / tokenizer missing
Symptoms:
- ASR throws a modelNotFound error mentioning missing tokenizer/mmproj

Fixes:
- Ensure tokenizer + mmproj are in Target Membership and Copy Bundle Resources
- Ensure companion discovery scans the directory of the resolved ASR model URL

### C) RAG uses audio engine / invalid system prompt
Symptoms:
- Logs show `lfm2_audio_engine` during RAG
- Errors mention supported prompts are `Perform ASR` / `Perform TTS` / interleaved audio

Fixes:
- Ensure RAG model is loaded from `models/text` and options set `mmProjPath=nil`, `audioTokenizerPath=nil`, `audioDecoderPath=nil`
- Prefer sandbox staging for text models so LeapSDK cannot auto-detect audio companions
- Confirm logs include: `Using text engine`

### D) Ask returns no chunks
Symptoms:
- `[SearchIndex] No current meeting transcript indexed`
- `chunks=0` in MainViewModel ask logs

Fixes:
- Record a meeting first and confirm `setCurrentMeetingTranscript` ran
- Confirm stopRecording returns to idle after indexing

### E) App stuck in transcribing/searching/answering
Fixes:
- Ensure state updates are performed on MainActor
- Ensure error paths set `.error(error)` and do not silently return

## 8) Verification Checklist (Known-good)

1) Open `meeting-transcriber.xcodeproj`
2) Clean build: Shift+Cmd+K
3) Build: Cmd+B
4) Run on device: Cmd+R
5) Record:
   - Tap mic, speak, stop
   - See live transcript updates while recording
   - See final transcript after stopping
   - Confirm log: `[MainViewModel] Current meeting transcript saved, length=...`
6) Ask:
   - Type a question and tap Ask
   - Confirm `chunks > 0`
   - Confirm RAG uses `Using text engine`
   - Answer + sources display
7) Airplane Mode sanity check:
   - Enable Airplane Mode
   - Repeat Ask (should still work)

---

## 9) Known-good Commit Checklist (Do This Before You Commit)

This repo can get messy because Xcode + models + generated build artifacts create a lot of noise. Use this checklist to keep commits clean and reproducible.

### A) Quick status + sanity check
Run:
- `git status`

You want:
- **No accidental deletions** of existing app files (especially `meeting-transcriber/Assets.xcassets`, app entrypoints, etc.)
- No huge surprise additions (e.g. a second app tree, duplicate Xcode project, etc.)

If you see “deleted:” entries you did not intend:
- `git restore --staged <path>` (unstage deletion)
- `git restore <path>` (restore file in working directory)

---

### B) What to stage (typically OK)
✅ **Stage these:**
- Swift source changes in `MeetingPrompterIOS/**.swift`
- `MeetingPrompterIOS/Resources/docpack.json` (if you intentionally changed it)
- New docs: `MVP.md`, `ARCHITECTURE_IOS.md`, `README.md`, `SETUP.md`, `QUICKSTART.md`
- Minimal, intentional Xcode project changes:
  - `meeting-transcriber.xcodeproj/project.pbxproj` **ONLY** if you knowingly changed Build Phases / Copy Bundle Resources / target membership / package references

> Tip: If `project.pbxproj` changed and you don’t know why, don’t commit it.

---

### C) What NOT to stage (avoid committing these)
🚫 **Do NOT commit generated build artifacts:**
- `.build/`
- `DerivedData/` (usually not inside repo, but if it is: don’t commit)
- `*.xcuserstate`, `xcuserdata/`, personal workspace settings

🚫 **Avoid committing large model binaries unless you explicitly want them in git:**
- `**/*.gguf`
- `**/*.bin`
- `**/*.bundle` (model bundles)

Committing models makes the repo huge and slow to clone. Prefer storing them outside git and downloading/copying them as a setup step.

---

### D) How to avoid committing binaries (recommended)
1) Add patterns to `.gitignore` (if you choose to do this):
   - `.build/`
   - `**/*.gguf`
   - `**/*.bin`
   - `**/*.bundle`

2) If binaries are already staged by accident:
- `git restore --staged MeetingPrompterIOS/models/**/*.gguf`
- `git restore --staged MeetingPrompterIOS/models/**/*.bundle`

(Repeat for any other binary patterns.)

3) If binaries were already committed in the past and you want them removed later:
- That requires a deliberate cleanup plan (possibly history rewrite). Don’t do this casually.

---

### E) Avoid committing accidental “duplicate app trees”
If you see both:
- `meeting-transcriber/` (old tree)
- `MeetingPrompterIOS/` (current tree)

Decide which is the real app. For this project, the known-good source is:
- open `meeting-transcriber.xcodeproj`
- app sources in `MeetingPrompterIOS/`

So **do not delete** the old tree unless you’re intentionally migrating and you’re sure you won’t break history.

---

### F) Minimal clean commit flow (safe sequence)
1) Unstage everything:
- `git reset`

2) Stage only what you want:
- `git add MVP.md`
- `git add MeetingPrompterIOS/**/*.swift`
- `git add MeetingPrompterIOS/Resources/docpack.json` (only if changed intentionally)
- `git add meeting-transcriber.xcodeproj/project.pbxproj` (only if you intentionally changed it)

3) Review:
- `git diff --staged`

4) Commit:
- `git commit -m "MVP: on-device ASR + current-meeting RAG flow"`

---

### G) Final “Green” check before pushing
- Clean build (Shift+Cmd+K)
- Run on device
- Record -> stop -> transcript saved/indexed -> idle
- Ask -> answer + sources visible
