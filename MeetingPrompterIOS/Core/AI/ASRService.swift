import Foundation
import LeapSDK

actor ASRService {
    static let shared = ASRService()

    private let leapManager = LeapModelManager.shared

    private var lastTranscriptionTime: Date?
    private let minTranscriptionInterval: TimeInterval = 1.0

    private init() {}

    func prepareForTranscription() async -> Bool {
        do {
            _ = try await leapManager.getASRModel()
            return true
        } catch {
            Logger.log("[ASR] prepare failed: \(error.localizedDescription)", level: .error, category: "asr")
            return false
        }
    }

    func transcribe(samples: [Float]) async -> String {
        guard !samples.isEmpty else { return "" }

        Logger.log("[ASR] Transcribing \(samples.count) samples", level: .debug, category: "asr")
        do {
            let model = try await leapManager.getASRModel()
            let result = try await performASRTranscription(model: model, audio: samples)
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            Logger.log("[ASR] Transcription failed: \(error.localizedDescription)", level: .error, category: "asr")
            return ""
        }
    }

    // MVP: used by LiveTranscriptionService for chunked transcription.
    func transcribeChunk(samples: [Float]) async -> String {
        await transcribe(samples: samples)
    }
    
    func transcribePartial(samples: [Float]) async -> String {
        guard !samples.isEmpty else { return "" }

        if let lastTime = lastTranscriptionTime,
           Date().timeIntervalSince(lastTime) < minTranscriptionInterval {
            return ""
        }

        lastTranscriptionTime = Date()
        return await transcribe(samples: samples)
    }

    private func performASRTranscription(model: any ModelRunner, audio: [Float]) async throws -> String {
        let conversation = model.createConversation(systemPrompt: "Perform ASR.")
        let userMessage = LeapSDK.ChatMessage(
            role: .user,
            content: [
                ChatMessageContent.fromFloatSamples(audio, sampleRate: 16_000),
            ]
        )

        var response = ""
        for try await messageResponse in conversation.generateResponse(message: userMessage) {
            switch messageResponse {
            case .chunk(let delta):
                response += delta
            case .complete(let completion):
                let completedText = completion.message.content.compactMap { item in
                    if case .text(let value) = item { return value }
                    return nil
                }.joined()

                if !completedText.isEmpty {
                    response = completedText
                }
            default:
                break
            }
        }

        let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        Logger.log("[ASR] transcription finished, len=\(cleaned.count)", level: .debug, category: "asr")
        return cleaned
    }
}

enum ASRError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "ASR model is not loaded"
        }
    }
}
