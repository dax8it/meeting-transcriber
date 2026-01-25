import Foundation
import LeapSDK

actor ASRService {
    static let shared = ASRService()
    
    private let leapManager = LeapModelManager.shared
    private var lastTranscriptionTime: Date?
    private let minTranscriptionInterval: TimeInterval = 1.0
    
    private init() {}
    
    func transcribe(samples: [Float]) async -> String {
        guard !samples.isEmpty else {
            print("[ASR] Empty samples, returning empty string")
            return ""
        }

        print("[ASR] Transcribing \(samples.count) samples...")
        do {
            print("[ASR] Loading ASR model...")
            let model = try await leapManager.getASRModel()
            print("[ASR] Model loaded. runnerType=\(String(describing: type(of: model)))")
            
            let result = try await performASRTranscription(
                model: model,
                audio: samples
            )
            
            return result.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        } catch {
            print("ASR error: \(error)")
            return ""
        }
    }

    // MVP: used by LiveTranscriptionService for chunked transcription.
    func transcribeChunk(samples: [Float]) async -> String {
        print("[DEBUG ASRService] transcribeChunk: \(samples.count) samples")
        let result = await transcribe(samples: samples)
        print("[DEBUG ASRService] transcribeChunk result: '\(String(result.prefix(100)))'")
        return result
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
        print("[ASR] Creating conversation. Runner type: \(String(describing: type(of: model)))")
        print("[ASR] ASR model type: \(type(of: model))")
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

        response = response.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[ASR] transcription finished, len=\(response.count), preview='\(String(response.prefix(80)))'")
        return response
    }
}
