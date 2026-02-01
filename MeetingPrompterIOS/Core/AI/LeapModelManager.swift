import Foundation
import LeapSDK

actor LeapModelManager {
    static let shared = LeapModelManager()
    
    private var asrEngine: LiquidInferenceEngine?
    private var ragModel: (any ModelRunner)?
    private var transcriptModel: (any ModelRunner)?
    
    // Track model kind to prevent accidental reuse
    private enum ModelKind {
        case asrAudio
        case ragText
        case transcriptText
    }
    private var asrModelKind: ModelKind = .asrAudio
    private var ragModelKind: ModelKind = .ragText
    private var transcriptModelKind: ModelKind = .transcriptText
    
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
            kindFolder = "audio"
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

    private func findAudioCompanions(nextTo modelURL: URL) -> (mmProjPath: String?, decoderPath: String?, tokenizerPath: String?) {
        let directoryURL = modelURL.deletingLastPathComponent()
        print("[ASR] Scanning companions next to: \(directoryURL.path)")

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            print("[ASR] Failed to list directory: \(directoryURL.path)")
            return (nil, nil, nil)
        }

        func isDecoder(_ url: URL) -> Bool {
            let name = url.lastPathComponent.lowercased()
            let ext = url.pathExtension.lowercased()
            return name.contains("audio") && name.contains("decoder") && (ext == "gguf" || ext == "bin")
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

        let mmproj = contents.first(where: isMMProj)
        let decoder = contents.first(where: isDecoder)
        let tokenizer = contents.first(where: isTokenizer)

        print("[ASR] Found tokenizer: \(tokenizer?.lastPathComponent ?? "<none>")")
        print("[ASR] Found mmproj: \(mmproj?.lastPathComponent ?? "<none>")")

        return (mmproj?.path, decoder?.path, tokenizer?.path)
    }

    func loadASRModel() async throws {
        guard asrModel == nil else { return }
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
                "ASR model is present but audio support is not enabled. Add the required companion files next to \(asrURL.lastPathComponent) in the app bundle (Copy Bundle Resources): an audio tokenizer (often named with 'audio'+'token' or 'tokenizer'), with extension .gguf or .bin. Some LFM2.5 Audio checkpoints also require an mmproj-*.gguf file (e.g. mmproj-LFM2.5-Audio-1.5B-Q4_0.gguf). If you also want audio output, include a true audio decoder artifact whose filename contains 'audio' and 'decoder'."
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

        if let decoderPath = companions.decoderPath {
            let decoderExists = FileManager.default.fileExists(atPath: decoderPath)
            print("ASR audioDecoderPath: \(decoderPath) exists=\(decoderExists)")
        } else {
            print("ASR audioDecoderPath: <none>")
        }
#endif

        // Stage ASR artifacts into a dedicated folder so LeapSDK can't cross-detect text/mmproj from other locations.
        let asrStageDir = try stagingDirectory(for: .asrAudio)
        let stagedASRURL = try stageFileIfNeeded(from: asrURL, to: asrStageDir)

        let tokenizerURL = URL(fileURLWithPath: audioTokenizerPath)
        let stagedTokenizerURL = try stageFileIfNeeded(from: tokenizerURL, to: asrStageDir)

        let stagedMMProjPath = try companions.mmProjPath.map { try stageFileIfNeeded(from: URL(fileURLWithPath: $0), to: asrStageDir).path }
        let stagedDecoderPath = try companions.decoderPath.map { try stageFileIfNeeded(from: URL(fileURLWithPath: $0), to: asrStageDir).path }

        print("[ASR] Loading staged ASR model from: \(stagedASRURL.path)")

        // LeapSDK v0.6.x: LiquidInferenceEngineOptions only has bundlePath, cacheOptions, cpuThreads, contextSize, nGpuLayers, mmProjPath
        let options = LiquidInferenceEngineOptions(
            bundlePath: stagedASRURL.path,
            cacheOptions: nil,
            cpuThreads: nil,
            contextSize: nil,
            nGpuLayers: nil,
            mmProjPath: stagedMMProjPath
        )

        asrEngine = try LiquidInferenceEngine(options: options)
        print("[ASR] ASR runner loaded")
    }

    func loadRAGModel() async throws {
        guard ragModel == nil else { return }
        print("[RAG] Loading RAG model...")
        
        let ragURL = try await modelURL(
            modelName: ModelIDs.ragModelName,
            modelExtension: ModelIDs.ragModelExtension,
            subdirectory: "models/text",
            notFoundMessage: "RAG model .gguf file not found in models/text subdirectory"
        )

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
            mmProjPath: nil
        )
        
        print("[RAG] Loading RAG model from models/text subdirectory...")
        print("[RAG] RAG model file: \(ragURL.lastPathComponent)")
        print("[RAG] RAG model path: \(ragURL.path)")
        print("[RAG] RAG options - bundlePath: \(ragOptions.bundlePath)")
        print("[RAG] RAG options - mmProjPath: nil")
        
        ragModel = try Leap.load(options: ragOptions)
        print("[RAG] RAG model loaded successfully - engine=text mmproj=nil tokenizer=nil")
    }

    func loadTranscriptModel() async throws {
        guard transcriptModel == nil else { return }
        print("[Summary] Loading Transcript model...")

        let modelURL = try await modelURL(
            modelName: ModelIDs.transcriptModelName,
            modelExtension: ModelIDs.transcriptModelExtension,
            subdirectory: "models/text",
            notFoundMessage: "Transcript model .gguf file not found in models/text subdirectory"
        )

        if transcriptModelKind != .transcriptText {
            throw ModelLoadError.modelNotLoaded("Transcript model kind mismatch")
        }

        let stageDir = try stagingDirectory(for: .transcriptText)
        let stagedURL = try stageFileIfNeeded(from: modelURL, to: stageDir)
        print("[Summary] Transcript staged URL: \(stagedURL.path)")

        let options = LiquidInferenceEngineOptions(
            bundlePath: stagedURL.path,
            cacheOptions: nil,
            cpuThreads: nil,
            contextSize: nil,
            nGpuLayers: nil,
            mmProjPath: nil
        )

        transcriptModel = try Leap.load(options: options)
        print("[Summary] Transcript runner loaded")
    }

    func getASREngine() async throws -> LiquidInferenceEngine {
        if let engine = asrEngine {
            print("[LeapManager] getASREngine - returning cached ASR engine")
            return engine
        }
        try await loadASRModel()
        guard let engine = asrEngine else {
            throw ModelLoadError.modelNotLoaded("ASR engine not loaded")
        }
        print("[LeapManager] getASREngine - returning newly loaded ASR engine")
        return engine
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

    func unloadASR() {
        print("[LeapManager] Unloading ASR engine...")
        asrEngine = nil
        print("[LeapManager] ASR engine unloaded")
    }

    func unloadRAG() {
        print("[LeapManager] Unloading RAG model...")
        ragModel = nil
        print("[LeapManager] RAG model unloaded")
    }

    func unloadTranscript() {
        print("[LeapManager] Unloading Transcript model...")
        transcriptModel = nil
        print("[LeapManager] Transcript model unloaded")
    }
    
    func unload() {
        print("[LeapManager] Unloading all models...")
        asrEngine = nil
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
