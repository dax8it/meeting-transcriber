import Foundation
import SwiftUI
import Combine

extension Notification.Name {
    static let meetingSessionArtifactsUpdated = Notification.Name("MeetingSessionArtifactsUpdated")
}

@MainActor
final class SessionViewModel: ObservableObject {
    @Published var transcriptText: String = ""
    @Published var summaryText: String = ""
    @Published var summaryReady: Bool = false
    @Published var shareURL: URL? = nil

    @Published var questionText: String = ""
    @Published var answerText: String = ""
    @Published var sources: [DocumentChunk] = []
    @Published var isBusy: Bool = false
    @Published var errorMessage: String? = nil

    let session: MeetingSession

    private let fileStore = FileStore.shared
    private let ragService = RAGService.shared
    private let searchIndex = SearchIndex.shared

    private var cancellables: Set<AnyCancellable> = []

    init(session: MeetingSession) {
        self.session = session

        NotificationCenter.default.publisher(for: .meetingSessionArtifactsUpdated)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self else { return }
                let id = notification.userInfo?["sessionID"] as? String
                guard id == self.session.id else { return }
                Task { await self.reloadArtifacts() }
            }
            .store(in: &cancellables)
    }

    func reloadArtifacts() async {
        func isPlaceholderSummary(_ text: String) -> Bool {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty || t == "Generating..." || t == "Summary generation failed."
        }

        func fileExistsAndNonEmpty(_ url: URL) -> Bool {
            let fm = FileManager.default
            guard fm.fileExists(atPath: url.path) else { return false }
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let size = attrs?[.size] as? NSNumber
            return (size?.intValue ?? 0) > 0
        }

        do {
            transcriptText = try await fileStore.readText(from: session.transcriptURL)
        } catch {
            transcriptText = ""
            errorMessage = "Failed to read transcript: \(error.localizedDescription)"
        }

        let mdText: String?
        if let mdURL = session.summaryMarkdownURL {
            mdText = try? await fileStore.readText(from: mdURL)
        } else {
            mdText = nil
        }

        let txtText = try? await fileStore.readText(from: session.summaryURL)

        if let mdText, !isPlaceholderSummary(mdText) {
            summaryText = mdText
        } else if let txtText {
            summaryText = txtText
        } else {
            summaryText = mdText ?? ""
        }

        let trimmedSummary = summaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        summaryReady = !trimmedSummary.isEmpty && trimmedSummary != "Generating..." && trimmedSummary != "Summary generation failed."

        // Share fix: prefer sharing .txt; if only .md exists, create a sibling .txt.
        shareURL = nil
        if summaryReady {
            if session.summaryURL.pathExtension.lowercased() == "txt" {
                if fileExistsAndNonEmpty(session.summaryURL) {
                    shareURL = session.summaryURL
                } else {
                    do {
                        try await fileStore.writeTextReplacingItem(trimmedSummary + "\n", to: session.summaryURL)
                        if fileExistsAndNonEmpty(session.summaryURL) {
                            shareURL = session.summaryURL
                        }
                    } catch {
                        print("[SessionViewModel] Failed to create share txt: \(error)")
                    }
                }
            } else if let mdURL = session.summaryMarkdownURL {
                let txtURL = mdURL.deletingPathExtension().appendingPathExtension("txt")
                do {
                    try await fileStore.writeTextReplacingItem(trimmedSummary + "\n", to: txtURL)
                    if fileExistsAndNonEmpty(txtURL) {
                        shareURL = txtURL
                    }
                } catch {
                    print("[SessionViewModel] Failed to create share txt from md: \(error)")
                }
            } else {
                // Backward-compat: older sessions used summaryURL as .md.
                let txtURL = session.summaryURL.deletingPathExtension().appendingPathExtension("txt")
                do {
                    try await fileStore.writeTextReplacingItem(trimmedSummary + "\n", to: txtURL)
                    if fileExistsAndNonEmpty(txtURL) {
                        shareURL = txtURL
                    }
                } catch {
                    print("[SessionViewModel] Failed to create share txt from legacy summaryURL: \(error)")
                }
            }
        }

        // Phase E: index transcript + summary into meeting-scoped DB.
        do {
            try await searchIndex.indexMeeting(session: session, transcript: transcriptText, summary: summaryText)
        } catch {
            // Non-fatal: allow UI to proceed.
            print("[SessionViewModel] Failed to index meeting: \(error)")
        }
    }

    func ask() {
        let q = questionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        let citationsRequested = QueryIntent.citationsRequested(q)

        isBusy = true
        answerText = ""
        sources = []

        Task {
            defer { Task { @MainActor in self.isBusy = false } }

            do {
                // MVP: retrieve more, then always include some summary chunks.
                let retrieved = try await searchIndex.searchMeeting(session: session, query: q, topK: 8)
                let summaryChunks: [DocumentChunk]
                if self.summaryReady {
                    summaryChunks = (try? await searchIndex.fetchMeetingChunks(session: session, title: "Summary", limit: 4)) ?? []
                } else {
                    summaryChunks = []
                }

                var mergedByID: [String: DocumentChunk] = [:]
                for c in retrieved { mergedByID[c.id] = c }
                for c in summaryChunks { mergedByID[c.id] = c }

                let mergedChunks = Array(mergedByID.values)
                if mergedChunks.isEmpty {
                    await MainActor.run {
                        self.answerText = "Not enough evidence in sources."
                        self.sources = []
                    }
                    return
                }

                // Stable ordering for citations: put retrieved first, then summary extras.
                let ordered = retrieved + summaryChunks.filter { sc in
                    !retrieved.contains(where: { $0.id == sc.id })
                }
                let deduped = ordered.reduce(into: [DocumentChunk]()) { acc, c in
                    if !acc.contains(where: { $0.id == c.id }) { acc.append(c) }
                }

                let result = try await ragService.generateAnswer(question: q, chunks: deduped)
                let finalAnswer = citationsRequested ? result.answer : QueryIntent.stripCitationMarkers(result.answer)
                await MainActor.run {
                    self.answerText = finalAnswer
                    self.sources = citationsRequested ? result.sources : []
                }
            } catch {
                await MainActor.run {
                    self.answerText = "Error: \(error.localizedDescription)"
                    self.sources = []
                }
            }
        }
    }
}
