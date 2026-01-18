import Foundation
import LeapSDK

actor RAGService {
    static let shared = RAGService()
    
    private let leapManager = LeapModelManager.shared
    private let searchIndex = SearchIndex.shared
    private let sentenceSelector = SentenceSelector()
    
    private init() {}
    
    func generateAnswer(question: String) async throws -> RAGAnswer {
        print("[RAG] generateAnswer called with question: \(question)")
        
        print("[RAG] Searching for chunks...")
        let retrievedChunks: [DocumentChunk]
        do {
            retrievedChunks = try await searchIndex.search(query: question, topK: 3)
            print("[RAG] Found \(retrievedChunks.count) chunks")
        } catch {
            print("[RAG] Search failed: \(error)")
            throw error
        }
        
        guard !retrievedChunks.isEmpty else {
            print("[RAG] No chunks found, returning default answer")
            return RAGAnswer(
                question: question,
                answer: "I don't have information to answer that question based on the available documents.",
                sources: []
            )
        }
        
        print("[RAG] Selecting best sentences...")
        let evidenceBlock = sentenceSelector.selectBestSentences(
            question: question,
            chunks: retrievedChunks,
            maxSentences: 8
        )
        print("[RAG] Evidence block created, loading model...")
        
        let model: any ModelRunner
        do {
            model = try await leapManager.getRAGModel()
            print("[RAG] Creating conversation. Runner type: \(String(describing: type(of: model)))")
            print("[RAG] RAG model type: \(type(of: model))")
        } catch {
            print("[RAG] Model loading failed: \(error)")
            throw error
        }
        
        let systemPrompt = "You are a helpful assistant. Answer questions using only the provided evidence."
        
        // Debug logging
        let trimmedPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[RAG] System prompt - Length: \(trimmedPrompt.count), Preview: \"\(String(trimmedPrompt.prefix(120)))\"")
        print("[RAG] Creating conversation. Runner type: \(String(describing: type(of: model)))")
        print("[RAG] RAG conversation system prompt: \"\(systemPrompt)\"")

        let conversation = model.createConversation(systemPrompt: systemPrompt)
        
        // CRITICAL: Verify we're not accidentally using audio engine
        print("[RAG] CONVERSATION CREATED - about to start generation")
        print("[RAG] System prompt accepted without 'Perform ASR' error - indicates text engine")
        print("[RAG] If audio engine was loaded, we would see 'Invalid system prompt' by now")
        
        let userPrompt = """
        Question: \(question)
        
        Evidence:
        \(evidenceBlock)
        
        Provide a short, helpful answer. Then list 2-3 sources with their titles and section paths.
        """
        
        print("[RAG] User prompt length: \(userPrompt.count)")
        let userMessage = ChatMessage(role: .user, content: [.text(userPrompt)])
        var response = ""

        print("[RAG] Starting generation with RAG model...")
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
            sources: retrievedChunks
        )
    }
    
    // MVP Option 1: Generate answer using provided chunks (current meeting transcript)
    func generateAnswer(question: String, chunks: [DocumentChunk]) async throws -> (answer: String, sources: [DocumentChunk]) {
        print("[RAG] generateAnswer(question:chunks:) questionLen=\(question.count), chunks=\(chunks.count)")
        
        guard !chunks.isEmpty else {
            print("[RAG] No current meeting chunks provided")
            return (answer: "I don't have current meeting transcript to answer from.", sources: [])
        }
        
        let evidenceBlock = sentenceSelector.selectBestSentences(
            question: question,
            chunks: chunks,
            maxSentences: 8
        )
        print("[RAG] Evidence block created from current meeting, loading model...")
        
        let model: any ModelRunner
        do {
            model = try await leapManager.getRAGModel()
            print("[RAG] Model loaded. Runner type: \(String(describing: type(of: model)))")
        } catch {
            print("[RAG] Model loading failed: \(error)")
            throw error
        }
        
        let systemPrompt = "You are a helpful assistant. Answer questions using only provided evidence."
        
        print("[RAG] Creating conversation. Runner type: \(String(describing: type(of: model)))")
        let conversation = model.createConversation(systemPrompt: systemPrompt)
        
        let userPrompt = """
        Question: \(question)
        
        Evidence:
        \(evidenceBlock)
        
        Provide a short, helpful answer. Then list 2-3 sources with their titles and section paths.
        """
        
        let userMessage = ChatMessage(role: .user, content: [.text(userPrompt)])
        var response = ""

        print("[RAG] Starting generation with current meeting evidence...")
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
        
        return (answer: response, sources: chunks)
    }
}
