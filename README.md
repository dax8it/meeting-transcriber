# Meeting Prompter iOS

An iOS app that provides real-time meeting assistance with local AI processing. The app uses push-to-talk audio capture, live transcription, and hybrid RAG (Retrieval-Augmented Generation) to answer questions based on local documents - all completely offline.

## Features

- **Push-to-Talk Recording**: Hold the microphone button to speak your question
- **Live Transcription**: Real-time transcription during recording with rate limiting
- **Local Document Search**: BM25 ranking over SQLite FTS5 index
- **RAG Answers**: Retrieves relevant documents, extracts evidence, and generates answers using LFM2-1.2B-RAG
- **100% Offline**: All processing happens on-device, works in Airplane Mode
- **Privacy-First**: No data sent to external servers

## Requirements

- iOS 15.0+
- Xcode 15.0+
- Physical iOS device (simulator may have performance limitations)

## Installation

### 1. Add Swift Package Dependencies

Open your Xcode project and add the required packages:

**Leap SDK (LEAP Edge SDK)**:
```
File -> Add Package Dependencies
URL: https://github.com/Liquid4All/leap-ios.git
Version: 0.7.0 or newer
Add "LeapSDK" product to your app target
```

**GRDB (SQLite wrapper)**:
```
File -> Add Package Dependencies
URL: https://github.com/groue/GRDB.swift.git
Version: 7.0 or newer
Add "GRDB" product to your app target
```

### 2. Add Model Files

Download the required Liquid AI models and add them to your app bundle:

1. Download these model files in .gguf format:
   - `LFM2-Audio-1.5B.gguf` - for speech recognition (ASR)
   - `LFM2-1.2B-RAG.gguf` - for answer generation

2. In Xcode, drag the `.gguf` files into your project
3. In the "Choose options for adding these files" dialog:
   - ✅ Copy items if needed
   - ✅ Create groups
   - ✅ Add to targets: [Your App Target]

4. Verify the .gguf files appear in Xcode's file navigator under your project

### 3. Add Document Pack

The app includes a bundled `docpack.json` file with sample documents. To add your own:

1. Create a JSON file named `docpack.json` with this structure:

```json
{
  "version": "1.0.0",
  "chunks": [
    {
      "id": "unique-id-1",
      "title": "Document Title",
      "sectionPath": "Section > Subsection",
      "text": "The content of your document chunk...",
      "metadata": {
        "category": "guide",
        "updated": "2026-01-10"
      }
    }
  ]
}
```

2. Add `docpack.json` to your app bundle (same as model bundles)

### 4. Configure Build Settings

Ensure these build settings are configured:

- **Minimum Deployment Target**: iOS 15.0
- **Swift Language Version**: Swift 5.9+
- **Other Linker Flags**: Add `-ObjC` (if experiencing issues with SDK)

### 5. Request Permissions

Add these to your `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Meeting Prompter needs microphone access to record your questions for transcription.</string>
```

## Running on Device

### Physical Device (Recommended)

1. Connect your iOS device via USB
2. Select your device from the scheme selector
3. Click Product → Run (⌘+R)
4. Grant microphone permissions when prompted

### Simulator

The app can run on simulator, but:
- Model inference may be slow
- Microphone simulation is limited
- Physical device testing is recommended

## Project Structure

```
MeetingPrompteriOS/
├── MeetingPrompteriOSApp.swift      # App entry point
├── ContentView.swift                 # Main UI
├── Core/
│   ├── AppState.swift                # App state management
│   ├── Audio/
│   │   ├── AudioCaptureService.swift # AVAudioEngine capture
│   │   ├── VADGate.swift             # Voice activity detection
│   │   └── PushToTalkController.swift # PTT logic
│   ├── AI/
│   │   ├── LeapModelManager.swift    # Model loading/lifecycle
│   │   ├── ASRService.swift          # Speech recognition
│   │   └── RAGService.swift          # RAG orchestration
│   └── Utils/
│       ├── TaskQueue.swift           # Task management
│       └── Logger.swift              # Logging utility
├── Retrieval/
│   ├── DocumentChunk.swift           # Data model
│   ├── DocPackLoader.swift           # Load bundled docs
│   └── SearchIndex.swift             # SQLite FTS5 + BM25
├── Grounding/
│   └── SentenceSelector.swift        # Evidence extraction
├── Views/
│   ├── TranscriptView.swift          # Live transcript UI
│   ├── AnswerView.swift              # Answer display
│   └── SourcesView.swift             # Source citations
└── Resources/
    └── docpack.json                  # Bundled documents
```

## Performance Tips

1. **Close other apps** when running Meeting Prompter for better performance
2. **Use newer devices** for faster inference (iPhone 13+ recommended)
3. **First launch** will be slower as it indexes documents
4. **Reduce doc pack size** if experiencing slow search
5. **Monitor battery** - AI inference is computationally intensive

## Testing

### Manual Test Checklist

#### Initial Setup
- [ ] App launches successfully
- [ ] Models load without errors
- [ ] Document pack indexes successfully
- [ ] Status shows "Ready" after initialization

#### Push-to-Talk Recording
- [ ] Microphone button changes color when pressed
- [ ] Recording starts immediately on press
- [ ] Recording stops when released
- [ ] Audio permissions are requested properly

#### Live Transcription
- [ ] Transcript area shows "(live)" indicator while recording
- [ ] Partial transcript updates every ~1.5 seconds
- [ ] Transcript is cleared after stop (non-question)
- [ ] Transcript persists after stop (question)

#### Question Detection
- [ ] Questions with "what/when/where/who/why/how" trigger RAG
- [ ] Questions with question marks trigger RAG
- [ ] Statements without question words don't trigger RAG
- [ ] Non-question transcripts stop without showing answer

#### Document Retrieval
- [ ] Search returns relevant document chunks
- [ ] Sources display with titles and section paths
- [ ] Search is deterministic (same query = same results)

#### RAG Answers
- [ ] Answer appears after question recording
- [ ] Sources are listed below answer
- [ ] Answer references document content
- [ ] Status indicator shows "Answering…" during generation

#### Offline Operation
- [ ] App works in Airplane Mode
- [ ] No network errors appear
- [ ] All features function offline

### Unit Tests

Run the test suite:
```
⌘+U (Product → Test)
```

Test coverage:
- `QuestionDetectorTests`: Question keyword and punctuation detection
- `SentenceSelectorTests`: Evidence extraction and scoring
- `RetrievalTests`: Search index functionality and determinism

## Troubleshooting

### Models Not Found

**Error**: "ASR model .gguf file not found in app bundle" or "RAG model .gguf file not found in app bundle"

**Solution**:
1. Verify `.gguf` files are in your app target
2. Check filenames match exactly: `LFM2-Audio-1.5B.gguf`, `LFM2-1.2B-RAG.gguf`
3. Clean build folder (⌘+Shift+K) and rebuild

### Microphone Permission Denied

**Error**: App doesn't record audio

**Solution**:
1. Check `Info.plist` has `NSMicrophoneUsageDescription`
2. In Settings → Privacy → Microphone, enable Meeting Prompter
3. Delete and reinstall app if needed

### Slow Performance

**Symptoms**: Long transcription/answer times

**Solutions**:
1. Close other apps
2. Reduce document pack size
3. Test on newer device
4. Check available device storage

### Build Errors

**Error**: "No such module 'LeapSDK'"

**Solution**:
1. Verify Leap SDK package is added via SPM
2. Check "LeapSDK" is added to your app target
3. Clean build folder and rebuild

**Error**: "No such module 'GRDB'"

**Solution**:
1. Verify GRDB package is added via SPM
2. Check "GRDB" is added to your app target
3. Clean build folder and rebuild

### Runtime Crashes

**Symptoms**: App crashes during recording or processing

**Solutions**:
1. Check console logs in Xcode
2. Verify sufficient device memory
3. Test on physical device (not simulator)
4. Check model .gguf file integrity

## Architecture Overview

### Audio Pipeline
1. `AudioCaptureService` captures PCM audio at 16kHz
2. `VADGate` filters silence using RMS threshold
3. `PushToTalkController` manages recording state

### ASR Pipeline
1. Rolling buffer stores last 12 seconds of audio
2. Partial transcription runs every 1.5s (rate limited)
3. Final transcription runs on stop
4. Uses LFM2-Audio-1.5B model

### RAG Pipeline
1. **Question Detection**: Keywords + punctuation analysis
2. **Retrieval**: BM25 search over SQLite FTS5 (top 3 chunks)
3. **Grounding**: Sentence selector extracts best 8 sentences
4. **Generation**: LFM2-1.2B-RAG generates answer from evidence
5. **Sources**: Display chunk titles and section paths

### Data Flow
```
User Input (PTT) → Audio Capture → ASR → Transcript → Question Detection
                                                      ↓
                                              RAG Pipeline
                                                      ↓
                                          Answer + Sources
```

## License

This project is proprietary. All rights reserved.

## Support

For issues or questions:
1. Check this README's troubleshooting section
2. Review console logs in Xcode
3. Verify model bundles and doc pack are properly configured

## Acknowledgments

- LEAP Edge SDK by Liquid AI
- GRDB for SQLite integration
- NaturalLanguage framework for sentence tokenization