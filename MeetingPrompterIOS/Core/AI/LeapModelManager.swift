import Foundation
import LeapSDK

actor LeapModelManager {
    static let shared = LeapModelManager()
    
    private var asrModel: (any ModelRunner)?
    private var ttsModel: (any ModelRunner)?
    private var ragModel: (any ModelRunner)?
    private var transcriptModel: (any ModelRunner)?
    
    // Track model kind to prevent accidental reuse
    private enum ModelKind {
        case asrAudio
        case ttsAudio
        case ragText
        case transcriptText
    }
    private var asrModelKind: ModelKind = .asrAudio
    private var ttsModelKind: ModelKind = .ttsAudio
    private var ragModelKind: ModelKind = .ragText
    private var transcriptModelKind: ModelKind = .transcriptText

    private struct AudioCompanions {
        let mmProjPath: String?
        let tokenizerPath: String?
        let decoderCandidates: [String]

        var preferredDecoderPath: String? {
            decoderCandidates.first
        }
    }
    
    private init() {}
    
    private func modelURL(modelName: String, modelExtension: String, subdirectory: String?, notFoundMessage: String) async throws -> URL {
        try await MainActor.run {
            if let subdirectory,
               let url = Bundle.main.url(forResource: modelName, withExtension: modelExtension, subdirectory: subdirectory) {
                print("[LeapManager] Resolved \(modelName).\(modelExtension) at: \(url.path)")
                return url
            }

            if let url = Bundle.main.url(forResource: modelName, withExtension: modelExtension) {
                // Safety fallback: keep bundle-root resolution in case build settings flatten resources.
                print("[LeapManager] Resolved \(modelName).\(modelExtension) at: \(url.path) (bundle root fallback)")
                return url
            }

            throw ModelLoadError.modelNotFound(notFoundMessage)
        }
    }

    private func stagingDirectory(for kind: ModelKind) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let kindFolder: String
        switch kind {
        case .asrAudio:
            kindFolder = "asr"
        case .ttsAudio:
            kindFolder = "tts"
        case .ragText:
            kindFolder = "rag"
        case .transcriptText:
            kindFolder = "transcript"
        }

        let dir = base
            .appendingPathComponent("MeetingPrompterModels", isDirectory: true)
            .appendingPathComponent(kindFolder, isDirectory: true)

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func stageFileIfNeeded(from sourceURL: URL, to directoryURL: URL) throws -> URL {
        let destURL = directoryURL.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: false)
        if FileManager.default.fileExists(atPath: destURL.path) {
            return destURL
        }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)
        return destURL
    }

    private func isDecoderArtifactURL(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()
        guard ext == "gguf" || ext == "bin" else { return false }
        return name.contains("decoder") || name.contains("vocoder")
    }

    private func removeStagedDecoderArtifacts(in directoryURL: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            print("[TTS] Could not inspect staging directory for stale decoder artifacts: \(directoryURL.path)")
            return
        }

        let decoderArtifacts = contents.filter(isDecoderArtifactURL)
        guard !decoderArtifacts.isEmpty else {
            print("[TTS] No stale staged decoder artifacts found in: \(directoryURL.path)")
            return
        }

        var removedNames: [String] = []
        for artifact in decoderArtifacts {
            do {
                try FileManager.default.removeItem(at: artifact)
                removedNames.append(artifact.lastPathComponent)
            } catch {
                print("[TTS] Failed to remove staged decoder artifact \(artifact.lastPathComponent): \(error)")
            }
        }

        if removedNames.isEmpty {
            print("[TTS] Found staged decoder artifacts but none were removed")
        } else {
            print("[TTS] Removed stale staged decoder artifacts: \(removedNames.joined(separator: ", "))")
        }
    }

    private func removeLegacyAudioStagingIfNeeded() {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return }

        let legacyDir = base
            .appendingPathComponent("MeetingPrompterModels", isDirectory: true)
            .appendingPathComponent("audio", isDirectory: true)

        if FileManager.default.fileExists(atPath: legacyDir.path) {
            try? FileManager.default.removeItem(at: legacyDir)
            print("[LeapManager] Removed legacy audio staging directory: \(legacyDir.path)")
        }
    }

    private func findAudioCompanions(nextTo modelURL: URL) -> AudioCompanions {
        let directoryURL = modelURL.deletingLastPathComponent()
        let modelStem = modelURL.deletingPathExtension().lastPathComponent.lowercased()
        print("[LeapManager] Scanning companions next to: \(directoryURL.path)")

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            print("[LeapManager] Failed to list directory: \(directoryURL.path)")
            return AudioCompanions(mmProjPath: nil, tokenizerPath: nil, decoderCandidates: [])
        }

        let sortedContents = contents.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }

        func isDecoder(_ url: URL) -> Bool {
            let name = url.lastPathComponent.lowercased()
            let ext = url.pathExtension.lowercased()
            let isDecoderLike = name.contains("decoder") || name.contains("vocoder")
            return isDecoderLike && (ext == "gguf" || ext == "bin")
        }

        func isTokenizer(_ url: URL) -> Bool {
            let name = url.lastPathComponent.lowercased()
            let ext = url.pathExtension.lowercased()
            let isTokenizerLike = name.contains("tokenizer") || (name.contains("audio") && name.contains("token"))
            return isTokenizerLike && (ext == "gguf" || ext == "bin")
        }

        func isMMProj(_ url: URL) -> Bool {
            let name = url.lastPathComponent.lowercased()
            let ext = url.pathExtension.lowercased()
            return name.contains("mmproj") && (ext == "gguf" || ext == "bin")
        }

        func decoderPriority(_ url: URL) -> Int {
            let name = url.lastPathComponent.lowercased()
            if name.contains("decoder") && !name.contains("vocoder") { return 0 }
            if name.contains("audio") && name.contains("decoder") { return 1 }
            if name.contains("vocoder") && !name.contains("decoder") { return 2 }
            return 3
        }

        func matchesModel(_ url: URL) -> Bool {
            url.lastPathComponent.lowercased().contains(modelStem)
        }

        let mmprojCandidates = sortedContents.filter(isMMProj)
        let tokenizerCandidates = sortedContents.filter(isTokenizer)
        let decoderCandidates = sortedContents
            .filter(isDecoder)
            .sorted { lhs, rhs in
                let lhsPriority = decoderPriority(lhs)
                let rhsPriority = decoderPriority(rhs)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                let lhsMatches = matchesModel(lhs)
                let rhsMatches = matchesModel(rhs)
                if lhsMatches != rhsMatches {
                    return lhsMatches && !rhsMatches
                }
                return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
            }

        let mmproj = mmprojCandidates.first(where: matchesModel) ?? mmprojCandidates.first
        let tokenizer = tokenizerCandidates.first(where: matchesModel) ?? tokenizerCandidates.first

        let decoderNames = decoderCandidates.map(\.lastPathComponent)
        print("[LeapManager] Found tokenizer: \(tokenizer?.lastPathComponent ?? "<none>")")
        print("[LeapManager] Found mmproj: \(mmproj?.lastPathComponent ?? "<none>")")
        print("[LeapManager] Decoder candidates: \(decoderNames.isEmpty ? "<none>" : decoderNames.joined(separator: ", "))")
        print("[LeapManager] Preferred decoder: \(decoderCandidates.first?.lastPathComponent ?? "<none>")")

        return AudioCompanions(
            mmProjPath: mmproj?.path,
            tokenizerPath: tokenizer?.path,
            decoderCandidates: decoderCandidates.map(\.path)
        )
    }

    func loadASRModel() async throws {
        guard asrModel == nil else { return }
        removeLegacyAudioStagingIfNeeded()
        let asrURL: URL
        do {
            asrURL = try await modelURL(
                modelName: ModelIDs.asrModelName,
                modelExtension: ModelIDs.asrModelExtension,
                subdirectory: "models/audio",
                notFoundMessage: "ASR model .gguf file not found in models/audio subdirectory"
            )
        } catch {
            // This is diagnostic only: some Xcode resource builds flatten subdirectories.
            // If this happens, we still allow ASR to load from bundle root.
            print("[ASR] Model not found in models/audio; falling back to bundle root")
            guard let fallbackURL = Bundle.main.url(forResource: ModelIDs.asrModelName, withExtension: ModelIDs.asrModelExtension) else {
                throw error
            }
            asrURL = fallbackURL
        }
        print("[ASR] ASR model file: \(asrURL.lastPathComponent)")
        print("[ASR] ASR model resolved URL: \(asrURL.path)")

        let companions = findAudioCompanions(nextTo: asrURL)

        guard let audioTokenizerPath = companions.tokenizerPath else {
            throw ModelLoadError.modelNotFound(
                "ASR model is present but audio support is not enabled. Add the required companion files next to \(asrURL.lastPathComponent) in the app bundle (Copy Bundle Resources): an audio tokenizer (often named with 'audio'+'token' or 'tokenizer'), with extension .gguf or .bin. Some LFM2.5 Audio checkpoints also require an mmproj-*.gguf file (e.g. mmproj-\(ModelIDs.asrModelName).gguf)."
            )
        }

#if DEBUG
        let tokenizerExists = FileManager.default.fileExists(atPath: audioTokenizerPath)
        let mmprojExists = companions.mmProjPath.map { FileManager.default.fileExists(atPath: $0) } ?? false
        print("ASR model: \(asrURL.lastPathComponent)")
        print("ASR audioTokenizerPath: \(audioTokenizerPath) exists=\(tokenizerExists)")
        if let mmproj = companions.mmProjPath {
            print("ASR mmProjPath: \(mmproj) exists=\(mmprojExists)")
        } else {
            print("ASR mmProjPath: <none>")
        }

        if let decoderPath = companions.preferredDecoderPath {
            let decoderExists = FileManager.default.fileExists(atPath: decoderPath)
            print("ASR audioDecoderPath: \(decoderPath) exists=\(decoderExists)")
        } else {
            print("ASR audioDecoderPath: <none>")
        }
#endif

        // Stage ASR artifacts into a dedicated folder so LeapSDK can't cross-detect text/mmproj from other locations.
        let asrStageBaseDir = try stagingDirectory(for: .asrAudio)
        let asrStageDir = asrStageBaseDir.appendingPathComponent(ModelIDs.asrModelName, isDirectory: true)
        try FileManager.default.createDirectory(at: asrStageDir, withIntermediateDirectories: true)
        removeStagedDecoderArtifacts(in: asrStageDir)
        let stagedASRURL = try stageFileIfNeeded(from: asrURL, to: asrStageDir)

        let tokenizerURL = URL(fileURLWithPath: audioTokenizerPath)
        let stagedTokenizerURL = try stageFileIfNeeded(from: tokenizerURL, to: asrStageDir)

        let stagedMMProjPath = try companions.mmProjPath.map { try stageFileIfNeeded(from: URL(fileURLWithPath: $0), to: asrStageDir).path }

        print("[ASR] Loading staged ASR model from: \(stagedASRURL.path)")

        // NOTE: ASR should not use a chat template; allow LeapSDK defaults.
        let options = LiquidInferenceEngineOptions(
            bundlePath: stagedASRURL.path,
            cacheOptions: nil,
            cpuThreads: 2,
            contextSize: 1024,
            nGpuLayers: 0,
            mmProjPath: stagedMMProjPath,
            audioDecoderPath: nil,
            chatTemplate: nil,
            audioTokenizerPath: stagedTokenizerURL.path,
            extras: nil
        )

        asrModel = try Leap.load(options: options)
        print("[ASR] ASR runner loaded")
    }

    func loadTTSModel() async throws {
        guard ttsModel == nil else { return }
        let ttsURL: URL
        do {
            ttsURL = try await modelURL(
                modelName: ModelIDs.ttsModelName,
                modelExtension: ModelIDs.ttsModelExtension,
                subdirectory: "models/audio",
                notFoundMessage: "TTS model \(ModelIDs.ttsModelName).\(ModelIDs.ttsModelExtension) not found in models/audio. LeapAudioDemo uses Q8_0 for audio output."
            )
        } catch {
            print("[TTS] Model not found in models/audio; falling back to bundle root")
            guard let fallbackURL = Bundle.main.url(forResource: ModelIDs.ttsModelName, withExtension: ModelIDs.ttsModelExtension) else {
                throw error
            }
            ttsURL = fallbackURL
        }

        if ttsModelKind != .ttsAudio {
            throw ModelLoadError.modelNotLoaded("TTS model kind mismatch")
        }

        print("[TTS] TTS model file: \(ttsURL.lastPathComponent)")
        print("[TTS] TTS model resolved URL: \(ttsURL.path)")

        let companions = findAudioCompanions(nextTo: ttsURL)

        guard !companions.decoderCandidates.isEmpty else {
            throw ModelLoadError.modelNotFound(
                "TTS requires a matching vocoder/decoder artifact for \(ModelIDs.ttsModelName). Add vocoder-\(ModelIDs.ttsModelName).gguf to models/audio."
            )
        }
        guard let tokenizerPath = companions.tokenizerPath else {
            throw ModelLoadError.modelNotFound(
                "TTS requires a matching audio tokenizer for \(ModelIDs.ttsModelName). Add tokenizer-\(ModelIDs.ttsModelName).gguf to models/audio."
            )
        }
        guard let mmprojPath = companions.mmProjPath else {
            throw ModelLoadError.modelNotFound(
                "TTS requires a matching mmproj for \(ModelIDs.ttsModelName). Add mmproj-\(ModelIDs.ttsModelName).gguf to models/audio."
            )
        }

        let ttsStageBaseDir = try stagingDirectory(for: .ttsAudio)
        let ttsStageDir = ttsStageBaseDir.appendingPathComponent(ModelIDs.ttsModelName, isDirectory: true)
        try FileManager.default.createDirectory(at: ttsStageDir, withIntermediateDirectories: true)
        removeStagedDecoderArtifacts(in: ttsStageDir)
        let stagedTTSURL = try stageFileIfNeeded(from: ttsURL, to: ttsStageDir)
        let stagedTokenizerPath = try stageFileIfNeeded(from: URL(fileURLWithPath: tokenizerPath), to: ttsStageDir).path
        let stagedMMProjPath = try stageFileIfNeeded(from: URL(fileURLWithPath: mmprojPath), to: ttsStageDir).path
        let modelStem = ModelIDs.ttsModelName.lowercased()
        let matchingDecoders = companions.decoderCandidates.filter {
            URL(fileURLWithPath: $0).lastPathComponent.lowercased().contains(modelStem)
        }
        let orderedDecoderCandidates = matchingDecoders + companions.decoderCandidates.filter { candidate in
            !matchingDecoders.contains(candidate)
        }
        let stagedDecoderCandidates = try orderedDecoderCandidates.map {
            try stageFileIfNeeded(from: URL(fileURLWithPath: $0), to: ttsStageDir).path
        }
        let decoderDiagnostics = orderedDecoderCandidates.map { candidate -> String in
            let name = URL(fileURLWithPath: candidate).lastPathComponent
            let size = (try? FileManager.default.attributesOfItem(atPath: candidate)[.size] as? NSNumber)?.intValue
            return size.map { "\(name) (\($0) bytes)" } ?? name
        }

        print("[TTS] Decoder candidates (ordered): \(decoderDiagnostics.joined(separator: ", "))")
        print("[TTS] Using tokenizer: \(URL(fileURLWithPath: stagedTokenizerPath).lastPathComponent)")
        print("[TTS] Using mmproj: \(URL(fileURLWithPath: stagedMMProjPath).lastPathComponent)")

        if let stagedFiles = try? FileManager.default.contentsOfDirectory(
            atPath: ttsStageDir.path
        ).sorted() {
            print("[TTS] Staging directory contents (\(ttsStageDir.path)): \(stagedFiles.joined(separator: ", "))")
        }

        var lastError: Error?
        for decoderPath in stagedDecoderCandidates {
            print("[TTS] Attempting decoder: \(URL(fileURLWithPath: decoderPath).lastPathComponent)")
            let baseOptions = LiquidInferenceEngineOptions(
                bundlePath: stagedTTSURL.path,
                cacheOptions: nil,
                cpuThreads: 2,
                contextSize: 1024,
                nGpuLayers: 0,
                mmProjPath: stagedMMProjPath,
                audioDecoderPath: decoderPath,
                audioDecoderUseGpu: false,
                chatTemplate: nil,
                audioTokenizerPath: stagedTokenizerPath,
                extras: nil
            )

            do {
                ttsModel = try Leap.load(options: baseOptions)
                print("[TTS] TTS runner loaded with decoder: \(URL(fileURLWithPath: decoderPath).lastPathComponent)")
                return
            } catch {
                lastError = error
                print("[TTS] Decoder load failed (\(URL(fileURLWithPath: decoderPath).lastPathComponent)): \(error)")
            }
        }

        if let lastError {
            throw ModelLoadError.modelNotLoaded(
                "TTS model failed to load with all decoder candidates. Error: \(lastError.localizedDescription)"
            )
        }
    }

    func loadRAGModel() async throws {
        guard ragModel == nil else { return }
        print("[RAG] Loading RAG model...")

        let ragURL: URL
        do {
            ragURL = try await modelURL(
                modelName: ModelIDs.ragModelName,
                modelExtension: ModelIDs.ragModelExtension,
                subdirectory: "models/text",
                notFoundMessage: "RAG model .gguf file not found in models/text subdirectory"
            )
        } catch {
            print("[RAG] Primary RAG model not found (\(ModelIDs.ragModelName)); trying fallback \(ModelIDs.ragFallbackModelName)")
            ragURL = try await modelURL(
                modelName: ModelIDs.ragFallbackModelName,
                modelExtension: ModelIDs.ragModelExtension,
                subdirectory: "models/text",
                notFoundMessage: "Neither primary RAG model \(ModelIDs.ragModelName) nor fallback \(ModelIDs.ragFallbackModelName) was found in models/text"
            )
        }

        // Fail-fast: RAG must not be configured with any audio companions.
        // If you see mmproj/tokenizer getting attached, it's coming from LeapSDK internals and we should stop here.
        if ragModelKind != .ragText {
            throw ModelLoadError.modelNotLoaded("RAG model kind mismatch")
        }
        print("[RAG] RAG model file: \(ragURL.lastPathComponent)")
        print("[RAG] RAG model resolved URL: \(ragURL.path)")
        print("[RAG] RAG model exists: \(FileManager.default.fileExists(atPath: ragURL.path))")
        
        // Use clean options without invalid extras JSON
        // Stage RAG model into a dedicated folder so LeapSDK can't auto-detect mmproj/tokenizer from ASR.
        let ragStageDir = try stagingDirectory(for: .ragText)
        let stagedRAGURL = try stageFileIfNeeded(from: ragURL, to: ragStageDir)
        print("[RAG] RAG staged URL: \(stagedRAGURL.path)")

        let ragOptions = LiquidInferenceEngineOptions(
            bundlePath: stagedRAGURL.path,
            cacheOptions: nil,
            cpuThreads: nil,
            contextSize: nil,
            nGpuLayers: nil,
            mmProjPath: nil,
            audioDecoderPath: nil,
            chatTemplate: nil,
            audioTokenizerPath: nil,
            extras: nil
        )
        
        print("[RAG] Loading RAG model from models/text subdirectory...")
        print("[RAG] RAG model file: \(ragURL.lastPathComponent)")
        print("[RAG] RAG model path: \(ragURL.path)")
        print("[RAG] RAG options - bundlePath: \(ragOptions.bundlePath)")
        print("[RAG] RAG options - mmProjPath: nil")
        print("[RAG] RAG options - audioTokenizerPath: nil")
        print("[RAG] RAG options - audioDecoderPath: nil")
        print("[RAG] RAG options - extras: nil")
        
        ragModel = try Leap.load(options: ragOptions)
        print("[RAG] RAG model loaded successfully - engine=text mmproj=nil tokenizer=nil")
    }

    func loadTranscriptModel() async throws {
        guard transcriptModel == nil else { return }
        print("[Summary] Loading Transcript model...")

        let transcriptURL: URL
        do {
            transcriptURL = try await modelURL(
                modelName: ModelIDs.transcriptModelName,
                modelExtension: ModelIDs.transcriptModelExtension,
                subdirectory: "models/text",
                notFoundMessage: "Transcript model .gguf file not found in models/text subdirectory"
            )
        } catch {
            print("[Summary] Primary transcript model not found (\(ModelIDs.transcriptModelName)); trying fallback \(ModelIDs.transcriptFallbackModelName)")
            transcriptURL = try await modelURL(
                modelName: ModelIDs.transcriptFallbackModelName,
                modelExtension: ModelIDs.transcriptModelExtension,
                subdirectory: "models/text",
                notFoundMessage: "Neither primary transcript model \(ModelIDs.transcriptModelName) nor fallback \(ModelIDs.transcriptFallbackModelName) was found in models/text"
            )
        }

        if transcriptModelKind != .transcriptText {
            throw ModelLoadError.modelNotLoaded("Transcript model kind mismatch")
        }

        let stageDir = try stagingDirectory(for: .transcriptText)
        let stagedURL = try stageFileIfNeeded(from: transcriptURL, to: stageDir)
        print("[Summary] Transcript staged URL: \(stagedURL.path)")

        // Avoid defaulting to full model context (128k), which can exhaust memory on-device.
        let contextSizeCandidates: [UInt32] = [16_384, 8_192, 4_096]
        var lastError: Error?

        for contextSize in contextSizeCandidates {
            let options = LiquidInferenceEngineOptions(
                bundlePath: stagedURL.path,
                cacheOptions: nil,
                cpuThreads: nil,
                contextSize: contextSize,
                nGpuLayers: nil,
                mmProjPath: nil,
                audioDecoderPath: nil,
                chatTemplate: nil,
                audioTokenizerPath: nil,
                extras: nil
            )

            do {
                transcriptModel = try Leap.load(options: options)
                print("[Summary] Transcript runner loaded (contextSize=\(contextSize))")
                return
            } catch {
                lastError = error
                print("[Summary] Transcript load failed (contextSize=\(contextSize)): \(error)")
            }
        }

        if let lastError {
            throw lastError
        }

        throw ModelLoadError.modelNotLoaded("Transcript model failed to load")
    }

    func getASRModel() async throws -> (any ModelRunner) {
        if let model = asrModel { 
            print("[LeapManager] getASRModel - returning cached ASR model, modelKind: asr")
            return model 
        }
        try await loadASRModel()
        guard let model = asrModel else {
            throw ModelLoadError.modelNotLoaded("ASR model not loaded")
        }
        print("[LeapManager] getASRModel - returning newly loaded ASR model, modelKind: asr")
        return model
    }

    func getTTSModel() async throws -> (any ModelRunner) {
        if let model = ttsModel {
            print("[LeapManager] getTTSModel - returning cached TTS model, modelKind: tts")
            return model
        }
        try await loadTTSModel()
        guard let model = ttsModel else {
            throw ModelLoadError.modelNotLoaded("TTS model not loaded")
        }
        print("[LeapManager] getTTSModel - returning newly loaded TTS model, modelKind: tts")
        return model
    }

    func getRAGModel() async throws -> (any ModelRunner) {
        if let model = ragModel { 
            print("[LeapManager] getRAGModel - returning cached RAG model, modelKind: rag")
            return model 
        }
        try await loadRAGModel()
        guard let model = ragModel else {
            throw ModelLoadError.modelNotLoaded("RAG model not loaded")
        }
        print("[LeapManager] getRAGModel - returning newly loaded RAG model, modelKind: rag")
        return model
    }

    func getTranscriptModel() async throws -> (any ModelRunner) {
        if let model = transcriptModel {
            return model
        }
        try await loadTranscriptModel()
        guard let model = transcriptModel else {
            throw ModelLoadError.modelNotLoaded("Transcript model not loaded")
        }
        return model
    }

    func unloadASR() async {
        print("[LeapManager] Unloading ASR model...")
        if let model = asrModel {
            await model.unload()
        }
        asrModel = nil
        print("[LeapManager] ASR model unloaded")
    }

    func unloadTTS() async {
        print("[LeapManager] Unloading TTS model...")
        if let model = ttsModel {
            await model.unload()
        }
        ttsModel = nil
        print("[LeapManager] TTS model unloaded")
    }

    func unloadRAG() async {
        print("[LeapManager] Unloading RAG model...")
        if let model = ragModel {
            await model.unload()
        }
        ragModel = nil
        print("[LeapManager] RAG model unloaded")
    }

    func unloadTranscript() async {
        print("[LeapManager] Unloading Transcript model...")
        if let model = transcriptModel {
            await model.unload()
        }
        transcriptModel = nil
        print("[LeapManager] Transcript model unloaded")
    }
    
    func unload() async {
        print("[LeapManager] Unloading all models...")
        if let model = asrModel {
            await model.unload()
        }
        if let model = ttsModel {
            await model.unload()
        }
        if let model = ragModel {
            await model.unload()
        }
        if let model = transcriptModel {
            await model.unload()
        }
        asrModel = nil
        ttsModel = nil
        ragModel = nil
        transcriptModel = nil
        print("[LeapManager] All models unloaded")
    }
}

enum ModelLoadError: LocalizedError {
    case modelNotFound(String)
    case modelNotLoaded(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotFound(let message):
            return message
        case .modelNotLoaded(let message):
            return message
        }
    }
}
