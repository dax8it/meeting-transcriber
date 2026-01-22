import Foundation
import LeapSDK

actor SummarizationService {
    static let shared = SummarizationService()

    private let leapManager = LeapModelManager.shared

    private init() {}

    func summarize(transcript: String) async -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        do {
            // Keep memory sane: only one text runner at a time.
            await leapManager.unloadRAG()

            let model = try await leapManager.getTranscriptModel()
            let systemPrompt = "You are a meeting summarizer. Output concise Markdown."

            let userPrompt = """
            Summarize the meeting transcript in Markdown with:
            - Title
            - Key points (bullets)
            - Decisions
            - Action items (owner, due date if present)
            - Open questions

            Transcript:
            \(trimmed)
            """

            let conversation = model.createConversation(systemPrompt: systemPrompt)
            let userMessage = ChatMessage(role: .user, content: [.text(userPrompt)])

            var response = ""
            for try await chunk in conversation.generateResponse(message: userMessage) {
                switch chunk {
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

            await leapManager.unloadTranscript()
            return response
        } catch {
            print("[Summary] error: \(error)")
            await leapManager.unloadTranscript()
            return ""
        }
    }
}
