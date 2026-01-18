# Meeting Prompter iOS - Setup Guide

This guide walks you through completing the Xcode project setup to get the Meeting Prompter iOS app building and running.

## Prerequisites

- Xcode 15.0 or newer
- iOS 15.0+ deployment target
- Physical iOS device (recommended) or iOS Simulator

## Step-by-Step Setup Instructions

### Step 1: Open the Project in Xcode

1. Navigate to your project directory
2. Open `MeetingPrompteriOS.xcodeproj`

### Step 2: Add Swift Package Dependencies

You need to add two Swift Package dependencies: **LeapSDK** and **GRDB**.

#### Add LEAP Edge SDK

1. In Xcode: **File → Add Package Dependencies...**
2. Enter this URL: `https://github.com/Liquid4All/leap-ios.git`
3. Click "Search" or press Enter
4. Select version `0.7.0` or newer
5. Click "Add Package"
6. In the "Add Package" dialog, select `LeapSDK` product
7. Ensure `MeetingPrompteriOS` target is checked
8. Click "Add Package"

#### Add GRDB (SQLite)

1. In Xcode: **File → Add Package Dependencies...**
2. Enter this URL: `https://github.com/groue/GRDB.swift.git`
3. Click "Search" or press Enter
4. Select version `7.0.0` or newer
5. Click "Add Package"
6. In the "Add Package" dialog, select `GRDB` product
7. Ensure `MeetingPrompteriOS` target is checked
8. Click "Add Package"

### Step 3: Add Microphone Permission to Info.plist

1. Select your project in the Project Navigator
2. Select the `MeetingPrompteriOS` target
3. Go to the **Info** tab
4. Add a new key:
   - Key: `NSMicrophoneUsageDescription`
   - Value: `Meeting Prompter needs microphone access to record your questions for transcription.`

Or, if you have the `Info.plist` file:
1. Right-click on `Info.plist` → Open As → Source Code
2. Add this inside the `<dict>` tag:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Meeting Prompter needs microphone access to record your questions for transcription.</string>
```

### Step 4: Add Model Files to Project

You need to add the Liquid AI model .gguf files to your project.

#### Model Files Required

1. Ensure you have these model files in `.gguf` format:
   - `LFM2-Audio-1.5B.gguf` (ASR model for speech recognition)
   - `LFM2-1.2B-RAG.gguf` (RAG generation model for answering)

   *Note: .gguf files are quantized model files that work with LEAP SDK.*

#### Add Model Files to Project

1. In Xcode, select your project in the Project Navigator
2. Create a folder: Right-click on `MeetingPrompteriOS` → New Group → Name it `Models`
3. Drag both `.gguf` files into the `Models` folder in Xcode
4. In the "Choose options for adding these files" dialog:
   - ✅ **Copy items if needed** (if files are outside project)
   - ✅ **Create groups**
   - ✅ **Add to targets**: [MeetingPrompteriOS]
5. Click "Finish"

6. Verify .gguf files appear in your project navigator under `Models/`

7. Ensure files are added to target:
   - Select `MeetingPrompteriOS` target
   - Go to **Build Phases** tab
   - Find **Copy Bundle Resources**
   - Verify `LFM2-Audio-1.5B.gguf` and `LFM2-1.2B-RAG.gguf` are listed

### Step 5: Verify Doc Pack is in Bundle

1. Ensure `docpack.json` is in your project (should be in `MeetingPrompteriOS/Resources/`)
2. Select `docpack.json` in Project Navigator
3. In the **File Inspector** (right panel), ensure:
   - Target Membership: `MeetingPrompteriOS` is checked

### Step 6: Verify Build Settings

1. Select your project → `MeetingPrompteriOS` target
2. Go to **Build Settings** tab
3. Verify these settings:
   - **iOS Deployment Target**: `iOS 15.0` or higher
   - **Swift Language Version**: `Swift 5.9` or higher

### Step 7: Build and Run

1. Select a physical iOS device from the scheme selector (recommended)
2. Click **Product → Run** (⌘+R)
3. The app should build and launch on your device
4. Grant microphone permission when prompted

### Step 8: First Launch

On first launch:
1. App will initialize and load models (may take 10-30 seconds)
2. Document pack will be indexed
3. Status should show "Ready"
4. Test push-to-talk by holding the microphone button

## Troubleshooting

### Build Errors

**Error: "No such module 'LeapSDK'"**
- Solution: Make sure Leap SDK package is added (Step 2.1)
- Clean build folder: **Product → Clean Build Folder** (⌘+Shift+K)
- Build again

**Error: "No such module 'GRDB'"**
- Solution: Make sure GRDB package is added (Step 2.2)
- Clean build folder and rebuild

**Error: "ASR model .gguf file not found in app bundle"**
- Solution: Verify model .gguf files are added to project target (Step 4)
- Check filenames match exactly: `LFM2-Audio-1.5B.gguf`, `LFM2-1.2B-RAG.gguf`
- Ensure they're in **Copy Bundle Resources** in Build Phases

**Error: "Microphone permission denied"**
- Solution: Check `NSMicrophoneUsageDescription` in Info.plist (Step 3)
- In device Settings: Privacy → Microphone → Enable Meeting Prompter

### Runtime Issues

**App crashes on launch**
- Check console logs in Xcode
- Verify model bundles are valid and complete
- Test on physical device (simulator may have issues)

**Slow performance**
- Close other apps
- Use newer device (iPhone 13+ recommended)
- Reduce document pack size if needed

**No transcription appears**
- Verify microphone permission
- Check device audio input
- Review console logs for errors

## Project Structure

```
MeetingPrompteriOS/
├── MeetingPrompteriOSApp.swift      # App entry point
├── ContentView.swift                 # Main UI
├── Info.plist                      # Permissions and config
├── Models/                        # Model .gguf files
│   ├── LFM2-Audio-1.5B.gguf
│   └── LFM2-1.2B-RAG.gguf
├── Resources/
│   └── docpack.json               # Sample documents
├── App/
│   └── ViewModels/
│       └── MainViewModel.swift     # State management
├── Core/
│   ├── Audio/
│   │   ├── AudioCaptureService.swift
│   │   ├── VADGate.swift
│   │   └── PushToTalkController.swift
│   ├── AI/
│   │   ├── LeapModelManager.swift
│   │   ├── ASRService.swift
│   │   ├── RAGService.swift
│   │   └── ModelIDs.swift
│   ├── Retrieval/
│   │   ├── DocumentChunk.swift
│   │   ├── DocPackLoader.swift
│   │   └── SearchIndex.swift
│   ├── RAG/
│   │   └── QuestionDetector.swift
│   ├── Grounding/
│   │   └── SentenceSelector.swift
│   └── Utils/
│       ├── TaskQueue.swift
│       └── Logger.swift
└── Views/
    ├── TranscriptView.swift
    ├── AnswerView.swift
    └── SourcesView.swift
```

## Next Steps

After setup is complete:

1. **Test the app**: Use push-to-talk to ask questions about the bundled documents
2. **Customize documents**: Replace `docpack.json` with your own documents
3. **Run unit tests**: Press ⌘+U to run the test suite
4. **Iterate**: Adjust parameters based on your use case

See **README.md** for:
- Feature descriptions
- Manual test checklist
- Performance tips
- Additional troubleshooting

## Support

For issues:
1. Check this setup guide's troubleshooting section
2. Review console logs in Xcode
3. Verify all steps above were completed correctly

Happy meeting prompting!