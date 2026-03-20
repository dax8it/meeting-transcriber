import Foundation
import LeapSDK

actor RAGService {
    static let shared = RAGService()
    
    private let leapManager = LeapModelManager.shared
    private let searchIndex = SearchIndex.shared
    private let sentenceSelector = SentenceSelector()
    
    private init() {}

    private func buildSourcesBlock(chunks: [DocumentChunk], maxSources: Int) -> (block: String, used: [DocumentChunk]) {
        guard !chunks.isEmpty else { return ("", []) }

        let usedChunks = Array(chunks.prefix(maxSources))
        let block = usedChunks.enumerated().map { idx, chunk in
            let sid = "S\(idx + 1)"
            let title = chunk.docTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let docType = chunk.docType.trimmingCharacters(in: .whitespacesAndNewlines)
            let meetingID = chunk.meetingID?.trimmingCharacters(in: .whitespacesAndNewlines)
            let meetingLabel = "meeting_\((meetingID?.isEmpty == false) ? (meetingID ?? "unknown") : "unknown")"

            let rawChunkIndex = chunk.chunkIndex ?? (idx + 1)
            let chunkIndexLabel = String(format: "%02d", rawChunkIndex)
            let section = chunk.sectionPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)

            let titleLabel = title.isEmpty ? "Untitled" : title
            let typeLabel = docType.isEmpty ? "unknown" : docType
            let metaLine: String = {
                if section.isEmpty {
                    return "Meta: doc_type=\(typeLabel)"
                }
                return "Meta: doc_type=\(typeLabel); path=\(section)"
            }()

            return """
            [\(sid) | \(titleLabel) | \(meetingLabel) | chunk \(chunkIndexLabel)]
            \(metaLine)
            \(text)
            """.trimmingCharacters(in: .whitespacesAndNewlines)
        }.joined(separator: "\n\n")

        return (block, usedChunks)
    }
    
    func generateAnswer(question: String) async throws -> RAGAnswer {
        Logger.log("[RAG] generateAnswer called; questionLen=\(question.count)", level: .debug, category: "rag")
        
        Logger.log("[RAG] Searching for chunks", level: .debug, category: "rag")
        let retrievedChunks: [DocumentChunk]
        do {
            retrievedChunks = try await searchIndex.search(query: question, topK: 8)
            Logger.log("[RAG] Found \(retrievedChunks.count) chunks", level: .debug, category: "rag")
        } catch {
            Logger.log("[RAG] Search failed: \(error.localizedDescription)", level: .error, category: "rag")
            throw error
        }
        
        guard !retrievedChunks.isEmpty else {
            Logger.log("[RAG] No chunks found; returning default answer", level: .debug, category: "rag")
            return RAGAnswer(
                question: question,
                answer: "Not enough evidence in sources.",
                sources: []
            )
        }

        let sources = buildSourcesBlock(chunks: retrievedChunks, maxSources: 12)
        Logger.log("[RAG] Evidence block created; loading model", level: .debug, category: "rag")
        // Keep memory footprint bounded during Q8 voice flows.
        await leapManager.unloadASR()
        await leapManager.unloadTTS()
        await leapManager.unloadTranscript()
        
        let model: any ModelRunner
        do {
            model = try await leapManager.getRAGModel()
            Logger.log("[RAG] Model loaded (runner=\(String(describing: type(of: model))))", level: .debug, category: "rag")
        } catch {
            Logger.log("[RAG] Model loading failed: \(error.localizedDescription)", level: .error, category: "rag")
            throw error
        }
        
        let systemPrompt = "Answer ONLY using SOURCES. Use a natural conversational tone (avoid numbered lists unless asked). Keep it concise (2-4 sentences). Add citations only where helpful, typically at sentence endings like [S1]. If not answerable, reply exactly: Not enough evidence in sources."
        
        let conversation = model.createConversation(systemPrompt: systemPrompt)
        
        let userPrompt = """
        SOURCES:
        \(sources.block)

        QUESTION:
        \(question)

        Instructions:
        - Answer ONLY using SOURCES.
        - Use conversational prose, not a rigid report format.
        - Keep it concise unless the user asks for detail.
        - Add citations only where needed.
        - If not answerable, say "Not enough evidence in sources." and nothing else.
        """
        
        Logger.log("[RAG] User prompt built; promptLen=\(userPrompt.count)", level: .debug, category: "rag")
        let userMessage = LeapSDK.ChatMessage(role: .user, content: [.text(userPrompt)])
        var response = ""

        Logger.log("[RAG] Starting generation with RAG model", level: .debug, category: "rag")
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

        response = response.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        return RAGAnswer(
            question: question,
            answer: response,
            sources: sources.used
        )
    }
    
    // MVP Option 1: Generate answer using provided chunks (current meeting transcript)
    func generateAnswer(question: String, chunks: [DocumentChunk]) async throws -> (answer: String, sources: [DocumentChunk]) {
        Logger.log("[RAG] generateAnswer(question:chunks:) questionLen=\(question.count), chunks=\(chunks.count)", level: .debug, category: "rag")
        
        guard !chunks.isEmpty else {
            Logger.log("[RAG] No current meeting chunks provided", level: .debug, category: "rag")
            return (answer: "I don't have current meeting transcript to answer from.", sources: [])
        }
        
        let sources = buildSourcesBlock(chunks: chunks, maxSources: 12)

        Logger.log("[RAG] Sources block created from meeting chunks; loading model", level: .debug, category: "rag")
        // Keep memory footprint bounded during Q8 voice flows.
        await leapManager.unloadASR()
        await leapManager.unloadTTS()
        await leapManager.unloadTranscript()
        
        let model: any ModelRunner
        do {
            model = try await leapManager.getRAGModel()
            Logger.log("[RAG] Model loaded (runner=\(String(describing: type(of: model))))", level: .debug, category: "rag")
        } catch {
            Logger.log("[RAG] Model loading failed: \(error.localizedDescription)", level: .error, category: "rag")
            throw error
        }
        
        let systemPrompt = "Answer ONLY using SOURCES. Use a natural conversational tone (avoid numbered lists unless asked). Keep it concise (2-4 sentences). Add citations only where helpful, typically at sentence endings like [S1]. If not answerable, reply exactly: Not enough evidence in sources."
        
        let conversation = model.createConversation(systemPrompt: systemPrompt)
        
        let userPrompt = """
        SOURCES:
        \(sources.block)

        Question:
        \(question)

        Instructions:
        - Answer ONLY using SOURCES.
        - Use conversational prose, not a rigid report format.
        - Keep it concise unless the user asks for detail.
        - Add citations only where needed.
        - If not answerable, say "Not enough evidence in sources." and nothing else.
        """
        
        let userMessage = LeapSDK.ChatMessage(role: .user, content: [.text(userPrompt)])
        var response = ""

        Logger.log("[RAG] Starting generation with current meeting evidence", level: .debug, category: "rag")
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

        response = response.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        return (answer: response, sources: sources.used)
    }
}
