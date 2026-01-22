import Foundation

struct MeetingSession: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var createdAt: Date

    // Optional metadata (MVP leaves these blank)
    var title: String?
    var durationSeconds: Double?

    // Persisted artifacts
    var folderURL: URL
    var audioURL: URL
    var transcriptURL: URL
    var summaryURL: URL
    var summaryMarkdownURL: URL?
    var ragDBURL: URL

    init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        title: String? = nil,
        durationSeconds: Double? = nil,
        folderURL: URL,
        audioURL: URL,
        transcriptURL: URL,
        summaryURL: URL,
        summaryMarkdownURL: URL? = nil,
        ragDBURL: URL
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.durationSeconds = durationSeconds
        self.folderURL = folderURL
        self.audioURL = audioURL
        self.transcriptURL = transcriptURL
        self.summaryURL = summaryURL
        self.summaryMarkdownURL = summaryMarkdownURL
        self.ragDBURL = ragDBURL
    }
}
