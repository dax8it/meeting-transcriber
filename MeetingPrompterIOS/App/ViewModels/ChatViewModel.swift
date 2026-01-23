import Foundation
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isBusy: Bool = false
    @Published var errorMessage: String? = nil

    let session: MeetingSession

    private let chatStore = ChatStore.shared
    private let fileStore = FileStore.shared
    private let searchIndex = SearchIndex.shared
    private let ragService = RAGService.shared

    private let maxHistoryMessages = 10
    private let maxPersistedSources = 8

    init(session: MeetingSession) {
        self.session = session
        Task { await loadHistoryAndIndex() }
    }

    func send() {
        let q = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isBusy else { return }

        print("[Chat] send len=\(q.count)")

        errorMessage = nil
        isBusy = true
        inputText = ""

        let userMessage = ChatMessage(role: .user, text: q, sessionID: session.id)
        messages.append(userMessage)

        let afterUserSnapshot = messages
        Task {
            do {
                try await chatStore.saveMessages(afterUserSnapshot, for: session)
                print("[Chat] saved=\(afterUserSnapshot.count)")
            } catch {
                print("[Chat] save failed: \(error)")
            }

            defer { self.isBusy = false }

            do {
                // Retrieve evidence from the meeting-scoped index.
                let retrieved = (try? await searchIndex.searchMeeting(session: session, query: q, topK: 10)) ?? []
                let summaryChunks = (try? await searchIndex.fetchMeetingChunks(session: session, title: "Summary", limit: 4)) ?? []

                var mergedByID: [String: DocumentChunk] = [:]
                for c in retrieved { mergedByID[c.id] = c }
                for c in summaryChunks { mergedByID[c.id] = c }
                let mergedChunks = Array(mergedByID.values)

                print("[Chat] retrieved=\(retrieved.count), merged=\(mergedChunks.count)")

                guard !mergedChunks.isEmpty else {
                    let assistant = ChatMessage(
                        role: .assistant,
                        text: "Not enough evidence in sources.",
                        sources: nil,
                        sessionID: session.id
                    )
                    self.messages.append(assistant)
                    try? await chatStore.saveMessages(self.messages, for: self.session)
                    print("[Chat] saved=\(self.messages.count)")
                    return
                }

                // Stable ordering: retrieved first, then summary extras.
                let ordered = retrieved + summaryChunks.filter { sc in
                    !retrieved.contains(where: { $0.id == sc.id })
                }
                let deduped = ordered.reduce(into: [DocumentChunk]()) { acc, c in
                    if !acc.contains(where: { $0.id == c.id }) { acc.append(c) }
                }

                let composedPrompt = self.buildComposedPrompt(currentQuestion: q)
                let result = try await ragService.generateAnswer(question: composedPrompt, chunks: deduped)
                let cappedSources = Array(result.sources.prefix(self.maxPersistedSources))

                let assistant = ChatMessage(
                    role: .assistant,
                    text: result.answer,
                    sources: cappedSources.isEmpty ? nil : cappedSources,
                    sessionID: session.id
                )
                self.messages.append(assistant)

                let afterAssistantSnapshot = self.messages
                try await self.chatStore.saveMessages(afterAssistantSnapshot, for: self.session)
                print("[Chat] saved=\(afterAssistantSnapshot.count)")
            } catch {
                self.errorMessage = error.localizedDescription
                print("[Chat] send failed: \(error)")
            }
        }
    }

    // MARK: - Private

    private func loadHistoryAndIndex() async {
        self.messages = await chatStore.loadMessages(for: session)
        try? await indexMeetingIfNeeded()
    }

    private func indexMeetingIfNeeded() async throws {
        func isPlaceholderSummary(_ text: String) -> Bool {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty || t == "Generating..." || t == "Summary generation failed."
        }

        let transcriptText = (try? await fileStore.readText(from: session.transcriptURL)) ?? ""

        let rawSummary: String
        if let mdURL = session.summaryMarkdownURL {
            rawSummary = (try? await fileStore.readText(from: mdURL)) ?? ""
        } else {
            rawSummary = (try? await fileStore.readText(from: session.summaryURL)) ?? ""
        }

        let summaryText = isPlaceholderSummary(rawSummary) ? "" : rawSummary
        try await searchIndex.indexMeeting(session: session, transcript: transcriptText, summary: summaryText)
    }

    private func buildComposedPrompt(currentQuestion: String) -> String {
        let system = "Answer using ONLY the provided meeting excerpts. Cite sources like [S1]. If the excerpts do not contain the answer, say: Not enough evidence in sources."

        let historyMessages = Array(messages.dropLast().suffix(maxHistoryMessages))
        let historyBlock = historyMessages.map { msg in
            switch msg.role {
            case .user:
                return "User: \(msg.text)"
            case .assistant:
                return "Assistant: \(msg.text)"
            }
        }.joined(separator: "\n")

        if historyBlock.isEmpty {
            return """
            SYSTEM:
            \(system)

            QUESTION:
            \(currentQuestion)
            """
        }

        return """
        SYSTEM:
        \(system)

        CHAT HISTORY:
        \(historyBlock)

        QUESTION:
        \(currentQuestion)
        """
    }
}
