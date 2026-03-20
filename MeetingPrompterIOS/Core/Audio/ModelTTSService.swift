import AVFoundation
import Foundation
import LeapSDK

actor ModelTTSService {
    static let shared = ModelTTSService()

    enum PlaybackSource: Sendable {
        case skipped
        case modelAudio
        case appleFallback
        case modelFailed
    }

    struct SpeakResult: Sendable {
        let source: PlaybackSource
        let exportedWAVURL: URL?
        let errorDescription: String?

        static let skipped = SpeakResult(source: .skipped, exportedWAVURL: nil, errorDescription: nil)
    }

    private struct GeneratedAudioOutput {
        let sampleCount: Int
        let exportedWAVURL: URL?
    }

    private struct GeneratedAudioChunkOutput {
        let sampleCount: Int
        let sampleRate: Int
        let samples: [Float]
    }

    private let leapManager = LeapModelManager.shared

    private let maxTTSInputCharacters = 960
    private let chunkCharacterLimit = 90
    private let speakTimeoutNanoseconds: UInt64 = 120_000_000_000
    private let minPlaybackDrainTimeoutSeconds: TimeInterval = 20
    private let playbackDrainGraceSeconds: TimeInterval = 8

    private let ttsPipelineVersion = "leap-audio-pipeline-v1"
    private let ttsSystemPrompt = "Perform TTS. Use the US female voice."


    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?
    private var currentSampleRate: Double?

    private var pendingBuffers: Int = 0
    private var audioSessionSnapshot: (category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions)?

    private var completionContinuation: CheckedContinuation<Void, Never>?
    private var generationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var fallbackInProgress = false
    private var pendingSpeakResult: SpeakResult = .skipped

    private final class CallbackAudioChunkStore: @unchecked Sendable {
        private let lock = NSLock()
        private var chunks: [([Float], Int)] = []

        func append(samples: [Float], sampleRate: Int) {
            guard !samples.isEmpty else { return }
            lock.lock()
            chunks.append((samples, sampleRate))
            lock.unlock()
        }

        func snapshot() -> [([Float], Int)] {
            lock.lock()
            let result = chunks
            lock.unlock()
            return result
        }
    }

    private init() {}

    func speak(
        _ text: String,
        preferModel: Bool = true,
        exportWAVTo exportURL: URL? = nil,
        allowAppleFallback: Bool = true
    ) async -> SpeakResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .skipped }

        stop()
        fallbackInProgress = false
        pendingSpeakResult = .skipped
        print("[ModelTTS] Pipeline version: \(ttsPipelineVersion)")

        guard preferModel else {
            await TTSService.shared.speak(trimmed)
            return SpeakResult(source: .appleFallback, exportedWAVURL: nil, errorDescription: nil)
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            completionContinuation = cont

            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: self.speakTimeoutNanoseconds)
                await self.handleSpeakTimeout(originalText: trimmed, allowAppleFallback: allowAppleFallback)
            }

            generationTask = Task {
                do {
                    let output = try await speakWithLeap(trimmed, exportWAVTo: exportURL)
                    pendingSpeakResult = SpeakResult(source: .modelAudio, exportedWAVURL: output.exportedWAVURL, errorDescription: nil)
                    finishSpeaking()
                } catch {
                    timeoutTask?.cancel()
                    timeoutTask = nil
                    guard completionContinuation != nil else { return }
                    guard !fallbackInProgress else { return }
                    let errorMessage = error.localizedDescription
                    print("[ModelTTS] Model audio failed: \(errorMessage)")
                    stopEngine()

                    if allowAppleFallback {
                        fallbackInProgress = true
                        print("[ModelTTS] Falling back to AVSpeechSynthesizer for this response")
                        await TTSService.shared.speak(trimmed)
                        pendingSpeakResult = SpeakResult(source: .appleFallback, exportedWAVURL: nil, errorDescription: errorMessage)
                    } else {
                        pendingSpeakResult = SpeakResult(source: .modelFailed, exportedWAVURL: nil, errorDescription: errorMessage)
                    }
                    finishSpeaking()
                }
            }
        }

        return pendingSpeakResult
    }

    func stop() {
        generationTask?.cancel()
        generationTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        fallbackInProgress = false
        pendingBuffers = 0
        pendingSpeakResult = .skipped
        stopEngine()
        finishSpeaking()
    }

    private func speakWithLeap(_ text: String, exportWAVTo exportURL: URL?) async throws -> GeneratedAudioOutput {
        // Keep resident memory stable by unloading non-TTS models before model audio generation.
        await leapManager.unloadASR()
        await leapManager.unloadRAG()
        await leapManager.unloadTranscript()

        let utterance = sanitizeForSpeech(text)
        guard !utterance.isEmpty else {
            throw ModelTTSError.noAudioSamples
        }

        let speechChunks = splitIntoSpeechChunks(utterance, maxCharacters: chunkCharacterLimit)
        guard !speechChunks.isEmpty else {
            throw ModelTTSError.noAudioSamples
        }
        print("[ModelTTS] Speaking \(utterance.count) chars across \(speechChunks.count) chunk(s)")

        let model = try await leapManager.getTTSModel()

        var totalSamples = 0
        var combinedSamples: [Float] = []
        var outputSampleRate = 0

        for (chunkIndex, speechChunk) in speechChunks.enumerated() {
            let chunkOutput = try await generateLeapAudio(
                model: model,
                utterance: speechChunk,
                systemPrompt: ttsSystemPrompt
            )

            guard !chunkOutput.samples.isEmpty else {
                print("[ModelTTS] Chunk \(chunkIndex + 1)/\(speechChunks.count) produced empty sample payload")
                continue
            }

            if outputSampleRate == 0 {
                outputSampleRate = chunkOutput.sampleRate
            }
            guard chunkOutput.sampleRate == outputSampleRate else {
                print("[ModelTTS] Skipping chunk \(chunkIndex + 1) due to sample-rate mismatch chunk=\(chunkOutput.sampleRate) expected=\(outputSampleRate)")
                continue
            }

            mergeChunkSamples(chunkOutput.samples, into: &combinedSamples, sampleRate: outputSampleRate)
            totalSamples += chunkOutput.sampleCount
            print("[ModelTTS] Chunk \(chunkIndex + 1)/\(speechChunks.count) generated, samples=\(chunkOutput.sampleCount)")
        }

        totalSamples = combinedSamples.count

        guard totalSamples > 0, outputSampleRate > 0, !combinedSamples.isEmpty else {
            throw ModelTTSError.noAudioSamples
        }

        try await playBufferedAudio(samples: combinedSamples, sampleRate: Double(outputSampleRate))

        var exportedWAVURL: URL?
        if let exportURL,
           !combinedSamples.isEmpty {
            do {
                exportedWAVURL = try writeWAV(samples: combinedSamples, sampleRate: outputSampleRate, to: exportURL)
                print("[ModelTTS] Exported response audio WAV: \(exportURL.lastPathComponent)")
            } catch {
                print("[ModelTTS] Failed to export WAV: \(error)")
            }
        }

        return GeneratedAudioOutput(sampleCount: totalSamples, exportedWAVURL: exportedWAVURL)
    }

    private func generateLeapAudio(
        model: any ModelRunner,
        utterance: String,
        systemPrompt: String
    ) async throws -> GeneratedAudioChunkOutput {
        let conversation = model.createConversation(systemPrompt: systemPrompt)
        let userMessage = LeapSDK.ChatMessage(role: .user, content: [.text(utterance)])

        let callbackStore = CallbackAudioChunkStore()
        var generationOptions = GenerationOptions(functionCallParser: nil, resetHistory: true, enableThinking: false)
        generationOptions.onAudioSamples = { samples, sampleRate in
            callbackStore.append(samples: samples, sampleRate: sampleRate)
        }

        var totalSamples = 0
        var outputSampleRate = 0
        var textResponse = ""
        var generatedSamples: [Float] = []

        for try await messageResponse in conversation.generateResponse(message: userMessage, generationOptions: generationOptions) {
            switch messageResponse {
            case .audioSample(samples: let samples, sampleRate: let sampleRate):
                let cleaned = sanitizeGeneratedAudio(samples)
                guard !cleaned.isEmpty else { continue }

                if outputSampleRate == 0 {
                    outputSampleRate = sampleRate
                }
                guard sampleRate == outputSampleRate else {
                    print("[ModelTTS] Skipping audio callback with mismatched sample rate=\(sampleRate), expected=\(outputSampleRate)")
                    continue
                }

                generatedSamples.append(contentsOf: cleaned)
                totalSamples += cleaned.count
            case .chunk(let delta):
                textResponse += delta
            case .complete(let completion):
                let completedText = completion.message.content.compactMap { item in
                    if case .text(let value) = item { return value }
                    return nil
                }.joined()
                if !completedText.isEmpty {
                    textResponse = completedText
                }
            case .reasoningChunk, .functionCall:
                break
            }
        }

        if totalSamples == 0 {
            let callbackChunks = callbackStore.snapshot()
            if !callbackChunks.isEmpty {
                print("[ModelTTS] Replaying \(callbackChunks.count) audio callback chunk(s)")
                for (samples, sampleRate) in callbackChunks {
                    let cleaned = sanitizeGeneratedAudio(samples)
                    guard !cleaned.isEmpty else { continue }

                    if outputSampleRate == 0 {
                        outputSampleRate = sampleRate
                    }
                    guard sampleRate == outputSampleRate else {
                        print("[ModelTTS] Skipping replay callback with mismatched sample rate=\(sampleRate), expected=\(outputSampleRate)")
                        continue
                    }

                    generatedSamples.append(contentsOf: cleaned)
                    totalSamples += cleaned.count
                }
            }
        }

        guard totalSamples > 0 else {
            let cleanedText = textResponse.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanedText.isEmpty {
                let preview = String(cleanedText.prefix(80))
                print("[ModelTTS] Model returned text but no audio (preview='\(preview)')")
            }
            throw ModelTTSError.noAudioSamples
        }

        guard outputSampleRate > 0 else {
            throw ModelTTSError.noAudioSamples
        }

        let seconds = Double(totalSamples) / Double(outputSampleRate)
        print("[ModelTTS] Audio chunk generated: \(totalSamples) samples @ \(outputSampleRate)Hz (~\(String(format: "%.2f", seconds))s)")
        return GeneratedAudioChunkOutput(
            sampleCount: totalSamples,
            sampleRate: outputSampleRate,
            samples: generatedSamples
        )
    }

    private func playBufferedAudio(samples: [Float], sampleRate: Double) async throws {
        guard !samples.isEmpty else {
            throw ModelTTSError.noAudioSamples
        }
        try setupEngineIfNeeded(sampleRate: sampleRate)
        try enqueue(samples: samples)
        try await waitForPlaybackDrain(expectedSamples: samples.count, sampleRate: sampleRate)
    }

    private func mergeChunkSamples(_ chunk: [Float], into combined: inout [Float], sampleRate: Int) {
        guard !chunk.isEmpty else { return }
        guard !combined.isEmpty else {
            combined = chunk
            return
        }

        let targetCrossfade = max(24, Int(Double(sampleRate) * 0.012))
        let crossfadeSamples = min(min(combined.count, chunk.count), targetCrossfade)
        guard crossfadeSamples > 0 else {
            combined.append(contentsOf: chunk)
            return
        }

        let start = combined.count - crossfadeSamples
        for i in 0..<crossfadeSamples {
            let t = Float(i + 1) / Float(crossfadeSamples + 1)
            combined[start + i] = (combined[start + i] * (1 - t)) + (chunk[i] * t)
        }
        combined.append(contentsOf: chunk.dropFirst(crossfadeSamples))
    }

    private func enqueueAndWait(samples: [Float], sampleRate: Double) async throws {
        try enqueue(samples: samples)
        try await waitForPlaybackDrain(expectedSamples: samples.count, sampleRate: sampleRate)
    }

    private func enqueue(samples: [Float]) throws {
        guard let format = audioFormat,
              let playerNode else {
            throw ModelTTSError.audioEngineNotReady
        }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw ModelTTSError.audioEngineNotReady
        }

        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData else {
            throw ModelTTSError.audioEngineNotReady
        }

        let channel = channelData[0]
        for i in 0..<samples.count {
            channel[i] = samples[i]
        }

        pendingBuffers += 1
        playerNode.scheduleBuffer(buffer) { [weak self] in
            Task { await self?.bufferDidFinish() }
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    private func waitForPlaybackDrain(expectedSamples: Int, sampleRate: Double) async throws {
        guard pendingBuffers > 0 else { return }

        let expectedPlaybackSeconds = sampleRate > 0 ? Double(expectedSamples) / sampleRate : 0
        let timeout = max(minPlaybackDrainTimeoutSeconds, expectedPlaybackSeconds + playbackDrainGraceSeconds)
        let deadline = Date().addingTimeInterval(timeout)
        while pendingBuffers > 0 {
            if Task.isCancelled {
                throw CancellationError()
            }
            if Date() >= deadline {
                throw ModelTTSError.playbackDrainTimeout
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func bufferDidFinish() {
        if pendingBuffers > 0 {
            pendingBuffers -= 1
        }
    }

    private func setupEngineIfNeeded(sampleRate: Double) throws {
        if let currentSampleRate,
           currentSampleRate == sampleRate,
           audioEngine != nil,
           playerNode != nil {
            return
        }

        try configureAudioSessionForPlaybackIfNeeded()
        print("[ModelTTS] Configured playback audio session")
        stopEngine()

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        player.volume = 0.9
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw ModelTTSError.audioEngineNotReady
        }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        print("[ModelTTS] Audio engine started @ \(Int(sampleRate))Hz")

        audioEngine = engine
        playerNode = player
        audioFormat = format
        currentSampleRate = sampleRate
    }

    private func stopEngine() {
        playerNode?.stop()
        audioEngine?.stop()
        playerNode = nil
        audioEngine = nil
        audioFormat = nil
        currentSampleRate = nil
    }

    private func finishSpeaking() {
        timeoutTask?.cancel()
        timeoutTask = nil
        fallbackInProgress = false
        restoreAudioSessionIfNeeded()
        completionContinuation?.resume()
        completionContinuation = nil
    }

    // iPhone reliability: isolate TTS playback session from recording/transcription session state.
    private func configureAudioSessionForPlaybackIfNeeded() throws {
        let session = AVAudioSession.sharedInstance()

        if audioSessionSnapshot == nil {
            audioSessionSnapshot = (session.category, session.mode, session.categoryOptions)
        }

        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .allowBluetoothA2DP, .allowAirPlay])
            try session.setActive(true)
            print("[ModelTTS] Audio session active category=\(session.category.rawValue) mode=\(session.mode.rawValue)")
        } catch {
            print("[ModelTTS] Primary playback session setup failed: \(error). Retrying with conservative audio session settings.")
            do {
                try session.setCategory(.playback, mode: .default, options: [])
                try session.setActive(true)
                print("[ModelTTS] Playback audio session recovered with conservative settings")
            } catch {
                throw ModelTTSError.audioSessionConfigurationFailed(error.localizedDescription)
            }
        }
    }

    private func restoreAudioSessionIfNeeded() {
        guard let snapshot = audioSessionSnapshot else { return }
        audioSessionSnapshot = nil

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
            try session.setCategory(snapshot.category, mode: snapshot.mode, options: snapshot.options)
        } catch {
            print("[ModelTTS] Failed to restore audio session: \(error)")
        }
    }

    private func handleSpeakTimeout(originalText: String, allowAppleFallback: Bool) async {
        guard completionContinuation != nil else { return }
        guard !fallbackInProgress else { return }
        fallbackInProgress = true
        print("[ModelTTS] Speak timeout hit; cancelling model generation")
        generationTask?.cancel()
        generationTask = nil
        stopEngine()

        if allowAppleFallback {
            print("[ModelTTS] Timeout fallback to AVSpeechSynthesizer")
            await TTSService.shared.speak(originalText)
            pendingSpeakResult = SpeakResult(source: .appleFallback, exportedWAVURL: nil, errorDescription: ModelTTSError.playbackDrainTimeout.localizedDescription)
        } else {
            pendingSpeakResult = SpeakResult(source: .modelFailed, exportedWAVURL: nil, errorDescription: ModelTTSError.playbackDrainTimeout.localizedDescription)
        }

        finishSpeaking()
    }

    private func writeWAV(samples: [Float], sampleRate: Int, to outputURL: URL) throws -> URL {
        guard sampleRate > 0, !samples.isEmpty else {
            throw ModelTTSError.noAudioSamples
        }

        let fm = FileManager.default
        let parent = outputURL.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)

        var pcmData = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let scaled = Int16((clamped * Float(Int16.max)).rounded()).littleEndian
            withUnsafeBytes(of: scaled) { bytes in
                pcmData.append(contentsOf: bytes)
            }
        }

        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let blockAlign: UInt16 = channels * (bitsPerSample / 8)
        let byteRate: UInt32 = UInt32(sampleRate) * UInt32(blockAlign)
        let dataSize = UInt32(pcmData.count)
        let riffSize: UInt32 = 36 + dataSize

        var wavData = Data(capacity: 44 + pcmData.count)
        wavData.append("RIFF".data(using: .ascii)!)
        appendLittleEndian(riffSize, to: &wavData)
        wavData.append("WAVE".data(using: .ascii)!)
        wavData.append("fmt ".data(using: .ascii)!)
        appendLittleEndian(UInt32(16), to: &wavData) // PCM chunk size
        appendLittleEndian(UInt16(1), to: &wavData) // PCM format
        appendLittleEndian(channels, to: &wavData)
        appendLittleEndian(UInt32(sampleRate), to: &wavData)
        appendLittleEndian(byteRate, to: &wavData)
        appendLittleEndian(blockAlign, to: &wavData)
        appendLittleEndian(bitsPerSample, to: &wavData)
        wavData.append("data".data(using: .ascii)!)
        appendLittleEndian(dataSize, to: &wavData)
        wavData.append(pcmData)

        try wavData.write(to: outputURL, options: [.atomic])
        return outputURL
    }

    private func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    private func sanitizeForSpeech(_ rawText: String) -> String {
        let noGroupedCitations = rawText.replacingOccurrences(
            of: #"\[(?:\s*S\d+\s*,?)+\s*\]"#,
            with: "",
            options: .regularExpression
        )
        let noCitations = noGroupedCitations.replacingOccurrences(
            of: #"\s*\[S\d+\]"#,
            with: "",
            options: .regularExpression
        )
        let noListPrefixes = noCitations.replacingOccurrences(
            of: #"(?m)^\s*\d+\.\s+"#,
            with: "",
            options: .regularExpression
        )
        let noBulletPrefixes = noListPrefixes.replacingOccurrences(
            of: #"(?m)^\s*[-*•]\s+"#,
            with: "",
            options: .regularExpression
        )
        let noMarkdownHeadings = noBulletPrefixes.replacingOccurrences(
            of: #"(?m)^\s*#{1,6}\s+"#,
            with: "",
            options: .regularExpression
        )
        let flattened = noMarkdownHeadings
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !flattened.isEmpty else { return "" }

        if flattened.count <= maxTTSInputCharacters {
            return flattened
        }

        let hardClipped = String(flattened.prefix(maxTTSInputCharacters))
        let clipped: String
        if let lastSpace = hardClipped.lastIndex(of: " "), lastSpace > hardClipped.startIndex {
            clipped = String(hardClipped[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            clipped = hardClipped
        }
        print("[ModelTTS] Trimming TTS input from \(flattened.count) to \(clipped.count) chars")
        return clipped
    }

    private func splitIntoSpeechChunks(_ text: String, maxCharacters: Int) -> [String] {
        guard text.count > maxCharacters else { return [text] }

        var sentences: [String] = []
        var currentSentence = ""

        for character in text {
            currentSentence.append(character)
            if character == "." || character == "!" || character == "?" {
                let trimmed = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sentences.append(trimmed)
                }
                currentSentence = ""
            }
        }

        let trailing = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trailing.isEmpty {
            sentences.append(trailing)
        }

        if sentences.isEmpty {
            return splitLongSegmentByWords(text, maxCharacters: maxCharacters)
        }

        var chunks: [String] = []
        var currentChunk = ""

        func flushCurrentChunk() {
            let trimmed = currentChunk.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                chunks.append(trimmed)
            }
            currentChunk = ""
        }

        for sentence in sentences {
            if sentence.count > maxCharacters {
                flushCurrentChunk()
                chunks.append(contentsOf: splitLongSegmentByWords(sentence, maxCharacters: maxCharacters))
                continue
            }

            if currentChunk.isEmpty {
                currentChunk = sentence
            } else if currentChunk.count + 1 + sentence.count <= maxCharacters {
                currentChunk += " " + sentence
            } else {
                flushCurrentChunk()
                currentChunk = sentence
            }
        }

        flushCurrentChunk()
        return chunks
    }

    private func splitLongSegmentByWords(_ text: String, maxCharacters: Int) -> [String] {
        guard text.count > maxCharacters else {
            return [text.trimmingCharacters(in: .whitespacesAndNewlines)]
        }

        var chunks: [String] = []
        var current = ""

        func flushCurrent() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                chunks.append(trimmed)
            }
            current = ""
        }

        let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
        for word in parts {
            if current.isEmpty {
                current = word
            } else if current.count + 1 + word.count <= maxCharacters {
                current += " " + word
            } else {
                flushCurrent()
                current = word
            }
        }
        flushCurrent()
        return chunks
    }

    private func sanitizeGeneratedAudio(_ audio: [Float]) -> [Float] {
        guard !audio.isEmpty else { return [] }

        var cleaned: [Float] = audio.map { sample in
            if sample.isFinite {
                return sample
            }
            return 0
        }

        // Keep headroom to reduce audible crunch/saturation on some iPhone playback routes.
        let gain: Float = 0.88
        for i in cleaned.indices {
            let adjusted = cleaned[i] * gain
            cleaned[i] = min(0.92, max(-0.92, adjusted))
        }

        return cleaned
    }
}

enum ModelTTSError: LocalizedError {
    case noAudioSamples
    case playbackDrainTimeout
    case modelNotLoaded
    case audioEngineNotReady
    case audioSessionConfigurationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioSamples:
            return "Model did not return audio samples"
        case .playbackDrainTimeout:
            return "Timed out while waiting for audio playback to drain"
        case .modelNotLoaded:
            return "Model TTS was not loaded"
        case .audioEngineNotReady:
            return "Audio engine is not ready"
        case .audioSessionConfigurationFailed(let message):
            return "Audio session configuration failed: \(message)"
        }
    }
}
