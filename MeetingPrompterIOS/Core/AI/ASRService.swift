import Foundation
import LeapSDK

actor ASRService {
    static let shared = ASRService()

    private let leapManager = LeapModelManager.shared
    private var lastTranscriptionTime: Date?
    private let minTranscriptionInterval: TimeInterval = 1.0

    private init() {}

    // MARK: - Public API

    func transcribe(samples: [Float]) async -> String {
        guard !samples.isEmpty else {
            print("[ASR] Empty samples, returning empty string")
            return ""
        }

        print("[ASR] Transcribing \(samples.count) samples...")

        do {
            let engine = try await leapManager.getASREngine()
            let text = try await performASRTranscription(
                engine: engine,
                audio: samples
            )
            return text.trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines
            )
        } catch {
            print("[ASR] Error: \(error)")
            return ""
        }
    }

    func transcribeChunk(samples: [Float]) async -> String {
        let result = await transcribe(samples: samples)
        print("[ASR] Chunk result: '\(result.prefix(80))'")
        return result
    }

    func transcribePartial(samples: [Float]) async -> String {
        guard !samples.isEmpty else { return "" }

        if let last = lastTranscriptionTime,
           Date().timeIntervalSince(last) < minTranscriptionInterval {
            return ""
        }

        lastTranscriptionTime = Date()
        return await transcribe(samples: samples)
    }

    // MARK: - Internal ASR implementation (LeapSDK v0.6.x)

    /// Converts Float audio samples to WAV format Data
    private func convertToWAV(samples: [Float], sampleRate: Int = 16000) -> Data {
        let bytesPerSample = 2  // 16-bit PCM
        let dataSize = samples.count * bytesPerSample
        let headerSize = 44
        let totalSize = headerSize + dataSize

        var wavData = Data(capacity: totalSize)

        // RIFF chunk descriptor
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(UInt32(totalSize - 8).littleEndianBytes)
        wavData.append("WAVE".data(using: .ascii)!)

        // fmt sub-chunk
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(UInt32(16).littleEndianBytes)  // Subchunk1Size (16 for PCM)
        wavData.append(UInt16(1).littleEndianBytes)   // AudioFormat (1 for PCM)
        wavData.append(UInt16(1).littleEndianBytes)   // NumChannels (1 for mono)
        wavData.append(UInt32(sampleRate).littleEndianBytes)  // SampleRate
        wavData.append(UInt32(sampleRate * bytesPerSample).littleEndianBytes)  // ByteRate
        wavData.append(UInt16(bytesPerSample).littleEndianBytes)  // BlockAlign
        wavData.append(UInt16(16).littleEndianBytes)  // BitsPerSample

        // data sub-chunk
        wavData.append("data".data(using: .ascii)!)
        wavData.append(UInt32(dataSize).littleEndianBytes)

        // Convert Float (-1.0 to 1.0) to Int16 PCM
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let intSample = Int16(clamped * 32767.0)
            wavData.append(intSample.littleEndianBytes)
        }

        return wavData
    }

    private func performASRTranscription(
        engine: LiquidInferenceEngine,
        audio: [Float]
    ) async throws -> String {

        print("[ASR] Running direct ASR transcription via LiquidInferenceEngine")

        // Convert Float samples to WAV Data
        let wavData = convertToWAV(samples: audio, sampleRate: 16000)
        print("[ASR] Converted \(audio.count) samples to WAV (\(wavData.count) bytes)")

        // Create message with WAV audio content
        let messageContent = LiquidMessageContent(wav: wavData)
        let message = LiquidMessage(role: "user", content: [messageContent])

        // Use generate with messages for direct ASR (no chat template)
        let generateOptions = LiquidGenerateOptions(
            resetHistory: true,
            sequenceLength: 256,
            samplerParams: LiquidSamplerParams(temperature: 1.0)
        )

        var transcription = ""
        var generationError: Error?

        print("[ASR] Starting generation...")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            engine.generate(
                messages: [message],
                options: generateOptions,
                onToken: { token in
                    transcription += token
                },
                onComplete: { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        generationError = error
                        continuation.resume(throwing: error)
                    }
                }
            )
        }

        if let error = generationError {
            throw error
        }

        let trimmed = transcription.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines
        )

        print("[ASR] Finished transcription, len=\(trimmed.count)")
        return trimmed
    }
}

// MARK: - Helper extensions for byte conversion

private extension UInt32 {
    var littleEndianBytes: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}

private extension UInt16 {
    var littleEndianBytes: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt16>.size)
    }
}

private extension Int16 {
    var littleEndianBytes: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<Int16>.size)
    }
}
