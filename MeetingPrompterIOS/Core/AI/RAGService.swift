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
        print("[RAG] generateAnswer called with question: \(question)")
        
        print("[RAG] Searching for chunks...")
        let retrievedChunks: [DocumentChunk]
        do {
            retrievedChunks = try await searchIndex.search(query: question, topK: 8)
            print("[RAG] Found \(retrievedChunks.count) chunks")
        } catch {
            print("[RAG] Search failed: \(error)")
            throw error
        }
        
        guard !retrievedChunks.isEmpty else {
            print("[RAG] No chunks found, returning default answer")
            return RAGAnswer(
                question: question,
                answer: "Not enough evidence in sources.",
                sources: []
            )
        }

        let sources = buildSourcesBlock(chunks: retrievedChunks, maxSources: 12)
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
        
        let systemPrompt = "Answer ONLY using SOURCES. Cite every sentence like [S1], [S2]. If not answerable, reply exactly: Not enough evidence in sources."
        
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
        SOURCES:
        \(sources.block)

        QUESTION:
        \(question)

        Instructions:
        - Answer ONLY using SOURCES.
        - Cite every sentence like [S1], [S2].
        - If not answerable, say "Not enough evidence in sources." and nothing else.
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
            sources: sources.used
        )
    }
    
    // MVP Option 1: Generate answer using provided chunks (current meeting transcript)
    func generateAnswer(question: String, chunks: [DocumentChunk]) async throws -> (answer: String, sources: [DocumentChunk]) {
        print("[RAG] generateAnswer(question:chunks:) questionLen=\(question.count), chunks=\(chunks.count)")
        
        guard !chunks.isEmpty else {
            print("[RAG] No current meeting chunks provided")
            return (answer: "I don't have current meeting transcript to answer from.", sources: [])
        }
        
        let sources = buildSourcesBlock(chunks: chunks, maxSources: 12)

        print("[RAG] Sources block created from meeting chunks, loading model...")
        
        let model: any ModelRunner
        do {
            model = try await leapManager.getRAGModel()
            print("[RAG] Model loaded. Runner type: \(String(describing: type(of: model)))")
        } catch {
            print("[RAG] Model loading failed: \(error)")
            throw error
        }
        
        let systemPrompt = "Answer ONLY using SOURCES. Cite every sentence like [S1], [S2]. If not answerable, reply exactly: Not enough evidence in sources."
        
        print("[RAG] Creating conversation. Runner type: \(String(describing: type(of: model)))")
        let conversation = model.createConversation(systemPrompt: systemPrompt)
        
        let userPrompt = """
        SOURCES:
        \(sources.block)

        Question:
        \(question)

        Instructions:
        - Answer ONLY using SOURCES.
        - Cite every sentence like [S1], [S2].
        - If not answerable, say "Not enough evidence in sources." and nothing else.
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
        
        return (answer: response, sources: sources.used)
    }
}
