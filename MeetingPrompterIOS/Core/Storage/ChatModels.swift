import Foundation

enum ChatRole: String, Codable, Sendable {
    case user
    case assistant
}

struct ChatMessage: Identifiable, Codable, Sendable {
    var id: String
    var role: ChatRole
    var text: String
    var timestamp: Date
    var sources: [DocumentChunk]?
    var sessionID: String

    init(
        id: String = UUID().uuidString,
        role: ChatRole,
        text: String,
        timestamp: Date = Date(),
        sources: [DocumentChunk]? = nil,
        sessionID: String
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.sources = sources
        self.sessionID = sessionID
    }
}
